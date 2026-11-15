class_name OpenRocketSim
extends Node
## Runs a real OpenRocket simulation from inside Godot.
##
## Spawns the headless Java bridge (openrocket_bridge/OpenRocketBridge) with
## OpenRocket's own jar on the classpath, tells it when to launch, and collects
## the flight states the OpenRocket engine streams back. Godot never integrates
## any physics itself; it only plays back what OpenRocket computed.

## Bridge finished loading the rocket and is waiting for launch().
signal ready_to_launch(rocket_name: String, length: float, radius: float)
## OpenRocket flight event (LIFTOFF, BURNOUT, APOGEE, ...), reported during
## playback when sim_time passes the event's time.
signal flight_event(type: String, time: float)
signal failed(message: String)

## OpenRocket install folder (contains jar/ and jre/). Empty = $OPENROCKET_HOME or ~/OpenRocket.
@export_global_dir var openrocket_home: String = ""
## Rocket design to fly.
@export_file("*.ork") var rocket_file: String = "res://rockets/simple_model_rocket.ork"
## Which simulation inside the .ork file to run.
@export var simulation_index: int = 0

## The motor never burns out (thrust is held at the motor's average once past mid-burn).
@export var infinite_fuel: bool = true
## With infinite fuel: the held thrust is this many times the motor's average thrust.
@export var thrust_scale: float = 40.0
## With infinite fuel: thrust is throttled back near this speed (m/s). OpenRocket's model
## rocket tumbles if pushed far past Mach 4. 0 = no limit.
@export var max_speed: float = 1200.0
## End the simulation after this many seconds of flight. 0 = fly until OpenRocket ends it.
@export var max_flight_time: float = 0.0
## End the simulation once the rocket is this high (m). 0 = no limit.
@export var max_altitude: float = 80000.0
## No wind and a vertical launch rod, so the rocket flies straight.
@export var calm_air: bool = true

## Play the whole recorded flight back in this many real seconds (0 = real time). Only the
## playback is compressed: the flight itself, and the frame rate, stay as OpenRocket computed them.
@export var playback_duration: float = 0.0
## Playback speed used until OpenRocket has finished and the flight's length is known.
@export var provisional_playback_speed: float = 8.0
const EARTH_LAUNCH_INITIAL_VELOCITY_BOOST_MPS: float = 8.0
const EARTH_LAUNCH_ACCELERATION_BOOST_MPS2: float = 1.5
const EARTH_LAUNCH_ACCELERATION_DECAY_SECONDS: float = 3.0

## Seconds of flight played back so far.
var sim_time: float = 0.0
var _playback_elapsed: float = 0.0
var launched: bool = false
## True once playback reached the end of the simulated flight.
var finished: bool = false
var vehicle_failed: bool = false
var vehicle_failure_reason: String = ""
var motion_scale: float = 1.0

var _pid: int = -1
var _stdio: FileAccess
var _thread: Thread
var _mutex := Mutex.new()
var _incoming: PackedStringArray = []

# Flight samples, in Godot coordinates (Y up).
var _times: PackedFloat64Array = []
var _positions: PackedVector3Array = []
var _velocities: PackedVector3Array = []
var _axes: PackedVector3Array = []
var _thrusts: PackedFloat32Array = []
var _events: Array[Dictionary] = []
var _next_event: int = 0
var _cursor: int = 0
var _sim_done: bool = false


func _ready() -> void:
	var config: Dictionary = _read_json_file(ProjectSettings.globalize_path("res://mission_config.json"))
	if str(config.get("mission_id", "")) == "around_earth":
		motion_scale = 0.5
	_start_bridge()


func _exit_tree() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


## Tell OpenRocket to run the simulation and start playing it back.
func launch() -> void:
	if launched or _stdio == null:
		return
	launched = true
	_stdio.store_line("LAUNCH")
	_stdio.flush()


