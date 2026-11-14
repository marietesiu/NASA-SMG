class_name GmatOrbit
extends Node
## Orbital phase, computed by NASA's GMAT.
##
## Writes a GMAT mission script for a circular Earth orbit, runs it headlessly with
## GmatConsole on a worker thread, and reads the ReportFile it produces. Godot only
## plays the result back.

signal failed(message: String)

const EARTH_RADIUS_KM := 6378.14
const EARTH_MU := 398600.4415 # km^3/s^2

## GMAT install folder (contains bin/GmatConsole). Empty = $GMAT_HOME or ~/GMAT.
@export_global_dir var gmat_home: String = ""
@export var altitude_km: float = 400.0
@export var inclination_deg: float = 28.5
## How many orbits to propagate; playback loops after that.
@export var orbits: float = 6.0
@export var step_seconds: float = 30.0
## Spacecraft mass given to GMAT (kg).
@export var dry_mass_kg: float = 12000.0

## True once the GMAT run finished and its report was read.
var is_ready: bool = false

var _thread: Thread
var _times: PackedFloat64Array = []
var _positions: PackedVector3Array = [] # km, Godot axes
var _velocities: PackedVector3Array = [] # km/s, Godot axes


func _ready() -> void:
	var home: String = gmat_home
	if home.is_empty():
		home = OS.get_environment("GMAT_HOME")
	if home.is_empty():
		home = OS.get_environment("HOME").path_join("GMAT")
	var bin_dir: String = home.path_join("bin")
	# GmatConsole needs its own libraries on the loader path.
	OS.set_environment("LD_LIBRARY_PATH", bin_dir)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://gmat"))
	var script_path: String = ProjectSettings.globalize_path("user://gmat/orbit.script")
	var report_path: String = ProjectSettings.globalize_path("user://gmat/orbit_report.txt")
	DirAccess.remove_absolute(report_path)
	var file := FileAccess.open(script_path, FileAccess.WRITE)
	file.store_string(_mission_script(report_path))
	file.close()

	_thread = Thread.new()
	_thread.start(_run_gmat.bind(bin_dir.path_join("GmatConsole"), script_path, report_path))


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


## Spacecraft state `seconds` after the start of the orbit (loops).
## Keys: position (km), velocity (km/s), both in Godot axes with Earth at the origin.
func get_state(seconds: float) -> Dictionary:
	var t: float = fposmod(seconds, _times[_times.size() - 1])
	var b: int = clampi(_times.bsearch(t), 1, _times.size() - 1)
	var a: int = b - 1
	var w: float = clampf((t - _times[a]) / (_times[b] - _times[a]), 0.0, 1.0)
	return {
		"position": _positions[a].lerp(_positions[b], w),
		"velocity": _velocities[a].lerp(_velocities[b], w),
	}


# One statement per line: GMAT rejects several on one line.
func _mission_script(report_path: String) -> String:
	var sma: float = EARTH_RADIUS_KM + altitude_km
	var period: float = TAU * sqrt(pow(sma, 3.0) / EARTH_MU)
	return "\n".join([
		"Create Spacecraft Sat;",
		"Sat.DryMass = %.1f;" % dry_mass_kg,
		"Sat.DateFormat = UTCGregorian;",
		"Sat.Epoch = '01 Jan 2026 12:00:00.000';",
		"Sat.CoordinateSystem = EarthMJ2000Eq;",
		"Sat.DisplayStateType = Keplerian;",
		"Sat.SMA = %.4f;" % sma,
		"Sat.ECC = 0.0001;",
		"Sat.INC = %.4f;" % inclination_deg,
		"Sat.RAAN = 0;",
		"Sat.AOP = 0;",
		"Sat.TA = 0;",
		"Create ForceModel FM;",
		"FM.CentralBody = Earth;",
		"FM.PrimaryBodies = {Earth};",
		"FM.GravityField.Earth.Degree = 4;",
		"FM.GravityField.Earth.Order = 4;",
		"Create Propagator Prop;",
		"Prop.FM = FM;",
		"Prop.Type = RungeKutta89;",
		"Prop.InitialStepSize = %.3f;" % step_seconds,
		"Prop.MaxStep = %.3f;" % step_seconds,
		"Create ReportFile RF;",
		"RF.Filename = '%s';" % report_path,
		"RF.WriteHeaders = false;",
		"RF.Add = {Sat.ElapsedSecs, Sat.EarthMJ2000Eq.X, Sat.EarthMJ2000Eq.Y, Sat.EarthMJ2000Eq.Z, "
				+ "Sat.EarthMJ2000Eq.VX, Sat.EarthMJ2000Eq.VY, Sat.EarthMJ2000Eq.VZ};",
		"BeginMissionSequence;",
		"Propagate Prop(Sat) {Sat.ElapsedSecs = %.1f};" % (period * orbits),
		"",
	])


# Worker thread.
func _run_gmat(console: String, script_path: String, report_path: String) -> void:
	var output: Array = []
	var exit_code: int = OS.execute(console, ["--run", script_path], output, true)
	var times: PackedFloat64Array = []
	var positions: PackedVector3Array = []
	var velocities: PackedVector3Array = []
	var report := FileAccess.open(report_path, FileAccess.READ)
	if report != null:
		while not report.eof_reached():
			var f: PackedFloat64Array = report.get_line().split_floats(" ", false)
			if f.size() < 7:
				continue
			times.append(f[0])
			positions.append(_to_godot(f[1], f[2], f[3]))
			velocities.append(_to_godot(f[4], f[5], f[6]))
	_finish.call_deferred(exit_code, times, positions, velocities)


func _finish(exit_code: int, times: PackedFloat64Array, positions: PackedVector3Array,
		velocities: PackedVector3Array) -> void:
	# GMAT's exit code is not trusted on its own; the report is what counts.
	if times.size() < 2:
		failed.emit("GMAT produced no orbit report (exit code %d)" % exit_code)
		return
	_times = times
	_positions = positions
	_velocities = velocities
	is_ready = true


## GMAT EarthMJ2000Eq (+Z north pole, +X vernal equinox) -> Godot (+Y up).
func _to_godot(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)
