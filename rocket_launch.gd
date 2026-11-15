extends Node3D
## Level 1 launch: OpenRocket flies the ascent, GMAT flies the orbit, Godot shows both.
##
## Ascent: the launch camera keeps a constant angle of elevation to the rocket's top.
## The sky changes as the rocket passes from the troposphere into the stratosphere.
## A few seconds after it reaches the third layer (mesosphere) the camera stops and
## the rocket flies out of frame, "Successful Launch" is shown, and the view then
## resumes with the rocket already in orbit.
## Space = launch, R = restart, Esc = quit.

enum Phase { PAD, ASCENT, CAMERA_HOLD, SUCCESS, ORBIT }

## Atmosphere layers from the ground up. Only the first two are flown through on
## camera; reaching the third ends the ascent.
const LAYERS: Array[Dictionary] = [
	{"name": "Troposphere", "top_km": 12.0, "color": Color(0.35, 0.6, 0.95),
		"sky_top": Color(0.2, 0.42, 0.78), "sky_horizon": Color(0.66, 0.78, 0.9), "stars": 0.0},
	{"name": "Stratosphere", "top_km": 50.0, "color": Color(0.1, 0.18, 0.5),
		"sky_top": Color(0.02, 0.05, 0.22), "sky_horizon": Color(0.1, 0.2, 0.5), "stars": 0.5},
	{"name": "Mesosphere", "top_km": 60.0, "color": Color(0.02, 0.02, 0.1),
		"sky_top": Color(0.0, 0.0, 0.02), "sky_horizon": Color(0.02, 0.03, 0.1), "stars": 1.0},
]

## Missions that end on another world, and the scene that lands there. transit.gd keeps the
## same pairing for the scene it opens when the intermission ends.
const LANDING_SCENES := {
	"to_the_moon": "res://moon_landing.tscn",
	"delivering_to_mars": "res://mars_landing.tscn",
}
## The intermission between the Earth ascent and the landing: six seconds of the rocket
## gliding toward the Moon or Mars, the same scene for both.
const TRANSIT_SCENE := "res://transit.tscn"

## Scene metres per real metre of the OpenRocket trajectory. Below 1 the world is
## compressed, so the rocket crosses fewer of its own lengths per second.
@export var altitude_scale: float = 0.08
@export_group("Moon and Mars missions")
## The whole Earth ascent is played back in this many seconds...
@export var landing_mission_ascent_time: float = 13.0
## ...and "Successful Launch" stays up this long before the landing scene opens,
## so the rocket is on its way 15 s after liftoff.
@export var landing_mission_success_hold: float = 2.0
@export_group("")
## Seconds between reaching the third layer and the camera stopping.
@export var camera_stop_delay: float = 3.0
## Seconds "Successful Launch" stays up before the orbit view starts.
@export var success_hold: float = 4.0
@export_group("Orbit view")
## Scene units per kilometre in the orbit view.
@export var orbit_units_per_km: float = 0.1
## Length the rocket is drawn at in orbit, in km (far larger than life so it can be seen).
@export var orbit_rocket_length_km: float = 30.0
## Orbit playback speed (GMAT seconds per real second).
@export var orbit_time_scale: float = 40.0
## Seconds in orbit before the core stage and boosters are jettisoned.
@export var jettison_delay: float = 3.0
## Mass before the jettison: liftoff mass of the vehicle in rocket_ascent_model.json (kg).
@export var liftoff_mass_kg: float = 546550.0
## Mass after the jettison: payload + empty upper stage (kg). Also sent to GMAT.
@export var orbit_mass_kg: float = 12000.0
## Ambient light in orbit; low so the night side is dark.
@export var orbit_ambient_energy: float = 0.02