func _process(delta: float) -> void:
	_drain_incoming()
	if not launched or finished or _times.is_empty():
		return
	var last_time: float = _times[_times.size() - 1]
	var step: float = delta
	if playback_duration > 0.0:
		_playback_elapsed += delta
		if _sim_done:
			# Spread what is left of the flight over what is left of the playback time.
			var real_left: float = maxf(playback_duration - _playback_elapsed, 0.0) + delta
			step = (last_time - sim_time) * delta / real_left
		else:
			step = delta * provisional_playback_speed
	sim_time = minf(sim_time + step, last_time)
	while _next_event < _events.size() and _events[_next_event].time <= sim_time:
		flight_event.emit(_events[_next_event].type, _events[_next_event].time)
		_next_event += 1
	if _sim_done and sim_time >= last_time:
		finished = true
## Interpolated flight state at the current sim_time.
## Keys: position, velocity, axis (unit nose direction), thrust (N).
func get_state() -> Dictionary:
	if _times.is_empty():
		return {"position": Vector3.ZERO, "velocity": Vector3.ZERO, "axis": Vector3.UP, "thrust": 0.0}
	while _cursor < _times.size() - 2 and _times[_cursor + 1] < sim_time:
		_cursor += 1
	var a: int = _cursor
	var b: int = mini(a + 1, _times.size() - 1)
	var span: float = _times[b] - _times[a]
	var w: float = clampf((sim_time - _times[a]) / span, 0.0, 1.0) if span > 0.0 else 0.0
	var position: Vector3 = _positions[a].lerp(_positions[b], w)
	position = _positions[0] + (position - _positions[0]) * motion_scale
	var velocity: Vector3 = _velocities[a].lerp(_velocities[b], w) * motion_scale
	if motion_scale < 1.0:
		var elapsed: float = maxf(sim_time, 0.0)
		var decay: float = EARTH_LAUNCH_ACCELERATION_DECAY_SECONDS
		var acceleration_ramp: float = decay * (elapsed - decay * (1.0 - exp(-elapsed / decay)))
		var velocity_ramp: float = decay * (1.0 - exp(-elapsed / decay))
		var launch_axis: Vector3 = _axes[0].normalized()
		position += launch_axis * (
			EARTH_LAUNCH_INITIAL_VELOCITY_BOOST_MPS * elapsed
			+ EARTH_LAUNCH_ACCELERATION_BOOST_MPS2 * acceleration_ramp
		)
		velocity += launch_axis * (
			EARTH_LAUNCH_INITIAL_VELOCITY_BOOST_MPS
			+ EARTH_LAUNCH_ACCELERATION_BOOST_MPS2 * velocity_ramp
		)
	return {
		"position": position,
		"velocity": velocity,
		"axis": _axes[a].lerp(_axes[b], w).normalized(),
		"thrust": lerpf(_thrusts[a], _thrusts[b], w),
	}


func _start_bridge() -> void:
	var home: String = openrocket_home
	if home.is_empty():
		home = OS.get_environment("OPENROCKET_HOME")
	if home.is_empty():
		home = OS.get_environment("HOME").path_join("OpenRocket")

	var jar: String = _find_jar(home.path_join("jar"))
	if jar.is_empty():
		failed.emit("OpenRocket jar not found in %s" % home.path_join("jar"))
		return
	var java: String = home.path_join("jre/bin/java")
	if not FileAccess.file_exists(java):
		java = "java"
	var bridge_dir: String = ProjectSettings.globalize_path("res://openrocket_bridge")
	var separator: String = ";" if OS.get_name() == "Windows" else ":"

	var args: PackedStringArray = [
		"-cp", jar + separator + bridge_dir,
		"OpenRocketBridge",
		ProjectSettings.globalize_path(rocket_file),
		str(simulation_index),
	]
	var vehicle_spec := _vehicle_from_config()
	if vehicle_spec.is_empty() and infinite_fuel:
		args.append_array(["--infinite-fuel", "--thrust-scale", str(thrust_scale)])
		if max_speed > 0.0:
			args.append_array(["--max-speed", str(max_speed)])
	if vehicle_spec.is_empty() and max_altitude > 0.0:
		args.append_array(["--max-altitude", str(max_altitude)])
	if vehicle_spec.is_empty() and max_flight_time > 0.0:
		args.append_array(["--max-time", str(max_flight_time)])
	if not vehicle_spec.is_empty():
		args.append_array(["--vehicle", vehicle_spec])
	if calm_air:
		args.append("--calm")
	var info: Dictionary = OS.execute_with_pipe(java, args) # blocking pipes: the reader thread sleeps until OpenRocket writes a line
	if info.is_empty():
		failed.emit("Could not start Java (%s)" % java)
		return
	_pid = info["pid"]
	_stdio = info["stdio"]
	_thread = Thread.new()
	_thread.start(_read_bridge_output)


