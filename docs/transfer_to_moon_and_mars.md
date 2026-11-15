# How the Moon's or Mars' displacement is used to plan the launch

This describes the calculation that turns "where the target is" into "how and when to launch".
It is a description of the method with worked numbers. **The project does not implement it yet**
(`project.md` already notes that the Moon and Mars missions have no transfer model); the
transit scene (`transit.tscn`) only shows the trip.

## 1. What "displacement" means here

The displacement is the vector from the Earth to the target:

```
d = r_target(t_arrival) - r_Earth(t_departure)
```

Two things in it matter, and they are used differently:

| Part of the displacement | Used for |
|---|---|
| Its **length** `|d|` (the distance) | the size of the transfer orbit, and therefore the **speed** the rocket needs, the **flight time**, and the **propellant** |
| Its **direction** and **when it is evaluated** | **when** to launch and **which way** to point, because the target moves while the rocket is on its way |

The crucial point: **the target must be located where it will be on arrival, not where it is at
launch.** The Moon moves about 1 km/s along its orbit and Mars about 24 km/s along its own, so
aiming at where they are now would miss by a huge margin.

(The Moon's *displacement map*, `Moon+Displacement.tif`, is something else: terrain height. It
shades the Moon model and would matter for choosing a landing site, but it plays no part in the
launch calculation.)

## 2. Step by step

Assumptions for every number below: parking orbit 200 km above the Earth (radius 6,571 km,
circular speed 7.788 km/s), two-body motion, planar circular orbits for Mars. These are first
estimates; real mission design refines them (section 4).

### Step 1: the distance sets the transfer orbit, and the transfer orbit sets the burn

The rocket leaves the parking orbit on an ellipse that touches the parking orbit at one end and
reaches the target's distance at the other:

```
a = (r_park + |d|) / 2                          semi-major axis of the transfer ellipse
v_burn = sqrt( mu * (2/r_park - 1/a) )          speed needed at the burn (vis-viva)
dv = v_burn - v_circular                        the burn: the rocket's "delta-v"
```

| | Moon | Mars |
|---|---|---|
| Distance used | 384,400 km (mean Earth-Moon) | 227.9 million km from the Sun (Earth is at 149.6) |
| Transfer ellipse `a` | 195,486 km (around the Earth) | 188.8 million km (around the Sun) |
| Speed needed beyond escape | - | `v_inf` = 2.945 km/s relative to the Earth |
| **Departure burn from 200 km orbit** | **3.133 km/s** | **3.613 km/s** |

For Mars the Sun's gravity is what the rocket has to climb, so the burn is computed in two parts:
first the speed relative to the Earth, `v_inf = v_transfer_perihelion - v_Earth = 32.729 - 29.785`,
then the burn that leaves the Earth with that excess, `dv = sqrt(v_inf^2 + 2*mu_Earth/r_park) - v_circular`.

A larger distance means a bigger ellipse and a bigger burn. The Moon's distance varies from
363,300 to 405,500 km over each orbit, which changes the burn only a little (3.128 to 3.138 km/s)
but changes the flight time a lot (next step).

The burn becomes propellant through the rocket equation `m_initial / m_final = exp(dv / v_e)`.
For an example upper stage with Isp 348 s (`v_e` = 3.413 km/s) that is a mass
ratio of 2.50 for the Moon burn and 2.88 for the Mars burn. This is how the displacement feeds the
**component choice**: engine Isp, propellant load and dry mass all have to cover this `dv`.

### Step 2: the distance sets the flight time (Kepler's third law)

Half an ellipse takes `t = pi * sqrt(a^3 / mu)`:

| | Moon | Mars |
|---|---|---|
| Flight time | 4.98 days (4.58 to 5.39 days across the Moon's distance range) | 258.9 days (8.5 months) |

(Real lunar missions are faster, about 3 days, by burning a little harder so the ellipse reaches
beyond the Moon's distance. That trades more propellant for less time.)

### Step 3: the flight time sets the lead angle, and so the launch window

During the flight the rocket sweeps half an orbit (180 degrees) around the central body. The
target must be at the far end of the ellipse when the rocket gets there, so at launch it has to be
ahead of the rocket by the angle it will travel in the meantime:

```
lead = 180 deg - omega_target * t_flight
```

| | Moon | Mars |
|---|---|---|
| Target's angular speed `omega` | 13.176 deg/day | 0.524 deg/day (Earth: 0.986 deg/day) |
| Angle the target covers in flight | 65.6 deg | 135.7 deg |
| **Where the target must be at launch** | **114.4 deg ahead of the burn point** | **Mars 44.3 deg ahead of the Earth** |
| How often the geometry repeats | every 27.3 days (a launch window each month) | every 779.9 days (about 26 months) |

So the distance and the target's motion together pick the launch date. Within a window the Earth's
rotation fixes the time of day: the launch site has to be turning under the right direction.

The same displacement also gives the separations that matter for planning:

* Mars at launch: 159.9 million km from the Earth (1.07 AU).
* Mars at arrival: 238.4 million km (1.59 AU), because the Earth has moved on 255 degrees. The
  Earth-Mars distance changes by about 78 million km during the trip.
* (Circular-orbit model. Real Earth-Mars distances range from about 55 to 400 million km.)

### Step 4: the direction sets where to point

The direction of the displacement, measured against the Earth's equator (its declination), decides
how far the launch must be steered to the north or south, which is the orbit **inclination**, and
the **azimuth** at lift-off. A site at latitude 28.5 degrees can launch directly into an orbit of
at least 28.5 degrees inclination; a target whose direction lies further north or south than that
needs a plane change or a different launch time. The mission file already carries
`target_inclination_deg` (28.5), which is this quantity for an Earth orbit.

### Step 5: accuracy, and why correction burns are needed

The transfer is very sensitive to the burn, because the displacement is large and the rocket
coasts for days or months. A velocity error `dv_err` at the burn changes the ellipse's size by
`da = 2 a^2 v dv_err / mu`, and the far end by about `2 da`:

| | Moon | Mars |
|---|---|---|
| Error from 1 m/s at the burn | about 4,190 km at arrival (the Moon's radius is 1,737 km) | about 35,000 km at arrival |
| Error from 1 s of launch timing | the Moon is about 1.0 km elsewhere on its orbit | the Earth is about 30 km elsewhere on its orbit |

A single open-loop launch cannot hit a target this precisely. In practice the launch only has to
put the rocket on a trajectory that is close; the displacement is then **re-measured during the
flight** and small **trajectory-correction burns** (a few m/s each) steer the rocket to an aim
point just outside the target's sphere of influence. Near the target the target's own gravity takes
over: the Moon's arrival speed relative to the rocket is 0.83 km/s (the Moon moves 1.018 km/s, the
rocket arrives at 0.187 km/s), and that difference is what the capture burn has to remove.

## 3. The calculation as an algorithm

```
inputs:  parking orbit radius r_park, target orbit (radius, period), departure epoch window
for each candidate departure epoch t0:
    a      = (r_park + target_distance) / 2          # step 1
    dv     = burn_from(a, r_park)                    # step 1  (Mars: via v_inf)
    t_f    = pi * sqrt(a^3 / mu)                     # step 2
    target_position = orbit_position(target, t0 + t_f)   # the displacement is taken at ARRIVAL
    lead   = angle(burn_point, target_position)      # step 3
    keep t0 if lead matches 180 deg - omega * t_f within tolerance
choose the cheapest t0 whose launch azimuth the site can fly   # step 4
fly the burn; measure the miss; apply small correction burns    # step 5
```

For the game this means three inputs it already has (target body, parking-orbit altitude from
`mission_config.json`, upper-stage thrust and Isp from `catalog.json`) and one it would need: a
model of the target's orbit over time, so the position at arrival can be evaluated.

## 4. What these numbers leave out

* Two-body motion only. A real lunar trajectory is a three-body problem (Earth, Moon, rocket), and
  Mars needs the Sun's and Earth's spheres of influence joined together (patched conics).
* Circular, coplanar orbits for Mars; its real orbit is noticeably eccentric (this changes the
  departure burn by a few tenths of a km/s from one launch window to the next).
* No gravity, drag or steering losses during the burn, and the burn is instantaneous. A real
  burn from low orbit takes minutes, and the losses add to the `dv` above.
* The parking orbit is a placeholder: the project's Moon and Mars missions currently skip the
  parking orbit and play a 6-second intermission instead.

## 5. How this relates to the transit scene

The transit scene retains its cinematic flyby for Hard and Extreme. On Easy and Normal it also
runs a relative-intercept exercise: the rocket is the origin, the web page displays the generated
destination curve, and the player's angle is used for the rocket's straight-line trajectory.
Moon and Mars use different coefficient ranges, randomized for each transit. A miss can be retried;
a hit advances to the corresponding landing scene. The values in this exercise are a game model,
not an ephemeris or a full patched-conic trajectory.

The scene is drawn from far away so that the rocket's speed reads as tiny next to the distance still
to go:

* **Distances and sizes.** The Earth is 6 million scene units away (a rocket is about 100) and
  looks 3 degrees in radius; the Moon and Mars are 1.8 million away and look 1.6 and 1.2 degrees
  in radius. The size of a far body comes from its distance, `angular_radius = asin(R / |d|)`. At real
  distances that is 0.259 degrees for the Moon and about 0.001 degrees for Mars at launch, so these
  sizes are still exaggerated, only less than before.
* **The destination moves a long way.** During the six seconds it drifts slowly, 8 degrees along its
  orbit, and a yellow arrow runs from it to the point where it will be when the rocket finally
  arrives (30 degrees from where it started). The tail of the arrow follows the destination, the tip
  stays put, so the arrow shortens as the destination moves. This is the displacement of section 1,
  made visible: it still has far more to travel than it does in the scene.
* **The rocket does not fly at it.** Its path leads to that same point, not to where the destination
  is now: its heading starts 5 degrees beyond the intercept bearing and bends back toward it by 10
  degrees over the six seconds. The arrival itself is days (Moon) or months (Mars) away.
* **Slow rocket.** It glides at 0.8 rocket lengths per second, about 80 m/s, which is nothing next
  to the distances. A slower rocket has to start closer to the camera to pass it within the first
  three seconds, so shot 1 is a closer view of the rocket than of the Earth.

The fallback flyby is set by exports in `transit.gd` (`glide_speed`, `intercept_bearing`,
`path_bend`, `destination_drift`, `earth_distance`, `destination_distance`, `show_motion_arrow`).
The challenge uses a separate relative coordinate scale in kilometres; the rendered distances and
angles remain cinematic, not to scale.