@onready var _sim: OpenRocketSim = $OpenRocketSim
@onready var _orbit: GmatOrbit = $GmatOrbit
@onready var _rocket: Rocket = $Rocket
@onready var _camera: LaunchCamera = $LaunchCamera
@onready var _ground: MeshInstance3D = $Ground
@onready var _pad: MeshInstance3D = $Pad
@onready var _site: Node3D = $LaunchSite
@onready var _earth: MeshInstance3D = $Earth
@onready var _sun: DirectionalLight3D = $Sun
@onready var _sky: ShaderMaterial = $WorldEnvironment.environment.sky.sky_material
@onready var _telemetry: Label = %Telemetry
@onready var _status: Label = %Status
@onready var _banner: Label = %Banner
@onready var _altitude_bar: AltitudeBar = %AltitudeBar

var _phase: Phase = Phase.PAD
var _ready_to_launch: bool = false
var _layer: int = 0
var _phase_time: float = 0.0
var _third_layer_time: float = -1.0
var _orbit_time: float = 0.0
var _orbit_error: String = ""
var _jettisoned: bool = false
## 0 = camera frames the whole rocket, 1 = it frames the upper stage left after the jettison.
var _close_up: float = 0.0


func _enter_tree() -> void:
	# Before GmatOrbit writes its mission script in its own _ready.
	($GmatOrbit as GmatOrbit).dry_mass_kg = orbit_mass_kg
	var config: Dictionary = _read_mission_config()
	if config.has("target_altitude_km"):
		var altitude := float(config.get("target_altitude_km", 400.0))
		if altitude > 0.0 and altitude < 2000.0:
			($GmatOrbit as GmatOrbit).altitude_km = altitude
	if config.has("target_inclination_deg"):
		var inclination := float(config.get("target_inclination_deg", 28.5))
		if inclination >= 0.0 and inclination <= 180.0:
			($GmatOrbit as GmatOrbit).inclination_deg = inclination


func _read_mission_config() -> Dictionary:
	var path := ProjectSettings.globalize_path("res://mission_config.json")
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		return {}
	var data: Variant = json.data
	return data if typeof(data) == TYPE_DICTIONARY else {}