func _find_jar(dir_path: String) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
	for file in dir.get_files():
		if file.begins_with("OpenRocket") and file.ends_with(".jar"):
			return dir_path.path_join(file)
	return ""


# Runs on a worker thread: blocking reads from the bridge's stdout.
func _read_bridge_output() -> void:
	while _stdio.is_open() and _stdio.get_error() == OK:
		var line: String = _stdio.get_line()
		if line.is_empty():
			continue
		if line.begins_with("ERROR"):
			continue
		_mutex.lock()
		_incoming.append(line)
		_mutex.unlock()
		if line == "DONE":
			break


func _drain_incoming() -> void:
	_mutex.lock()
	var lines: PackedStringArray = _incoming
	_incoming = PackedStringArray()
	_mutex.unlock()
	for line in lines:
		_handle_line(line)


func _format_vehicle_failure(code: String, value: float, limit: float, difficulty: String) -> String:
	var human: String = "Vehicle failure"
	var detail: String = "The rocket exceeded a structural or flight limit."
	var metric_name: String = "measured value"
	var unit: String = ""
	var explanation: String = ""
	match code:
		"NO_LIFTOFF":
			human = "No liftoff"
			metric_name = "thrust-to-weight ratio"
			unit = "g"
			detail = "The engine produced only %.2f g of thrust while the rocket needed %.2f g to leave the pad. This means the launch vehicle was underpowered for the selected loadout and difficulty." % [value, limit]
		"TANK_RUPTURE":
			human = "Tank rupture"
			metric_name = "tank pressure"
			unit = "Pa"
			detail = "The propellant tank reached %.3f Pa, while the safe operating limit was %.3f Pa. That is about %.2f times the tank's safe pressure limit, so the tank failed before the burn could finish." % [value, limit, value / maxf(limit, 1.0)]
		"STRUCTURAL_BREAKUP":
			human = "Structural breakup"
			metric_name = "aerodynamic load"
			unit = "Pa·rad"
			detail = "The airframe saw %.3f Pa·rad of bending load, while the safe design limit was %.3f Pa·rad. This was about %.2f times the structural limit, so the rocket broke up in flight." % [value, limit, value / maxf(limit, 1.0)]
		"NOSE_BURNTHROUGH":
			human = "Nose burn-through"
			metric_name = "nose heating"
			unit = "W/m²"
			detail = "The nose reached %.3f W/m² of thermal loading, while the heat shield limit was %.3f W/m². The thermal protection could not absorb the heat load at this speed and angle of attack." % [value, limit]
		"LOST_CONTROL":
			human = "Loss of control"
			metric_name = "rocket tilt"
			unit = "deg"
			detail = "The vehicle tilted to %.2f degrees, while the control system was only safe up to %.2f degrees. The rocket drifted out of its stable flight path and lost attitude control." % [value, limit]
		_:
			human = code.replace("_", " ").to_lower().capitalize()
			metric_name = "measured limit"
			unit = ""
			detail = "The rocket crossed a measured value of %.3f against a safe limit of %.3f. This means the current design or difficulty setting was outside the safe operating envelope." % [value, limit]
	if code == "NO_LIFTOFF":
		explanation = "Difficulty: %s. The engine output was %.3f g, compared with the %.3f g required to leave the pad." % [difficulty, value, limit]
	elif not unit.is_empty():
		explanation = "Difficulty: %s. Measured %s = %s %s, safe limit = %s %s." % [difficulty, metric_name, String.num(value, 3), unit, String.num(limit, 3), unit]
	else:
		explanation = "Difficulty: %s. Measured value = %s, safe limit = %s." % [difficulty, String.num(value, 3), String.num(limit, 3)]
	return "%s: %s %s" % [human, detail, explanation]

