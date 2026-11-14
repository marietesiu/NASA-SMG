# OpenRocket Deep Technical Architecture & Godot 4 Integration Specification

> **Document Purpose & Target Consumer:** This specification is engineered as a complete, self-contained technical knowledge base for an AI agent or software architect tasked with understanding OpenRocket's internal physics, data structures, and simulation pipeline, and integrating or porting them into the **Godot Engine (4.x)**.

---

## 1. System Overview & Architectural Paradigm

**OpenRocket** (target reference: `v24.12+`) is an open-source, six-degrees-of-freedom (6-DOF) model and high-power rocket design and flight simulation suite written in Java. Historically monolithic, modern OpenRocket separates its headless simulation kernel from its user interface via a multi-module build:

* `info.openrocket.core`: Pure headless domain model, aerodynamics engine, atmospheric physics, file parsers, and numerical integrators. Contains **zero** UI (`Swing`/`AWT`) dependencies and can be invoked programmatically or embedded in external applications.
* `info.openrocket.swing`: Desktop graphical frontend, 2D/3D OpenGL/JOGL viewport renderers, and interactive plotting tools.

### Core Paradigm Mismatch: OpenRocket vs. Godot 4

To integrate OpenRocket with Godot, an AI agent must reconcile four fundamental architectural differences:

| Architectural Dimension | OpenRocket (`info.openrocket.core`) | Godot Engine (`4.x`) |
| :--- | :--- | :--- |
| **Runtime & Language** | JVM (Java 11/17/21+), garbage-collected object graph | C++20 core, GDScript, C# (`.NET 8`), GDExtension (C/C++/Rust) |
| **Execution Model** | Event-driven discrete simulation loop (`SimulationEngine`) running faster-than-real-time with adaptive $\Delta t$ | Real-time hierarchical `SceneTree` with fixed physics ticks ($\Delta t = \frac{1}{60}\text{ s}$ or $\frac{1}{120}\text{ s}$) and variable render frames |
| **Coordinate System** | Rocket Body Frame: $+X$ aft (nose to tail), $Y$ and $Z$ radial; World Frame: ENU (East-North-Up) or WGS84 Geodetic | Right-handed 3D Cartesian: $+X$ right, $+Y$ up, $-Z$ forward |
| **Precision** | Strictly 64-bit IEEE 754 `double` across all kinematics and solvers | Default 32-bit `float` (`real_t`), optional `precision=double` engine compilation flag |

---

## 2. OpenRocket Core Domain & Component Hierarchy

Located under `info.openrocket.core.rocketcomponent`, a rocket design is represented as a directed acyclic tree rooted at a `Rocket` object.

### 2.1 Structural Hierarchy

```text
Rocket (Root Container)
 └── AxialStage (Stage 0: Sustainer, Stage 1+: Boosters)
      ├── NoseCone (Ogive, Conical, Ellipsoid, Power Series, Parabolic, Haack/Von Karman)
      ├── BodyTube (Cylindrical airframe segment)
      │    ├── TrapezoidFinSet / EllipticalFinSet / FreeformFinSet / TubeFinSet
      │    ├── Transition (Conical/Ogive shoulder or boat-tail)
      │    ├── LaunchLug / RailButton
      │    ├── InnerTube (Motor mount tube, stuffer tube)
      │    │    ├── EngineBlock / CenteringRing / Bulkhead
      │    │    └── MotorMount (Holds IgnitionConfiguration -> ThrustCurveMotor)
      │    ├── Parachute / Streamer (RecoveryDevice with CD, area, deployment event)
      │    └── MassComponent (Payload, avionics bay, ballast)
      ├── PodSet (Radially offset external pods)
      └── ParallelStage (Strap-on boosters with independent separation events)
```

### 2.2 Coordinate Systems & Exact Basis Transformations

#### A. OpenRocket Rocket Design Frame ($\mathcal{F}_{OR,\text{design}}$)
* **Origin $(0,0,0)$:** Tip of the foremost nose cone.
* **$+X_{OR}$:** Longitudinal axis pointing **aft** (from nose cone toward motor nozzle).
* **$+Y_{OR}$:** Vertical/upward radial axis in default 2D side view.
* **$+Z_{OR}$:** Lateral radial axis completing the right-handed triad ($\hat{X}_{OR} \times \hat{Y}_{OR} = \hat{Z}_{OR}$).

#### B. Godot 3D Local Node Frame ($\mathcal{F}_{Godot}$)
* **Origin $(0,0,0)$:** Typically placed at the rocket's instantaneous Center of Gravity ($\mathbf{X}_{CG}$) for `RigidBody3D` dynamics, or at the nose tip for procedural mesh generation.
* **$-Z_{G}$:** Forward longitudinal axis (pointing toward nose tip).
* **$+Y_{G}$:** Dorsal / up radial axis.
* **$+X_{G}$:** Starboard / right radial axis ($\hat{X}_{G} \times \hat{Y}_{G} = \hat{Z}_{G}$).

