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

## Seconds of flight played back so far.
var sim_time: float = 0.0
var launched: bool = false
## True once playback reached the end of the simulated flight.
var finished: bool = false

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
	sim_time = minf(sim_time + delta, last_time)
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
	return {
		"position": _positions[a].lerp(_positions[b], w),
		"velocity": _velocities[a].lerp(_velocities[b], w),
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
	if infinite_fuel:
		args.append_array(["--infinite-fuel", "--thrust-scale", str(thrust_scale)])
		if max_speed > 0.0:
			args.append_array(["--max-speed", str(max_speed)])
	if max_altitude > 0.0:
		args.append_array(["--max-altitude", str(max_altitude)])
	if max_flight_time > 0.0:
		args.append_array(["--max-time", str(max_flight_time)])
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
		_mutex.lock()
		_incoming.append(line)
		_mutex.unlock()
		if line == "DONE" or line.begins_with("ERROR"):
			break


func _drain_incoming() -> void:
	_mutex.lock()
	var lines: PackedStringArray = _incoming
	_incoming = PackedStringArray()
	_mutex.unlock()
	for line in lines:
		_handle_line(line)


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
			failed.emit(line.trim_prefix("ERROR,"))


## OpenRocket world (x east, y north, z up) -> Godot (x east, y up, -z north).
func _to_godot(x: String, y: String, z: String) -> Vector3:
	return Vector3(x.to_float(), z.to_float(), -y.to_float())
