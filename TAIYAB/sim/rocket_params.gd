class_name RocketParams
extends RefCounted
## All user-adjustable rocket variables, their realistic limits, presets and cross-constraints.

## Structural-mass floor: at most 95 % of the launch mass may be propellant (dry mass >= 5 %).
const MAX_FUEL_FRACTION: float = 0.95

const KEYS: Array[String] = ["thrust", "initial_mass", "fuel_mass", "isp", "diameter", "cd"]
const OPTION_KEYS: Array[String] = [
	"gravity_enabled", "variable_gravity", "drag_enabled", "dt_burn", "dt_coast", "t_max", "stop_at_apogee"
]

const LIMITS: Dictionary = {
	"thrust": {
		"label": "Engine thrust", "unit": "N", "min": 100000.0, "max": 10000000.0, "step": 10000.0, "exp": true,
		"desc": "F — total engine thrust, held constant while propellant lasts. 100 kN is a small sounding rocket, 7.6 MN a Falcon 9 first stage, 35 MN a Saturn V."
	},
	"initial_mass": {
		"label": "Initial mass", "unit": "kg", "min": 5000.0, "max": 600000.0, "step": 500.0, "exp": true,
		"desc": "m0 — total mass on the pad: structure + payload + propellant."
	},
	"fuel_mass": {
		"label": "Fuel mass", "unit": "kg", "min": 500.0, "max": 570000.0, "step": 500.0, "exp": true,
		"desc": "Propellant mass. Limited to 95 % of the initial mass (the remaining 5 % is the minimum dry mass of tanks and engine)."
	},
	"isp": {
		"label": "Specific impulse", "unit": "s", "min": 150.0, "max": 460.0, "step": 1.0, "exp": false,
		"desc": "Isp — engine efficiency: thrust per unit weight-flow of propellant. Solid ≈ 250 s, kerolox ≈ 300–340 s, hydrolox ≈ 450 s."
	},
	"diameter": {
		"label": "Rocket diameter", "unit": "m", "min": 0.5, "max": 12.0, "step": 0.1, "exp": false,
		"desc": "d — body diameter. Sets the reference cross-section A = π(d/2)² used by the drag equation."
	},
	"cd": {
		"label": "Drag coefficient", "unit": "", "min": 0.1, "max": 1.2, "step": 0.01, "exp": false,
		"desc": "Cd — dimensionless aerodynamic resistance. Slender, streamlined rockets ≈ 0.2–0.4; blunt bodies approach 1."
	},
}

# --- user variables -------------------------------------------------------
var thrust: float = 1500000.0
var initial_mass: float = 100000.0
var fuel_mass: float = 60000.0
var isp: float = 300.0
var diameter: float = 5.0
var cd: float = 0.4

# --- model / solver options (not exposed as sliders; used by tests & challenges) -----
var gravity_enabled: bool = true
var variable_gravity: bool = true
var drag_enabled: bool = true
var dt_burn: float = 0.2       ## RK4 step while the engine fires [s]
var dt_coast: float = 1.0      ## RK4 step during the ballistic phase [s]
var t_max: float = 3600.0
var stop_at_apogee: bool = false


func clone() -> RocketParams:
	var c: RocketParams = RocketParams.new()
	for k in KEYS:
		c.set(k, get(k))
	for k in OPTION_KEYS:
		c.set(k, get(k))
	return c


func dry_mass() -> float:
	return initial_mass - fuel_mass


func area() -> float:
	return RocketPhysics.area(diameter)


func twr0() -> float:
	return RocketPhysics.twr(thrust, initial_mass, Const.G0)


func clamp_to_limits() -> void:
	for k in KEYS:
		var lim: Dictionary = LIMITS[k]
		set(k, clampf(float(get(k)), float(lim["min"]), float(lim["max"])))
	fuel_mass = minf(fuel_mass, initial_mass * MAX_FUEL_FRACTION)


func warnings() -> Array[String]:
	var w: Array[String] = []
	var twr: float = twr0()
	if twr < 1.0:
		w.append("TWR at liftoff is %.2f (< 1): the rocket stays on the pad until burning propellant lowers its mass." % twr)
	elif twr > 6.0:
		w.append("TWR at liftoff is %.1f: extreme acceleration (> 5 g sustained is beyond crewed limits)." % twr)
	if dry_mass() / initial_mass < 0.1:
		w.append("Dry-mass fraction %.0f %% is below 10 %%: very optimistic structure." % (100.0 * dry_mass() / initial_mass))
	return w


static func presets() -> Dictionary:
	return {
		"Reference (defaults)": {},
		"High-thrust booster": {"thrust": 3000000.0},
		"High-Isp upper stage": {"thrust": 1200000.0, "isp": 420.0},
		"Heavy, low TWR": {"thrust": 1100000.0},
		"Blunt, draggy body": {"diameter": 9.0, "cd": 0.9},
		"Small sounding rocket": {"thrust": 150000.0, "initial_mass": 10000.0, "fuel_mass": 6000.0, "isp": 250.0, "diameter": 0.8, "cd": 0.35},
	}


static func from_preset(preset_name: String) -> RocketParams:
	var p: RocketParams = RocketParams.new()
	var all: Dictionary = presets()
	if all.has(preset_name):
		var d: Dictionary = all[preset_name]
		for k in d.keys():
			p.set(k, d[k])
	p.clamp_to_limits()
	return p