#### C. Exact Transformation Matrix ($\mathcal{F}_{OR,\text{design}} \rightarrow \mathcal{F}_{Godot}$)
Given a position vector $\mathbf{p}_{OR} = [x_{OR}, y_{OR}, z_{OR}]^T$ in OpenRocket design coordinates (with origin shifted to $\mathbf{X}_{CG} = [x_{CG}, 0, 0]^T$), the equivalent position $\mathbf{p}_{G} = [x_{G}, y_{G}, z_{G}]^T$ in Godot local space is:

$$
\begin{bmatrix} x_{G} \\ y_{G} \\ z_{G} \end{bmatrix} = \begin{bmatrix} 0 & 0 & 1 \\ 0 & 1 & 0 \\ 1 & 0 & 0 \end{bmatrix} \begin{bmatrix} x_{OR} - x_{CG} \\ y_{OR} \\ z_{OR} \end{bmatrix} = \begin{bmatrix} z_{OR} \\ y_{OR} \\ x_{OR} - x_{CG} \end{bmatrix}
$$

Notice that $+X_{OR}$ (aft) maps directly to $+Z_{G}$ (backward in Godot), meaning the rocket nose points along $-Z_{G}$ (Godot's canonical `Vector3.FORWARD`). The determinant of this transformation matrix is:

$$
\det \begin{bmatrix} 0 & 0 & 1 \\ 0 & 1 & 0 \\ 1 & 0 & 0 \end{bmatrix} = -1
$$

Because the determinant is $-1$ if raw coordinates are mapped without mirroring a radial axis, preserve right-handed chirality ($\det = +1$) by negating $z_{OR}$:

$$
\mathbf{T}_{OR \rightarrow G} = \begin{bmatrix} 0 & 0 & -1 \\ 0 & 1 & 0 \\ 1 & 0 & 0 \end{bmatrix}, \quad \det(\mathbf{T}_{OR \rightarrow G}) = +1
$$

Thus:
* $x_{G} = -z_{OR}$
* $y_{G} = y_{OR}$
* $z_{G} = x_{OR} - x_{CG}$

---

## 3. Aerodynamics & 6-DOF Physics Engine

OpenRocket's aerodynamic solver resides in `info.openrocket.core.aerodynamics` (primarily `BarrowmanCalculator.java`), while its trajectory solver resides in `info.openrocket.core.simulation` (`RK4SimulationStepper.java`).

### 3.1 Extended Barrowman Stability & Normal Force Model

For subsonic and supersonic flight at small angles of attack ($\alpha \rightarrow 0$), OpenRocket computes the normal force coefficient derivative $C_{N\alpha} = \left.\frac{\partial C_N}{\partial \alpha}\right|_{\alpha=0}$ and axial Center of Pressure $X_{CP}$ by summing contributions over all external axisymmetric and planar components, normalized by the reference area $A_{\text{ref}} = \frac{\pi d_{\text{ref}}^2}{4}$.

1. **Nose Cones & Transitions:**
   For a slender body of revolution with inlet area $A_1$ and outlet area $A_2$:
   $$
   (C_{N\alpha})_{\text{body}} = \frac{2 (A_2 - A_1)}{A_{\text{ref}}}
   $$
   The axial Center of Pressure $X_{CP}$ measured from the component's front edge is determined by its volume $\mathcal{V}$:
   $$
   X_{CP,\text{body}} = L - \frac{\mathcal{V}}{A_2 - A_1} \quad (\text{for } A_1 = 0: \; X_{CP} = L - \frac{\mathcal{V}}{A_2})
   $$
   * Conical nose cone: $X_{CP} = \frac{2}{3} L$
   * Tangent ogive nose cone: $X_{CP} \approx 0.466 L$
   * Ellipsoidal nose cone: $X_{CP} = \frac{1}{3} L$

2. **Planar Fin Sets ($N \ge 3$ fins):**
   For a fin set with span $s$, root chord $c_r$, tip chord $c_t$, mid-chord sweep angle $\Lambda_m$, and fin area $A_f = \frac{1}{2}(c_r + c_t)s$:
   $$
   (C_{N\alpha})_{\text{fins}} = K_{TB} \frac{4 N \left(\frac{s}{d_{\text{ref}}}\right)^2}{1 + \sqrt{1 + \left(\frac{2 L_m}{c_r + c_t}\right)^2}}
   $$
   where $L_m = \frac{s}{\cos \Lambda_m}$ is the mid-chord length, and $K_{TB}$ is the body-on-fin interference factor for body radius $r_t$:
   $$
   K_{TB} = 1 + \frac{r_t}{s + r_t}
   $$
   For $N > 4$ fins, OpenRocket applies multi-fin mutual interference attenuation factors (e.g., $\approx 0.948$ for $N=5$, $\approx 0.913$ for $N=6$, $\approx 0.854$ for $N=8$).

3. **High-Angle-of-Attack ($\alpha$) Nonlinear Crossflow Correction:**
   Classical Barrowman theory fails at large $\alpha$ (such as during weathercocking or wind gusts). OpenRocket augments linear $C_{N\alpha}$ with viscous crossflow drag integrated along the body planform area $A_{\text{plan}}$ and fin planform area:
   $$
   C_N(\alpha) = C_{N\alpha} \sin(\alpha) \cos(\alpha) + C_{D,c} \frac{A_{\text{plan}}}{A_{\text{ref}}} \sin^2(\alpha)
   $$
   where $C_{D,c} \approx 1.1\text{--}1.2$ is the cylindrical crossflow drag coefficient.

4. **Static Stability Margin (Calibers):**
   $$
   \text{Stability Margin (cal)} = \frac{X_{CP} - X_{CG}}{d_{\text{ref}}}
   $$
   Positive values ($> 1.0\text{ cal}$ to $2.5\text{ cal}$) indicate restoring aerodynamic pitch/yaw torque; negative values indicate aerodynamic divergence.

### 3.2 Axial Drag Decomposition ($C_D$)

Total axial drag coefficient $C_A$ (converted to wind-axis $C_D$ via $C_D = C_A \cos\alpha + C_N \sin\alpha$) is decomposed into four distinct physical mechanisms:

$$
C_{A,\text{total}} = C_{A,\text{friction}} + C_{A,\text{pressure}} + C_{A,\text{base}} + C_{A,\text{parasitic}}
$$

1. **Skin Friction Drag ($C_{A,\text{friction}}$):**
   Computed from Reynolds number $Re = \frac{\rho V L}{\mu}$ and surface roughness height $k_s$ (e.g., $k_s \approx 0\ \mu\text{m}$ for polished finish, $20\ \mu\text{m}$ for smooth paint, $60\ \mu\text{m}$ for matte/unfinished cardboard):
   * Critical roughness Reynolds number: $Re_{\text{crit}} = 51 \left(\frac{k_s}{L}\right)^{-1.039}$
   * Turbulent skin friction coefficient (Prandtl-Schlichting / Hoerner compressibility-corrected):
     $$
     C_f = \frac{1}{(1.50 \ln Re - 5.6)^2} \cdot \left(1 + 0.15 M^2\right)^{-0.58}
     $$
   * Scaled by wetted area $A_{\text{wet}}$ and fin thickness-to-chord ratio $t/c$:
     $$
     C_{A,\text{friction}} = C_f \left[ \left(1 + \frac{1}{2 (L/d)}\right) \frac{A_{\text{wet,body}}}{A_{\text{ref}}} + \left(1 + \frac{2 t}{c}\right) \frac{A_{\text{wet,fins}}}{A_{\text{ref}}} \right]
     $$

2. **Pressure & Transonic Wave Drag ($C_{A,\text{pressure}}$):**
   * Subsonic ($M < 0.8$): Nose cone and transition forebody pressure drag based on fineness ratio $f_N = L_N / d$.
   * Transonic & Supersonic ($0.8 \le M \le 5.0$): Empirical transonic drag-divergence rise peaking near $M \approx 1.05\text{--}1.2$, followed by supersonic wave drag decay proportional to $\frac{1}{\sqrt{M^2 - 1}}$.

3. **Base Drag ($C_{A,\text{base}}$):**
   Low-pressure wake behind blunt aft ends and boat-tails:
   $$
   C_{A,\text{base,coast}} = \begin{cases} 0.12 + 0.13 M^2 & M < 1 \\ \frac{0.25}{M} & M \ge 1 \end{cases}
   $$
   During motor burn (powered ascent), exhaust plume pressure partially fills the base wake, reducing $C_{A,\text{base}}$ proportionally to the nozzle exit area ratio $A_{\text{nozzle}} / A_{\text{base}}$.

4. **Parasitic Drag ($C_{A,\text{parasitic}}$):**
   Launch lugs, rail buttons, and external pods computed from local boundary layer velocity deficit and frontal area.

### 3.3 Roll Dynamics & Aerodynamic Damping

* **Roll Forcing Moment ($C_{l,\delta}$):** Induced by fin cant angle $\delta_f$ (in radians):
  $$
  C_{l,\delta} = N \cdot (C_{N\alpha})_{1\text{ fin}} \cdot \frac{\bar{y}_{\text{MAC}}}{d_{\text{ref}}} \delta_f
  $$
  where $\bar{y}_{\text{MAC}}$ is the radial distance from the rocket centerline to the fin's Mean Aerodynamic Chord.
* **Roll Damping Moment ($C_{l,p}$):** Opposes angular roll velocity $p = \omega_x$:
  $$
  C_{l,p} = -N \cdot (C_{N\alpha})_{1\text{ fin}} \cdot \frac{p}{2 V} \int_{r_t}^{r_t + s} c(r) r^2 \, dr \cdot \frac{1}{A_{\text{ref}} d_{\text{ref}}}
  $$
* **Pitch/Yaw Damping ($C_{mq}, C_{nr}$):** Combines aerodynamic normal force damping at distance $(X_{CP,i} - X_{CG})^2$ and **propulsive jet damping**:
  $$
  \mathbf{M}_{\text{jet}} = -\dot{m} \left( L_{\text{nozzle}} - X_{CG} \right)^2 \boldsymbol{\omega}_{\perp}
  $$
  where $\dot{m} = -\frac{dm}{dt} > 0$ is the propellant mass exhaust rate.

### 3.4 6-DOF State Vector & RK4 Numerical Integration

`RK4SimulationStepper` integrates a 14-element state vector $\mathbf{y}(t)$ using classical 4th-order Runge-Kutta with adaptive step-size control:

$$
\mathbf{y}(t) = \begin{bmatrix} \mathbf{p}(t) \in \mathbb{R}^3 \\ \mathbf{v}(t) \in \mathbb{R}^3 \\ \mathbf{q}(t) \in \mathbb{H} \\ \boldsymbol{\omega}(t) \in \mathbb{R}^3 \\ m(t) \in \mathbb{R} \end{bmatrix}
$$

* **Translational Kinematics & Dynamics (Inertial Frame):**
  $$
  \frac{d\mathbf{p}}{dt} = \mathbf{v}, \quad \frac{d\mathbf{v}}{dt} = \frac{1}{m(t)} \left( \mathbf{R}(\mathbf{q}) \left[ \mathbf{F}_{\text{thrust}} + \mathbf{F}_{\text{aero}} \right] + \mathbf{F}_{\text{gravity}} + \mathbf{F}_{\text{Coriolis}} \right)
  $$
* **Quaternion Attitude Kinematics:**
  $$
  \frac{d\mathbf{q}}{dt} = \frac{1}{2} \mathbf{q} \otimes \begin{bmatrix} 0 \\ \boldsymbol{\omega} \end{bmatrix}
  $$
* **Euler Rotational Dynamics (Body Frame):**
  $$
  \mathbf{I}(t) \frac{d\boldsymbol{\omega}}{dt} + \boldsymbol{\omega} \times \left( \mathbf{I}(t) \boldsymbol{\omega} \right) = \mathbf{M}_{\text{aero}} + \mathbf{M}_{\text{damping}} + \mathbf{M}_{\text{jet}} - \frac{d\mathbf{I}(t)}{dt} \boldsymbol{\omega}
  $$

#### Flight Phase State Machine (`FlightEvent.Type`)
1. `LAUNCH`: Ignition triggered at $t = 0$. Rocket constrained to 1-DOF linear translation along the launch rod/rail vector $\hat{\mathbf{u}}_{\text{rod}}$ until travel distance $s \ge L_{\text{rod}}$.
2. `LAUNCHROD`: Constraint released; full 6-DOF unconstrained dynamics begin.
3. `BURNOUT`: Propellant mass reaches dry mass; thrust drops to $0$; delay grain countdown begins.
4. `STAGE_SEPARATION`: Booster stage detaches, spawning an independent child `SimulationStatus` instance simulated concurrently.
5. `APOGEE`: Vertical velocity $v_z$ crosses from positive to negative.
6. `EJECTION_CHARGE` / `RECOVERY_DEVICE_DEPLOYMENT`: Parachute or streamer opens; aerodynamic solver switches from Barrowman airframe model to bluff-body canopy drag:
   $$
   \mathbf{F}_{\text{chute}} = -\frac{1}{2} \rho \|\mathbf{v}_{\text{rel}}\| \mathbf{v}_{\text{rel}} \sum_{k} (C_{D,k} A_k)
   $$
7. `GROUND_HIT`: Altitude $z \le z_{\text{ground}}$; simulation terminates.

---

## 4. File Formats & Data Schemas

### 4.1 `.ork` Design Archive Specification

An `.ork` file is a standard **PKZIP** archive containing:

```text
design_name.ork (ZIP Archive)
 ├── rocket.ork          # UTF-8 XML rocket tree, materials, and simulation configurations
 ├── preview.png         # Optional 2D/3D thumbnail render
 ├── thrustcurves/       # Embedded .rse / .eng motor files used by the design
 │    └── *.rse
 └── textures/           # Optional decal PNG/JPG textures referenced by <appearance> tags
```

#### Key XML Elements inside `rocket.ork`
* `<openrocket version="1.10" creator="OpenRocket 24.12">`: Root element.
* `<rocket>` $\rightarrow$ `<subcomponents>` $\rightarrow$ `<stage>`: Structural tree.
* `<material type="bulk|surface|line" density="680.0" inPlaneShearModulus="1.2e8">Balsa</material>`: All internal values are strictly **SI units** ($\text{m}$, $\text{kg}$, $\text{s}$, $\text{rad}$, $\text{Pa}$, $\text{N}$).
* `<finpoints>`: Array of `<point x="..." y="..."/>` coordinates in meters defining custom freeform fin polygons relative to the root leading edge.
* `<simulation status="...">`: Stores launch site elevation, latitude/longitude, rod length/angle, multi-level wind tables, and dispersion settings.

### 4.2 Motor Thrust Curve Formats (`.eng` & `.rse`)

* **RASP (`.eng`):** Space-delimited ASCII file. Header line:
  `Designation Diameter(mm) Length(mm) Delays PropellantMass(kg) TotalMass(kg) Manufacturer`
  Followed by `time(s) thrust(N)` pairs. OpenRocket linearly interpolates $F_T(t)$ between points and computes instantaneous propellant mass $m_p(t)$ proportional to remaining impulse:
  $$
  m_p(t) = m_{p,0} \left( 1 - \frac{\int_0^t F_T(\tau) \, d\tau}{I_{\text{total}}} \right)
  $$
* **RockSim (`.rse`):** XML format supporting explicit time-varying mass points `<eng-data t="..." f="..." m="..."/>` and nozzle geometry.

---

## 5. Godot 4 Integration & Compatibility Architectures

Depending on whether the Godot project requires **offline flight replay**, **real-time hardware/software-in-the-loop (HITL/SITL)**, or **interactive rocket building inside Godot**, select one of the four architectural patterns below.

---

### Pattern A: Offline Baked Telemetry & Aerodynamic Lookup Table (LUT) Playback
**Best for:** High-FPS games, cinematic replays, and procedural missile/rocket trajectories where live structural editing inside Godot is unnecessary.

1. **Telemetry Replay Mode:** Export OpenRocket simulation data as CSV (`Time`, `Position X/Y/Z`, `Velocity X/Y/Z`, `Roll/Pitch/Yaw`, `Angle of Attack`, `Mach`, `Thrust`) and load it into a Godot `Curve3D` or custom binary `Resource`. Interpolate pose via Hermite/cubic splines in `_process(delta)`.
2. **Aerodynamic LUT Mode (Interactive Godot `RigidBody3D`):**
   * Use OpenRocket 24.12's **Component Analysis Parameter Sweep** (or a headless Java script) to sweep:
     * Mach number $M \in [0.0, 4.0]$ (step $0.05$)
     * Angle of attack $\alpha \in [0^\circ, 90^\circ]$ (step $2^\circ$)
   * Export a 2D lookup table of $[C_A(M, \alpha), C_N(M, \alpha), X_{CP}(M, \alpha), C_{l,p}(M)]$.
   * Inside Godot's `RigidBody3D._integrate_forces(state)`, perform bilinear interpolation on $(M, \alpha)$ and apply forces directly to Godot's physics solver.

---

### Pattern B: Local IPC Co-Simulation Daemon (Java `core` $\leftrightarrow$ Godot)
**Best for:** Rapid prototyping, SITL flight computer testing, and zero-C++ compilation setups.

* **Architecture:** Spawn `java -cp OpenRocket.jar CustomHeadlessBridge` as a background OS subprocess (`OS.execute_with_pipe()` in Godot 4.2+), communicating over `stdin`/`stdout` or a localhost TCP/UDP socket using a fixed-size binary packet (64 bytes per step).
* **Synchronization Loop:**
  1. Godot's `_physics_process(delta)` sends control inputs (e.g., active fin deflections $\delta_{\text{pitch}}, \delta_{\text{yaw}}, \delta_{\text{roll}}$, stage ignition triggers, wind gusts) to the Java process.
  2. Java steps `RK4SimulationStepper` forward by `delta` seconds (performing adaptive internal sub-steps).
  3. Java returns `[pos_x, pos_y, pos_z, quat_x, quat_y, quat_z, quat_w, vel_x, vel_y, vel_z, mach, aoa, stage_events]`.
  4. Godot updates the rocket's `Transform3D` and triggers particle emitters (`GPUParticles3D` exhaust plumes, shock diamonds, parachute deployment animations).

---

### Pattern C: GraalVM Native Image + Godot GDExtension / C# P/Invoke (Embedded Production Core)
**Best for:** Commercial or standalone desktop/mobile simulators shipping a single executable without requiring users to install a JVM.

1. **Compile `info.openrocket:core` to Native Shared Library:**
   Write a thin Java facade annotated with GraalVM `@CEntryPoint` methods (`or_load_ork`, `or_init_sim`, `or_step_sim`, `or_get_aero_coeffs`), then compile with GraalVM `native-image --shared` into:
   * `libopenrocket_core.dll` (Windows x64)
   * `libopenrocket_core.so` (Linux x64/arm64)
   * `libopenrocket_core.dylib` (macOS Apple Silicon/Intel)
2. **Bind to Godot 4:**
   * **C# (`.NET 8`):** Use `[LibraryImport("openrocket_core")]` P/Invoke bindings directly inside a Godot C# `Node3D`.
   * **C++ GDExtension:** Wrap the C header in a `Godot::RefCounted` class (`OpenRocketSimulator`) exposed directly to GDScript.

---

### Pattern D: Pure Native Godot Port (`.ork` Importer + GDScript/C# Solver)
**Best for:** In-game rocket editors (Kerbal-style vehicle assembly) where players modify fins, nose cones, and stages inside Godot with zero external runtime dependencies.

1. **`.ork` Importer (`EditorImportPlugin` or Runtime Loader):**
   * Use Godot's built-in `ZIPReader` to extract `rocket.ork` and `textures/*` from any `.ork` file.
   * Parse `rocket.ork` using Godot's `XMLParser` to reconstruct the component hierarchy, masses, materials, and motor curves.
2. **Procedural 3D Mesh Generation (`ArrayMesh` / `SurfaceTool`):**
   * **Axisymmetric Bodies (`NoseCone`, `BodyTube`, `Transition`):** Sample profile radius $r(x)$ at $N_x$ axial stations (e.g., Haack series $r(x) = \frac{R}{\sqrt{\pi}} \sqrt{\theta - \frac{\sin(2\theta)}{2} + C \sin^3\theta}$ where $\theta = \arccos\left(1 - \frac{2x}{L}\right)$) and revolve across $N_\phi$ circumferential segments to generate vertex positions, smooth analytical normals, and cylindrical UV coordinates.
   * **Planar Fins (`TrapezoidFinSet`, `FreeformFinSet`):** Triangulate the 2D fin polygon using `Geometry2D.triangulate_polygon()`, extrude by fin thickness $t$ with beveled/airfoil leading and trailing edges, and instance $N$ times radially around the parent tube at angles $\phi_k = \phi_0 + \frac{2\pi k}{N}$.
3. **Native Godot Physics Integration:**
   * Compute total dry mass $M_{\text{dry}}$, Center of Gravity $\mathbf{X}_{CG}$, and diagonal inertia tensor $\mathbf{I} = \text{diag}(I_{xx}, I_{yy}, I_{zz})$ from component geometry and densities.
   * Execute Barrowman $C_{N\alpha}$, $X_{CP}$, drag $C_D(M, \alpha)$, and thrust curve integration inside `_integrate_forces(PhysicsDirectBodyState3D state)`.

---

## 6. Critical Engineering Rules & Pitfalls for AI Agents

When generating code for Godot + OpenRocket integration, enforce these invariants:

1. **Never Double-Integrate Forces:**
   * If OpenRocket's `RK4SimulationStepper` computes the trajectory (Patterns A, B, or C), **do not** let Godot's `RigidBody3D` simultaneously apply gravity or integrate forces. Either set `RigidBody3D.custom_integrator = true` and overwrite `state.transform` and `state.linear_velocity` directly inside `_integrate_forces`, or use a kinematic `Node3D` / `AnimatableBody3D`.
   * Conversely, if Godot's `RigidBody3D` handles integration (Pattern A LUT or Pattern D), inject only net aerodynamic forces, aerodynamic restoring torques, and motor thrust via `state.apply_central_force()` and `state.apply_torque()`, allowing Godot's physics engine to handle collisions, launch rail `SliderJoint3D` constraints, and rigid-body integration natively.
2. **Large-World Precision & Floating Origin:**
   * High-power rockets routinely exceed $10,000\text{ m}$ to $100,000\text{ m}$ altitude. Standard Godot builds use 32-bit floats (`float32`), which suffer visible vertex jitter beyond $\sim 5,000\text{ m}$ from `(0,0,0)`.
   * **Solution:** Either compile Godot with `precision=double` or implement a **Floating Origin** controller that shifts the world container node whenever the rocket's `global_position.length() > 2000.0`, keeping the rocket near the rendering origin while tracking true `double` coordinates in C# or C++.
3. **Singularity Protection at Zero Airspeed ($V \rightarrow 0$):**
   * On the launch pad before ignition, relative airspeed $\|\mathbf{v}_{\text{rel}}\| = \|\mathbf{v} - \mathbf{v}_{\text{wind}}\|$ may be $0$. Clamp dynamic pressure $q = \frac{1}{2} \rho \|\mathbf{v}_{\text{rel}}\|^2$ and guard division by $V$ in angle-of-attack $\alpha = \operatorname{atan2}(\|\mathbf{v}_{\text{rel},\perp}\|, v_{\text{rel},\parallel})$ and roll damping $C_{l,p} \propto \frac{p}{2V}$ with a threshold $V_{\min} = 10^{-3}\text{ m/s}$.
4. **Launch Rail / Rod Constraint Modeling:**
   * Before the rocket clears the launch rail ($s < L_{\text{rail}}$), lateral aerodynamic forces and wind gusts must not tip the rocket over. In Godot, either constrain motion along the rail axis using a `SliderJoint3D` with locked angular limits until distance traveled exceeds $L_{\text{rail}}$, or project net forces onto the rail unit vector $\hat{\mathbf{u}}_{\text{rail}}$:
     $$
     \mathbf{F}_{\text{constrained}} = \max\left(0, (\mathbf{F}_{\text{thrust}} + \mathbf{F}_{\text{aero}} + \mathbf{F}_{\text{grav}}) \cdot \hat{\mathbf{u}}_{\text{rail}}\right) \hat{\mathbf{u}}_{\text{rail}}
     $$

---

## 7. Reference Implementation Blueprints

### 7.1 Headless Java Simulation Driver (`info.openrocket.core`)

Use this pattern to load an `.ork` file, attach a custom step listener, and stream or extract simulation telemetry from `info.openrocket:core`:

```java
package com.godot.openrocket.bridge;

import info.openrocket.core.database.Databases;
import info.openrocket.core.document.OpenRocketDocument;
import info.openrocket.core.document.Simulation;
import info.openrocket.core.file.GeneralRocketLoader;
import info.openrocket.core.simulation.SimulationOptions;
import info.openrocket.core.simulation.SimulationStatus;
import info.openrocket.core.simulation.exception.SimulationException;
import info.openrocket.core.simulation.listeners.AbstractSimulationListener;
import info.openrocket.core.startup.Application;
import info.openrocket.core.util.Coordinate;
import info.openrocket.core.util.Quaternion;

import java.io.File;

public class HeadlessSimDriver {

    public static void main(String[] args) throws Exception {
        // 1. Initialize headless OpenRocket core databases (materials & thrust curves)
        Application.initialize();
        Databases.fakeMethod(); // Ensures static motor/component database initialization

        // 2. Load .ork design file
        File orkFile = new File("rocket_design.ork");
        GeneralRocketLoader loader = new GeneralRocketLoader(orkFile);
        OpenRocketDocument doc = loader.load();

        // 3. Configure simulation options
        Simulation sim = doc.getSimulation(0);
        SimulationOptions opts = sim.getOptions();
        opts.setLaunchRodLength(1.5);
        opts.setWindSpeedAverage(3.5);

        // 4. Attach real-time step listener to stream state to Godot
        AbstractSimulationListener godotStreamer = new AbstractSimulationListener() {
            @Override
            public void postStep(SimulationStatus status) throws SimulationException {
                double t = status.getSimulationTime();
                Coordinate pos = status.getRocketPosition();       // ENU meters
                Coordinate vel = status.getRocketVelocity();       // m/s
                Quaternion rot = status.getRocketOrientationQuaternion();

                // Map OpenRocket ENU/Body coordinates to Godot right-handed coordinates
                // Emit packet over stdout / socket / shared memory buffer
                System.out.printf("STEP,%.5f,%.4f,%.4f,%.4f,%.5f,%.5f,%.5f,%.5f%n",
                        t, -pos.y, pos.z, -pos.x,
                        rot.getX(), rot.getY(), rot.getZ(), rot.getW());
            }
        };

        // 5. Execute 6-DOF RK4 simulation
        sim.simulate(godotStreamer);
    }
}
```

### 7.2 Godot 4 GDScript `.ork` Archive & XML Extractor

Use this native GDScript pattern in Godot 4 to unpack any `.ork` file directly without external tools:

```gdscript
class_name OrkParser
extends RefCounted

static func parse_ork_file(ork_path: String) -> Dictionary:
	var zip := ZIPReader.new()
	var err := zip.open(ork_path)
	if err != OK:
		push_error("Failed to open .ork archive: %s (Error %d)" % [ork_path, err])
		return {}

	var files := zip.get_files()
	if not files.has("rocket.ork"):
		push_error("Invalid .ork archive: missing rocket.ork XML payload.")
		zip.close()
		return {}

	var xml_bytes := zip.read_file("rocket.ork")
	zip.close()

	var parser := XMLParser.new()
	parser.open_buffer(xml_bytes)

	var rocket_data := {
		"name": "Unnamed Rocket",
		"components": [],
		"simulations": []
	}

	var element_stack: Array[String] = []
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var node_name := parser.get_node_name()
				if not parser.is_empty():
					element_stack.append(node_name)
				if node_name in ["nosecone", "bodytube", "transition", "trapezoidfinset", "freeformfinset", "parachute"]:
					rocket_data["components"].append({
						"type": node_name,
						"attributes": _get_attributes(parser)
					})
			XMLParser.NODE_ELEMENT_END:
				if element_stack.size() > 0:
					element_stack.pop_back()
			XMLParser.NODE_TEXT:
				var text := parser.get_node_data().strip_edges()
				if text != "" and element_stack.size() > 0:
					var current_tag := element_stack[-1]
					if rocket_data["components"].size() > 0:
						rocket_data["components"][-1][current_tag] = text

	return rocket_data

static func _get_attributes(parser: XMLParser) -> Dictionary:
	var attrs := {}
	for i in range(parser.get_attribute_count()):
		attrs[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
	return attrs
```

### 7.3 Godot 4 `RigidBody3D` Native Aerodynamic Force Applicator

Use this GDScript/C# physics pattern when driving a Godot `RigidBody3D` using OpenRocket-derived stability coefficients ($C_N$, $C_A$, $X_{CP}$) and thrust curves:

```gdscript
class_name RocketAeroBody
extends RigidBody3D

@export var reference_area: float = 0.00456     # pi * (d_ref / 2)^2 [m^2]
@export var reference_diameter: float = 0.0762  # d_ref [m]
@export var x_cg_from_nose: float = 0.85        # Instantaneous CG [m]
@export var x_cp_from_nose: float = 1.02        # Barrowman CP [m]
@export var cn_alpha: float = 11.4              # Normal force slope [1/rad]
@export var cd_axial: float = 0.42              # Zero-AoA axial drag coeff
@export var roll_damping_clp: float = -18.5     # Roll damping derivative
@export var wind_velocity: Vector3 = Vector3(3.0, 0.0, -1.5) # World wind [m/s]

var current_thrust: float = 0.0                 # Instantaneous motor thrust [N]
var rail_constrained: bool = true
var rail_length: float = 1.5
var launch_origin: Vector3

func _ready() -> void:
	launch_origin = global_position

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var basis := state.transform.basis
	# Godot forward axis is -Z; OpenRocket aft axis is +Z
	var forward_dir := -basis.z.normalized()
	var aft_dir := basis.z.normalized()

	# 1. Compute relative airspeed vector
	var v_rel := state.linear_velocity - wind_velocity
	var speed := v_rel.length()

	# 2. Atmospheric density (ISA sea-level approximation; replace with ISA altitude model)
	var altitude := maxf(0.0, state.transform.origin.y)
	var rho := 1.225 * exp(-altitude / 8500.0)

	# 3. Propulsive Thrust along rocket longitudinal axis (-Z)
	var thrust_force := forward_dir * current_thrust

	# 4. Aerodynamic Forces & Restoring Moment
	var aero_force := Vector3.ZERO
	var aero_torque := Vector3.ZERO

	if speed > 0.01:
		var v_hat := v_rel / speed
		var q_dyn := 0.5 * rho * speed * speed

		# Angle of attack alpha between rocket nose (-Z) and relative velocity
		var cos_alpha := clampf(forward_dir.dot(v_hat), -1.0, 1.0)
		var alpha := acos(cos_alpha)

		# Normal force direction perpendicular to rocket axis opposing crossflow
		var lateral_vel := v_rel - forward_dir * v_rel.dot(forward_dir)
		var normal_dir := -lateral_vel.normalized() if lateral_vel.length_squared() > 1e-8 else Vector3.ZERO

		# Extended Barrowman + crossflow normal force magnitude
		var cn := cn_alpha * sin(alpha) * cos(alpha) + 1.15 * sin(alpha) * sin(alpha)
		var f_normal := normal_dir * (q_dyn * reference_area * cn)

		# Axial drag force opposing axial airflow
		var f_axial := aft_dir * (q_dyn * reference_area * cd_axial * cos_alpha)
		aero_force = f_normal + f_axial

		# Restoring weathercocking torque: r_cp_cg x F_normal
		# CP is aft of CG (+Z in Godot local space)
		var stability_arm := (x_cp_from_nose - x_cg_from_nose) * aft_dir
		aero_torque += stability_arm.cross(f_normal)

		# Roll damping torque around longitudinal axis
		var roll_rate := state.angular_velocity.dot(forward_dir)
		var cl_roll := roll_damping_clp * (roll_rate * reference_diameter) / (2.0 * speed)
		aero_torque += forward_dir * (q_dyn * reference_area * reference_diameter * cl_roll)

	# 5. Launch Rail 1-DOF Constraint
	if rail_constrained:
		var dist_along_rail := (state.transform.origin - launch_origin).dot(forward_dir)
		if dist_along_rail >= rail_length:
			rail_constrained = false
		else:
			var net_force := thrust_force + aero_force + (state.total_gravity * mass)
			var rail_net := maxf(0.0, net_force.dot(forward_dir))
			state.apply_central_force(forward_dir * rail_net - (state.total_gravity * mass))
			state.angular_velocity = Vector3.ZERO
			return

	state.apply_central_force(thrust_force + aero_force)
	state.apply_torque(aero_torque)
```