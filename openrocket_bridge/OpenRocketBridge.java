import info.openrocket.core.document.OpenRocketDocument;
import info.openrocket.core.document.Simulation;
import info.openrocket.core.file.GeneralRocketLoader;
import info.openrocket.core.aerodynamics.AerodynamicForces;
import info.openrocket.core.aerodynamics.FlightConditions;
import info.openrocket.core.masscalc.MassCalculator;
import info.openrocket.core.masscalc.RigidBody;
import info.openrocket.core.simulation.AccelerationData;
import info.openrocket.core.simulation.FlightDataType;
import info.openrocket.core.simulation.FlightEvent;
import info.openrocket.core.simulation.MotorClusterState;
import info.openrocket.core.simulation.SimulationOptions;
import info.openrocket.core.simulation.SimulationStatus;
import info.openrocket.core.simulation.exception.SimulationException;
import info.openrocket.core.simulation.listeners.AbstractSimulationListener;
import info.openrocket.core.startup.OpenRocketCore;
import info.openrocket.core.util.Coordinate;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileDescriptor;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.PrintStream;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * Headless OpenRocket driver for Godot.
 *
 * Usage: java -cp OpenRocket-24.12.jar:. OpenRocketBridge rocket.ork simulationIndex [options]
 *   --infinite-fuel    the motor never burns out: once it is past the middle of its burn, thrust
 *                      is held at no less than the motor's average thrust, and no ejection charge fires
 *   --thrust-scale <k> with --infinite-fuel: the held thrust is k times the motor's average thrust
 *   --max-speed <m/s>  with --infinite-fuel: throttle the held thrust back as the rocket nears this
 *                      speed (OpenRocket's model rocket tumbles if it is pushed far past Mach 4)
 *   --max-time <s>     end the simulation after this many seconds of flight
 *   --max-altitude <m> end the simulation once the rocket is this high
 *   --calm             no wind and a vertical launch rod, so the rocket flies straight up
 *   --vehicle <k=v,..> fly a full-scale launch vehicle through OpenRocket's integrator instead of the
 *                      model rocket in the .ork file (which then only supplies the aerodynamic shape).
 *                      See the Vehicle class for the keys. The flight ends at MECO (propellant spent)
 *                      or when the physics breaks the vehicle.
 *
 * Line protocol on stdout (all SI units, OpenRocket world frame: x east, y north, z up):
 *   INFO,<length>,<radius>,<name>         rocket loaded
 *   READY                                 waiting for a LAUNCH line on stdin
 *   STEP,t,px,py,pz,vx,vy,vz,ax,ay,az,thrust   one line per integrator step (a* = unit nose direction)
 *   EVENT,t,<TYPE>                        flight event (LIFTOFF, BURNOUT, APOGEE, ...)
 *   FAIL,t,<CODE>,<value>,<limit>         (--vehicle) the vehicle was lost: NO_LIFTOFF, TANK_RUPTURE,
 *                                         STRUCTURAL_BREAKUP, NOSE_BURNTHROUGH, LOST_CONTROL
 *   MECO,t,alt,vx,vy,vz,mass              (--vehicle) stage-1 burnout state, world frame
 *   SUMMARY,k=v,...                       (--vehicle) peak loads met in flight and their limits
 *   DONE                                  simulation finished
 *   ERROR,<message>
 */
public class OpenRocketBridge {

    public static void main(String[] args) throws Exception {
        // Keep the protocol stream private; OpenRocket's logging must not leak into it.
        PrintStream out = new PrintStream(new FileOutputStream(FileDescriptor.out), true);
        PrintStream sink = new PrintStream(OutputStream.nullOutputStream());
        System.setOut(sink);
        System.setErr(sink);

        try {
            if (args.length < 1) {
                throw new IllegalArgumentException("no .ork file given");
            }
            OpenRocketCore.initialize();

            OpenRocketDocument doc = new GeneralRocketLoader(new File(args[0])).load();
            int index = args.length > 1 ? Integer.parseInt(args[1]) : 0;
            Simulation sim = doc.getSimulation(index);

            boolean infiniteFuel = false;
            double maxTime = Double.POSITIVE_INFINITY;
            double maxAltitude = Double.POSITIVE_INFINITY;
            double thrustScale = 1.0;
            double maxSpeed = Double.POSITIVE_INFINITY;
            Vehicle vehicle = null;
            boolean calm = false;
            for (int i = 2; i < args.length; i++) {
                switch (args[i]) {
                    case "--infinite-fuel" -> infiniteFuel = true;
                    case "--max-time" -> maxTime = Double.parseDouble(args[++i]);
                    case "--max-altitude" -> maxAltitude = Double.parseDouble(args[++i]);
                    case "--max-speed" -> maxSpeed = Double.parseDouble(args[++i]);
                    case "--thrust-scale" -> thrustScale = Double.parseDouble(args[++i]);
                    case "--vehicle" -> vehicle = new Vehicle(args[++i]);
                    case "--calm" -> {
                        calm = true;
                        SimulationOptions options = sim.getOptions();
                        options.setWindSpeedAverage(0);
                        options.setWindSpeedDeviation(0);
                        options.setWindTurbulenceIntensity(0);
                        options.setLaunchIntoWind(false);
                        options.setLaunchRodAngle(0);
                    }
                    default -> throw new IllegalArgumentException("unknown option " + args[i]);
                }
            }

            out.printf(Locale.ROOT, "INFO,%.4f,%.4f,%s%n",
                    sim.getActiveConfiguration().getLength(),
                    doc.getRocket().getBoundingRadius(),
                    doc.getRocket().getName().replace(',', ' '));
            out.println("READY");

            // Godot decides when the flight starts.
            BufferedReader in = new BufferedReader(new InputStreamReader(System.in));
            String line;
            while ((line = in.readLine()) != null) {
                if (line.trim().equals("LAUNCH")) {
                    break;
                }
            }
            if (line == null) {
                return; // Godot went away before launching
            }

            Streamer streamer = new Streamer(out, infiniteFuel, thrustScale, maxSpeed, maxTime, maxAltitude);
            if (vehicle != null) {
                vehicle.structureMass = MassCalculator.calculateStructure(sim.getActiveConfiguration()).getMass();
                vehicle.modelLength = sim.getActiveConfiguration().getLength();
                sim.getOptions().setMaxSimulationTime(Math.max(600, sim.getOptions().getMaxSimulationTime()));
                sim.getOptions().setLaunchRodAngle(0);
                sim.simulate(new VehicleFlight(out, vehicle, calm), streamer);
            } else {
                sim.simulate(streamer);
            }
            out.println("DONE");
        } catch (Throwable t) {
            out.println("ERROR," + String.valueOf(t).replace('\n', ' '));
        }
        out.flush();
        System.exit(0);
    }

    /**
     * A full-scale launch vehicle, described by physical quantities (SI units). Keys of --vehicle:
     *   dry_mass       everything that is not stage-1 propellant: structure, upper stage, payload (kg)
     *   propellant     stage-1 propellant on board at liftoff (kg)
     *   thrust_sl / thrust_vac   stage-1 thrust at sea level and in vacuum (N)
     *   isp_vac        stage-1 vacuum specific impulse (s); mass flow = thrust_vac / (isp_vac * g0)
     *   ref_area       aerodynamic reference area (m2)       length  vehicle length (m)
     *   cg_dry / cg_prop   centre of mass of the dry vehicle / of the propellant, from the nose, 0..1
     *   static_margin  distance centre of pressure - centre of mass at liftoff, in calibres (+ = stable)
     *   gimbal_max     largest engine deflection the attitude control can command (deg)
     *   q_alpha_limit  bending load the airframe survives: dynamic pressure x angle of attack (Pa rad)
     *   tank_limit     burst pressure of the weakest propellant tank (Pa)
     *   ullage / prop_density / column   tank gas pressure (Pa), liquid density (kg/m3) and height of
     *                  the liquid column that the tank bottom carries under acceleration (m)
     *   heat_limit     heat flux the nose survives (W/m2)      nose_radius  (m)
     *   wind_ground / wind_jet   wind speed at the ground and in the jet stream at 11 km (m/s)
     */
    private static class Vehicle {
        static final double G0 = 9.80665;
        final Map<String, Double> values = new HashMap<>();
        double structureMass; // of the .ork model, to tell its mass calculation from the motor's
        double modelLength;

        Vehicle(String spec) {
            for (String pair : spec.split(",")) {
                String[] kv = pair.split("=");
                values.put(kv[0].trim(), Double.parseDouble(kv[1]));
            }
        }

        double get(String key) {
            Double v = values.get(key);
            if (v == null) {
                throw new IllegalArgumentException("--vehicle is missing " + key);
            }
            return v;
        }
    }

    /** Replaces the model rocket's mass, thrust and aerodynamic scale by the vehicle's, every step. */
    private static class VehicleFlight extends AbstractSimulationListener {
        private final PrintStream out;
        private final Vehicle v;
        private final double dryMass, thrustSl, thrustVac, massFlow, refArea, length, cgDry, cgProp;
        private final double staticMargin, gimbalMax, qAlphaLimit, tankLimit, ullage, propDensity, column;
        private final double heatLimit, noseRadius, windGround, windJet, propellant0;

        private double propellant;
        private double lastTime = Double.NaN;
        private double pressure = 101325, density = 1.225;
        private double refLength = 1, modelArea = 1, cgX = 0, mass = 1, inertia = 1, thrust = 0;
        private double aoa = 0, airSpeed = 0;
        private boolean failed = false, ended = false, meco = false;
        private double endAt = Double.POSITIVE_INFINITY;
        private double maxQ = 0, maxQAlpha = 0, maxTank = 0, maxHeat = 0, maxAccel = 0, maxTilt = 0, maxGimbal = 0;
        private double gimbal = 0;

        VehicleFlight(PrintStream out, Vehicle v, boolean calm) {
            this.out = out;
            this.v = v;
            dryMass = v.get("dry_mass");
            propellant0 = propellant = v.get("propellant");
            thrustSl = v.get("thrust_sl");
            thrustVac = v.get("thrust_vac");
            massFlow = thrustVac / (v.get("isp_vac") * Vehicle.G0);
            refArea = v.get("ref_area");
            length = v.get("length");
            cgDry = v.get("cg_dry");
            cgProp = v.get("cg_prop");
            staticMargin = v.get("static_margin");
            gimbalMax = Math.toRadians(v.get("gimbal_max"));
            qAlphaLimit = v.get("q_alpha_limit");
            tankLimit = v.get("tank_limit");
            ullage = v.get("ullage");
            propDensity = v.get("prop_density");
            column = v.get("column");
            heatLimit = v.get("heat_limit");
            noseRadius = v.get("nose_radius");
            windGround = calm ? 0 : v.get("wind_ground");
            windJet = calm ? 0 : v.get("wind_jet");
        }

        private boolean burning() {
            return !failed && propellant > 0;
        }

        // ---- mass: dry vehicle + the propellant still on board ----
        @Override
        public RigidBody postMassCalculation(SimulationStatus status, RigidBody body) {
            if (Math.abs(body.getMass() - v.structureMass) > 1e-9) {
                return RigidBody.EMPTY; // the model motor's mass: already part of the vehicle
            }
            mass = dryMass + Math.max(0, propellant);
            double cg = (dryMass * cgDry + Math.max(0, propellant) * cgProp) / mass;
            cgX = cg * v.modelLength;
            // Slender body. Angles in the simulation are real; lengths along the body are the model's,
            // so the moment of inertia carries one factor of the length scale (see TVC and aero moments).
            double scale = length / v.modelLength;
            inertia = mass * v.modelLength * v.modelLength / 12.0 * scale;
            double roll = mass * refLength * refLength / 8.0 * scale;
            return new RigidBody(new info.openrocket.core.util.Coordinate(cgX, 0, 0, mass), roll, inertia, inertia);
        }

        // ---- thrust: falls with ambient pressure, stops when the propellant is gone ----
        @Override
        public double postSimpleThrustCalculation(SimulationStatus status, double modelThrust) {
            thrust = burning() ? thrustVac - (thrustVac - thrustSl) * pressure / 101325.0 : 0;
            return thrust;
        }

        // ---- wind: light at the ground, a jet stream around 11 km; blows from the east ----
        @Override
        public Coordinate postWindModel(SimulationStatus status, Coordinate wind) {
            double h = status.getRocketPosition().z;
            double jet = Math.exp(-Math.pow((h - 11000.0) / 4000.0, 2));
            return new Coordinate(-(windGround + (windJet - windGround) * jet), 0, 0);
        }

        @Override
        public FlightConditions postFlightConditions(SimulationStatus status, FlightConditions c) {
            pressure = c.getAtmosphericConditions().getPressure();
            density = c.getAtmosphericConditions().getDensity();
            refLength = c.getRefLength();
            modelArea = c.getRefArea();
            aoa = c.getAOA();
            airSpeed = c.getVelocity();
            return null;
        }

        // ---- aerodynamics: OpenRocket's coefficients for the shape, on the vehicle's real area ----
        @Override
        public AerodynamicForces postAerodynamicCalculation(SimulationStatus status, AerodynamicForces f) {
            double k = refArea / modelArea;
            double cn = f.getCN() * k;
            double cside = f.getCside() * k;
            f.setCN(cn);
            f.setCside(cside);
            // Centre of pressure: static_margin calibres behind the liftoff centre of mass.
            double cg0 = (dryMass * cgDry + propellant0 * cgProp) / (dryMass + propellant0) * v.modelLength;
            double arm = cg0 / refLength + staticMargin * (refLength * Math.sqrt(k)) / (length / v.modelLength) / refLength;
            f.setCm(cn * arm);
            f.setCyaw(cside * arm);
            f.setCDaxial(f.getCDaxial() * k);
            f.setCD(f.getCD() * k);
            f.setPitchDampingMoment(f.getPitchDampingMoment() * k);
            f.setYawDampingMoment(f.getYawDampingMoment() * k);
            return f;
        }

        // ---- attitude control: engine gimbal holds the nose vertical, as far as the hardware can ----
        @Override
        public AccelerationData postAccelerationCalculation(SimulationStatus status, AccelerationData a) {
            if (!burning() || !status.isLaunchRodCleared()) {
                gimbal = 0;
                return null;
            }
            Coordinate nose = status.getRocketOrientationQuaternion().rotateZ();
            Coordinate error = nose.cross(new Coordinate(0, 0, 1)); // rotation that rights the nose
            Coordinate rate = status.getRocketRotationVelocity();
            rate = rate.sub(nose.multiply(rate.dot(nose))); // pitch and yaw only
            Coordinate wanted = error.multiply(1.0).sub(rate.multiply(1.4)); // rad/s2, PD law
            // What the engines can deliver: thrust x sin(gimbal) x arm / inertia (arm in model metres).
            double armModel = v.modelLength - cgX;
            double perRadian = thrust * armModel / inertia;
            double need = wanted.length() / Math.max(perRadian, 1e-12);
            gimbal = Math.min(need, Math.sin(gimbalMax));
            if (need > gimbal && need > 0) {
                wanted = wanted.multiply(gimbal / need);
            }
            return new AccelerationData(null, null, a.getLinearAccelerationWC(),
                    a.getRotationalAccelerationWC().add(wanted), status.getRocketOrientationQuaternion());
        }

        @Override
        public void postStep(SimulationStatus status) throws SimulationException {
            double now = status.getSimulationTime();
            double dt = Double.isNaN(lastTime) ? 0 : now - lastTime;
            lastTime = now;
            Coordinate p = status.getRocketPosition();
            Coordinate vel = status.getRocketVelocity();
            if (ended) {
                return;
            }
            if (failed || meco) {
                if (now >= endAt) {
                    end(status);
                }
                return;
            }
            if (thrust > 0) {
                propellant -= massFlow * dt;
            }

            // Loads the flight puts on the hardware.
            double q = 0.5 * density * airSpeed * airSpeed;
            double qAlpha = q * Math.abs(aoa);
            double accel = thrust / mass; // what the structure and the liquids feel
            double tank = ullage + propDensity * accel * column;
            double heat = 1.7415e-4 * Math.sqrt(density / noseRadius) * Math.pow(airSpeed, 3);
            double tilt = Math.acos(Math.max(-1, Math.min(1, status.getRocketOrientationQuaternion().rotateZ().z)));
            maxQ = Math.max(maxQ, q);
            maxAccel = Math.max(maxAccel, accel);
            maxTilt = Math.max(maxTilt, tilt);
            maxGimbal = Math.max(maxGimbal, Math.asin(Math.min(1, gimbal)));
            if (status.isLaunchRodCleared()) {
                maxQAlpha = Math.max(maxQAlpha, qAlpha);
            }
            maxTank = Math.max(maxTank, tank);
            maxHeat = Math.max(maxHeat, heat);

            if (tank > tankLimit) {
                fail(status, "TANK_RUPTURE", tank, tankLimit);
            } else if (status.isLaunchRodCleared() && qAlpha > qAlphaLimit) {
                fail(status, "STRUCTURAL_BREAKUP", qAlpha, qAlphaLimit);
            } else if (heat > heatLimit) {
                fail(status, "NOSE_BURNTHROUGH", heat, heatLimit);
            } else if (now > 8 && p.z < 1) {
                fail(status, "NO_LIFTOFF", thrustSl / (mass * Vehicle.G0), 1.0);
            } else if (p.z > 50 && (vel.z < 0 || tilt > Math.toRadians(75))) {
                fail(status, "LOST_CONTROL", Math.toDegrees(tilt), 75);
            } else if (propellant <= 0) {
                meco = true;
                endAt = now;
                out.printf(Locale.ROOT, "MECO,%.3f,%.1f,%.3f,%.3f,%.3f,%.1f%n", now, p.z, vel.x, vel.y, vel.z, dryMass);
                end(status);
            }
        }

        private void fail(SimulationStatus status, String code, double value, double limit) {
            failed = true;
            thrust = 0;
            endAt = status.getSimulationTime() + 6; // show the wreck falling for a moment
            out.printf(Locale.ROOT, "FAIL,%.3f,%s,%.5g,%.5g%n", status.getSimulationTime(), code, value, limit);
        }

        private void end(SimulationStatus status) {
            ended = true;
            out.printf(Locale.ROOT,
                    "SUMMARY,max_q=%.1f,max_q_alpha=%.1f,q_alpha_limit=%.1f,max_tank=%.1f,tank_limit=%.1f,"
                            + "max_heat=%.1f,heat_limit=%.1f,max_accel=%.3f,max_tilt_deg=%.3f,max_gimbal_deg=%.4f,"
                            + "gimbal_limit_deg=%.4f,propellant_left=%.1f%n",
                    maxQ, maxQAlpha, qAlphaLimit, maxTank, tankLimit, maxHeat, heatLimit, maxAccel,
                    Math.toDegrees(maxTilt), Math.toDegrees(maxGimbal), Math.toDegrees(gimbalMax), Math.max(0, propellant));
            status.getEventQueue().add(new FlightEvent(FlightEvent.Type.SIMULATION_END, status.getSimulationTime()));
        }

        @Override
        public boolean handleFlightEvent(SimulationStatus status, FlightEvent event) {
            FlightEvent.Type type = event.getType();
            // The model motor's own burnout, ejection charge and parachute play no part.
            return !(type == FlightEvent.Type.BURNOUT || type == FlightEvent.Type.EJECTION_CHARGE
                    || type == FlightEvent.Type.RECOVERY_DEVICE_DEPLOYMENT || type == FlightEvent.Type.TUMBLE);
        }
    }

    private static class Streamer extends AbstractSimulationListener {
        private final PrintStream out;

        private final boolean infiniteFuel;
        private final double thrustScale;
        private final double maxSpeed;
        private final double maxTime;
        private final double maxAltitude;
        private double ignitionTime = Double.NaN;
        private boolean endRequested = false;

        Streamer(PrintStream out, boolean infiniteFuel, double thrustScale, double maxSpeed, double maxTime, double maxAltitude) {
            this.maxSpeed = maxSpeed;
            this.out = out;
            this.infiniteFuel = infiniteFuel;
            this.thrustScale = thrustScale;
            this.maxTime = maxTime;
            this.maxAltitude = maxAltitude;
        }

        @Override
        public double postSimpleThrustCalculation(SimulationStatus status, double thrust) throws SimulationException {
            if (!infiniteFuel) {
                return Double.NaN; // keep OpenRocket's value
            }
            double now = status.getSimulationTime();
            if (Double.isNaN(ignitionTime)) {
                if (thrust > 0) {
                    ignitionTime = now;
                }
                return Double.NaN;
            }
            double sustain = 0;
            double burnTime = 0;
            for (MotorClusterState motor : status.getMotors()) {
                sustain += motor.getMotor().getAverageThrustEstimate();
                burnTime = Math.max(burnTime, motor.getMotor().getBurnTimeEstimate());
            }
            if (now - ignitionTime < burnTime * 0.5) {
                return Double.NaN;
            }
            // Ease the throttle off over the last 5 % below the speed limit.
            double speed = status.getRocketVelocity().length();
            double throttle = Math.max(0, Math.min(1, (maxSpeed - speed) / (0.05 * maxSpeed)));
            return Math.max(thrust, sustain * thrustScale * throttle);
        }

        @Override
        public void postStep(SimulationStatus status) throws SimulationException {
            Coordinate p = status.getRocketPosition();
            Coordinate v = status.getRocketVelocity();
            Coordinate a = status.getRocketOrientationQuaternion().rotateZ();
            double thrust = status.getFlightDataBranch().getLast(FlightDataType.TYPE_THRUST_FORCE);
            if (Double.isNaN(thrust)) {
                thrust = 0;
            }
            out.printf(Locale.ROOT, "STEP,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.5f,%.5f,%.5f,%.3f%n",
                    status.getSimulationTime(), p.x, p.y, p.z, v.x, v.y, v.z, a.x, a.y, a.z, thrust);
            if (!endRequested && (status.getSimulationTime() >= maxTime || p.z >= maxAltitude)) {
                endRequested = true;
                status.getEventQueue().add(new FlightEvent(FlightEvent.Type.SIMULATION_END, status.getSimulationTime()));
            }
        }

        @Override
        public boolean handleFlightEvent(SimulationStatus status, FlightEvent event) throws SimulationException {
            FlightEvent.Type type = event.getType();
            if (infiniteFuel && (type == FlightEvent.Type.BURNOUT || type == FlightEvent.Type.EJECTION_CHARGE
                    || type == FlightEvent.Type.RECOVERY_DEVICE_DEPLOYMENT)) {
                return false; // the motor keeps burning
            }
            if (type != FlightEvent.Type.ALTITUDE) {
                out.printf(Locale.ROOT, "EVENT,%.4f,%s%n", event.getTime(), event.getType().name());
            }
            return true;
        }
    }
}