func _handle_line(line: String) -> void:
	var f: PackedStringArray = line.split(",")
	match f[0]:
		"STEP":
			if f.size() < 12:
				return
			_times.append(f[1].to_float())
			_positions.append(_to_godot(f[2], f[3], f[4]))
			_velocities.append(_to_godot(f[5], f[6], f[7]))
			_axes.append(_to_godot(f[8], f[9], f[10]))
			_thrusts.append(f[11].to_float())
		"EVENT":
			_events.append({"time": f[1].to_float(), "type": f[2]})
		"INFO":
			ready_to_launch.emit(f[3], f[1].to_float(), f[2].to_float())
		"DONE":
			_sim_done = true
		"ERROR":
			return
		"FAIL":
			vehicle_failed = true
			if f.size() >= 5:
				var code: String = f[2]
				var value: float = f[3].to_float()
				var limit: float = f[4].to_float()
				var config: Dictionary = _read_json_file(ProjectSettings.globalize_path("res://mission_config.json"))
				var difficulty_name = String(config.get("difficulty", "normal")).capitalize()
				vehicle_failure_reason = _format_vehicle_failure(code, value, limit, difficulty_name)
			else:
				vehicle_failure_reason = "Vehicle failure: the rocket exceeded a flight limit. Review the payload, propulsion choice, and difficulty profile."
			failed.emit("Vehicle failure - " + vehicle_failure_reason)


func _read_json_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		return {}
	var data: Variant = json.data
	return data if typeof(data) == TYPE_DICTIONARY else {}