func _load_build_data() -> Dictionary:
	var config := _read_mission_config()
	var selected: Dictionary = config.get("selected_components", {})
	if typeof(selected) != TYPE_DICTIONARY or selected.is_empty():
		return {}
	var catalog_path := ProjectSettings.globalize_path("res://catalog.json")
	if not FileAccess.file_exists(catalog_path):
		return {}
	var file := FileAccess.open(catalog_path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	var catalog: Dictionary = json.data
	if typeof(catalog) != TYPE_DICTIONARY:
		return {}
	var selected_options: Dictionary = {}
	for category in catalog.get("categories", []):
		var category_id: String = String(category.get("id", ""))
		if not selected.has(category_id):
			continue
		var option_id: String = String(selected.get(category_id, ""))
		for option in category.get("options", []):
			if option.get("id") == option_id:
				selected_options[category_id] = option
				break
	var core_option: Dictionary = selected_options.get("core_structure", {})
	var nose_option: Dictionary = selected_options.get("nose_cone_tip", {})
	var booster_option: Dictionary = selected_options.get("side_boosters", {})
	var core_visuals: Dictionary = core_option.get("visuals", {})
	var nose_visuals: Dictionary = nose_option.get("visuals", {})
	var booster_visuals: Dictionary = booster_option.get("visuals", {})
	var visuals: Dictionary = {
		"core_color": core_visuals.get("core_color", "#727a83"),
		"body_radius_scale": nose_visuals.get("body_radius_scale", 1.0),
		"height_scale": nose_visuals.get("height_scale", 1.0),
		"side_booster_count": booster_visuals.get("side_booster_count", 2),
		"escape_tower_visible": nose_visuals.get("escape_tower_visible", true),
	}
	return {"visuals": visuals}


func _ready() -> void:
	var config: Dictionary = _read_mission_config()
	if LANDING_SCENES.has(config.get("mission_id", "")):
		_sim.playback_duration = landing_mission_ascent_time
		success_hold = landing_mission_success_hold
	if config.get("mission_id", "") == "delivering_to_mars":
		_status.text = "Mars mission alert: +200 kg cargo with radioactive material on board"
	_sim.ready_to_launch.connect(_on_ready_to_launch)
	_sim.failed.connect(_on_failed.bind("OpenRocket"))
	_orbit.failed.connect(_on_orbit_failed)
	_altitude_bar.layers = LAYERS
	_banner.hide()
	_earth.hide()
	_status.text = "Starting OpenRocket..."
	_update_ascent_hud({"position": Vector3.ZERO, "velocity": Vector3.ZERO, "thrust": 0.0})


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and _ready_to_launch and _phase == Phase.PAD:
		_sim.launch()
		_phase = Phase.ASCENT
		_status.text = "Liftoff - %s" % LAYERS[0].name
	elif event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		get_tree().reload_current_scene()


func _process(delta: float) -> void:
	_phase_time += delta
	match _phase:
		Phase.ASCENT, Phase.CAMERA_HOLD, Phase.SUCCESS:
			_process_ascent(delta)
		Phase.ORBIT:
			_process_orbit(delta)


func _process_ascent(delta: float) -> void:
	var state: Dictionary = _sim.get_state()
	_update_ascent_hud(state)
	_update_layer(state.position.y / 1000.0)
	# The scene shows the trajectory compressed; the HUD shows the real numbers.
	state.position *= altitude_scale
	_rocket.apply_state(state, delta)

	match _phase:
		Phase.ASCENT:
			# The camera follows the rocket for the whole ascent.
			if _sim.finished:
				_banner.text = "Vehicle Failure" if _sim.vehicle_failed else "Successful Launch"
				_banner.show()
				_status.text = _sim.vehicle_failure_reason if _sim.vehicle_failed else ""
				_set_phase(Phase.SUCCESS)
		Phase.SUCCESS:
			if _phase_time >= success_hold:
				if _sim.vehicle_failed:
					_status.text = _sim.vehicle_failure_reason
				elif LANDING_SCENES.has(_read_mission_config().get("mission_id", "")):
					# The coast to the Moon or Mars is a six-second intermission; the
					# transit scene then opens the landing scene for the mission.
					get_tree().change_scene_to_file(TRANSIT_SCENE)
				elif _orbit.is_ready:
					_enter_orbit()
				elif not _orbit_error.is_empty():
					_status.text = "GMAT error: %s" % _orbit_error


func _set_phase(phase: Phase) -> void:
	_phase = phase
	_phase_time = 0.0


func _update_layer(altitude_km: float) -> void:
	if _sim.vehicle_failed or _phase == Phase.SUCCESS:
		return
	var layer: int = 0
	while layer < LAYERS.size() - 1 and altitude_km >= LAYERS[layer].top_km:
		layer += 1
	if layer == _layer:
		return
	_layer = layer
	_status.text = "Entering the %s - %d km" % [LAYERS[layer].name, LAYERS[layer - 1].top_km]
	_fade_sky(LAYERS[layer].sky_top, LAYERS[layer].sky_horizon, LAYERS[layer].stars)
	if layer == 2:
		_third_layer_time = _sim.sim_time


func _fade_sky(top: Color, horizon: Color, stars: float) -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(_sky, "shader_parameter/top_color", top, 1.5)
	tween.tween_property(_sky, "shader_parameter/horizon_color", horizon, 1.5)
	tween.tween_property(_sky, "shader_parameter/star_amount", stars, 1.5)


func _update_ascent_hud(state: Dictionary) -> void:
	var altitude_km: float = state.position.y / 1000.0
	_altitude_bar.altitude_km = altitude_km
	_telemetry.text = "T+ %5.1f s\nAltitude %6.2f km\nSpeed %7.0f m/s\nLayer: %s" % [
		_sim.sim_time, altitude_km, state.velocity.length(), LAYERS[_layer].name,
	]


func _enter_orbit() -> void:
	_set_phase(Phase.ORBIT)
	_banner.hide()
	_altitude_bar.hide()
	_ground.hide()
	_pad.hide()
	_site.hide()
	_earth.show()
	_earth.scale = Vector3.ONE * GmatOrbit.EARTH_RADIUS_KM * orbit_units_per_km
	_sky.set_shader_parameter("star_amount", 1.0)
	_rocket.engines_enabled = false
	_rocket.clear_exhaust()
	_rocket.scale = Vector3.ONE * orbit_rocket_length_km * orbit_units_per_km / _rocket.length
	# One sun for the Earth and the rocket; the rocket leaves its layer in the Earth's shadow.
	_sun.light_cull_mask = 1
	_sun.shadow_enabled = false
	var env: Environment = $WorldEnvironment.environment
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = orbit_ambient_energy
	_camera.frozen = true # the orbit view places the camera itself
	_camera.fov = 60.0
	_status.text = "In orbit"
	_process_orbit(0.0)


func _process_orbit(delta: float) -> void:
	_orbit_time += delta * orbit_time_scale
	var state: Dictionary = _orbit.get_state(_orbit_time)
	var at: Vector3 = state.position * orbit_units_per_km
	var up: Vector3 = at.normalized()
	var prograde: Vector3 = state.velocity.normalized()
	_rocket.set_pose(at, prograde, up)

	if not _jettisoned and _phase_time >= jettison_delay:
		_jettisoned = true
		_rocket.jettison()
		_status.text = "Core stage and boosters jettisoned"
		create_tween().tween_property(self, "_close_up", 1.0, 4.0).set_delay(3.0)

	# In the Earth's shadow when behind it (seen from the sun) and inside its cylinder.
	var to_sun: Vector3 = _sun.global_basis.z
	var along: float = state.position.dot(to_sun)
	var sunlit: bool = along > 0.0 or (state.position - to_sun * along).length() > GmatOrbit.EARTH_RADIUS_KM
	_rocket.set_sunlit(sunlit)

	# Camera resumes: behind and above the rocket, looking along its path.
	var rocket_length: float = orbit_rocket_length_km * orbit_units_per_km
	var view: float = rocket_length * lerpf(1.0, 0.4, _close_up)
	var anchor: Vector3 = at + prograde * rocket_length * 0.75 * _close_up
	_camera.global_position = anchor - prograde * view * 2.5 + up * view * 1.2
	_camera.look_at(anchor + prograde * view * lerpf(1.0, 0.3, _close_up), up)

	_telemetry.text = "Orbit (GMAT)\nAltitude %6.1f km\nSpeed %7.2f km/s\nMass %d kg\n%s\nTime x%d" % [
		state.position.length() - GmatOrbit.EARTH_RADIUS_KM, state.velocity.length(),
		orbit_mass_kg if _jettisoned else liftoff_mass_kg, "Sunlight" if sunlit else "Earth's shadow", orbit_time_scale,
	]


func _on_ready_to_launch(rocket_name: String, length: float, _radius: float) -> void:
	_rocket.build(length, _load_build_data())
	_camera.frame_target(_rocket.length)
	_ready_to_launch = true
	var config: Dictionary = _read_mission_config()
	if config.get("mission_id", "") == "delivering_to_mars":
		_status.text = "Mars cargo: 200 kg radioactive material aboard. Press SPACE to launch"
	else:
		_status.text = "Press SPACE to launch"
	print("OpenRocket design: %s. Camera elevation angle: %.1f deg" % [rocket_name, _camera.get_elevation_angle()])


func _on_failed(message: String, source: String) -> void:
	_status.text = "%s error: %s" % [source, message]
	push_error("%s: %s" % [source, message])


func _on_orbit_failed(message: String) -> void:
	_orbit_error = message
	push_error("GMAT: %s" % message)