func _vehicle_from_config() -> String:
	var config := _read_json_file(ProjectSettings.globalize_path("res://mission_config.json"))
	if config.is_empty():
		return ""
	var selected: Dictionary = config.get("selected_components", {})
	if typeof(selected) != TYPE_DICTIONARY or selected.is_empty():
		return ""
	var catalog := _read_json_file(ProjectSettings.globalize_path("res://catalog.json"))
	if catalog.is_empty():
		return ""
	var difficulty_settings: Dictionary = catalog.get("difficulties", {}).get(config.get("difficulty", "normal"), {})
	var fuel_multiplier: float = float(difficulty_settings.get("fuel", 1.0))
	var hazard_multiplier: float = maxf(float(difficulty_settings.get("hazard", 1.0)), 0.01)

	var dry_mass: float = 0.0
	var propellant: float = 0.0
	var thrust_sl: float = 0.0
	var thrust_vac: float = 0.0
	var ref_area: float = 0.0
	var length: float = 0.0
	var static_margin_total: float = 0.0
	var cg_dry_weight: float = 0.0
	var cg_prop_weight: float = 0.0
	var gimbal_max: float = 0.0
	var q_alpha_min: float = INF
	var tank_limit: float = INF
	var heat_limit: float = INF
	var prop_density: float = 1000.0
	var column: float = 3.0
	var ullage: float = 2000.0
	var count: int = 0
	var nose_radius: float = 0.8
	var wind_ground: float = 5.0
	var wind_jet: float = 25.0
	var engine_isp: float = 330.0

	for category in catalog.get("categories", []):
		var option_id: String = selected.get(category.get("id", ""), "")
		if option_id.is_empty():
			continue
		var option: Dictionary = {}
		for candidate in category.get("options", []):
			if candidate.get("id") == option_id:
				option = candidate
				break
		if option.is_empty():
			continue
		var physics: Dictionary = option.get("physics", {})
		if physics.is_empty():
			continue
		var category_id: String = String(category.get("id", ""))
		count += 1
		dry_mass += float(physics.get("dry_mass", 0.0))
		if category_id in ["propellant_tanks", "side_boosters"]:
			propellant += float(physics.get("propellant", 0.0))
			cg_prop_weight += float(physics.get("propellant", 0.0)) * float(physics.get("cg_prop", 0.5))
		if category_id in ["main_engines", "side_boosters"]:
			thrust_sl += float(physics.get("thrust_sl", 0.0))
			thrust_vac += float(physics.get("thrust_vac", 0.0))
			engine_isp = maxf(engine_isp, float(physics.get("isp_vac", 0.0)))
		ref_area = maxf(ref_area, float(physics.get("ref_area", 0.0)))
		length = maxf(length, float(physics.get("length", 0.0)))
		static_margin_total += float(physics.get("static_margin", 0.08))
		cg_dry_weight += float(physics.get("dry_mass", 0.0)) * float(physics.get("cg_dry", 0.5))
		gimbal_max = maxf(gimbal_max, float(physics.get("gimbal_max", 0.0)))
		if physics.has("q_alpha_limit"):
			q_alpha_min = minf(q_alpha_min, float(physics.get("q_alpha_limit", 0.0)))
		if category_id in ["bulk_plates", "core_structure", "propellant_tanks"] \
				and float(physics.get("tank_limit", 0.0)) > 0.0:
			tank_limit = minf(tank_limit, float(physics.get("tank_limit", INF)))
		if category_id == "thermal_protection" and float(physics.get("heat_limit", 0.0)) > 0.0:
			heat_limit = minf(heat_limit, float(physics.get("heat_limit", INF)))
		if physics.has("nose_radius"):
			nose_radius = maxf(nose_radius, float(physics.get("nose_radius", 0.0)))
		if physics.has("prop_density"):
			prop_density = maxf(prop_density, float(physics.get("prop_density", 0.0)))
		if physics.has("column"):
			column = maxf(column, float(physics.get("column", 0.0)))
		if physics.has("ullage"):
			ullage = maxf(ullage, float(physics.get("ullage", 0.0)))

	if config.get("mission_id") == "delivering_to_mars":
		dry_mass += float(config.get("cargo_mass_kg", 200.0))
	if dry_mass <= 0.0 or count == 0:
		return ""
	if q_alpha_min == INF:
		q_alpha_min = 3000.0
	if tank_limit == INF:
		tank_limit = 500000.0
	if heat_limit == INF:
		heat_limit = 100000.0
	q_alpha_min /= hazard_multiplier
	tank_limit /= hazard_multiplier
	heat_limit /= hazard_multiplier
	if ref_area <= 0.0:
		ref_area = 1.0
	if length <= 0.0:
		length = 18.0
	if propellant <= 0.0:
		propellant = maxf(dry_mass * 0.15, 30000.0)
	propellant *= maxf(fuel_multiplier, 0.01)
	if thrust_vac <= 0.0:
		thrust_vac = 4200000.0
	if thrust_sl <= 0.0:
		thrust_sl = thrust_vac * 0.8
	if gimbal_max <= 0.0:
		gimbal_max = 1.3
	var cg_dry: float = cg_dry_weight / maxf(dry_mass, 1.0)
	var cg_prop: float = cg_prop_weight / maxf(propellant, 1.0)
	var static_margin: float = static_margin_total / maxf(count, 1.0)
	return (
		"dry_mass=%.1f,propellant=%.1f,thrust_sl=%.1f,thrust_vac=%.1f,isp_vac=%.1f,ref_area=%.4f,length=%.4f,"
		+ "cg_dry=%.4f,cg_prop=%.4f,static_margin=%.4f,gimbal_max=%.4f,q_alpha_limit=%.1f,tank_limit=%.1f,"
		+ "ullage=%.1f,prop_density=%.1f,column=%.1f,heat_limit=%.1f,nose_radius=%.4f,wind_ground=%.1f,wind_jet=%.1f"
	) % [
		dry_mass, propellant, thrust_sl, thrust_vac, engine_isp, ref_area, length,
		cg_dry, cg_prop, static_margin, gimbal_max, q_alpha_min, tank_limit,
		ullage, prop_density, column, heat_limit, nose_radius, wind_ground, wind_jet
	]


## OpenRocket world (x east, y north, z up) -> Godot (x east, y up, -z north).
func _to_godot(x: String, y: String, z: String) -> Vector3:
	return Vector3(x.to_float(), z.to_float(), -y.to_float())
