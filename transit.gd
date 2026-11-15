extends Node3D
## Transit: a six-second intermission between leaving Earth and arriving at the Moon or Mars.
## One scene serves both missions; mission_config.json says which one.
##
## The rocket lies horizontal, nose toward the destination, and glides at a steady speed.
## The camera never moves within a shot, and there are two shots:
##   0-3 s   The camera looks back at the rocket with the Earth behind it. The rocket glides
##           toward the camera, passes just beside it and goes out of view behind it.
##   3-6 s   The camera cuts to (x of the fins, y of the fins + 100, z of the fins), taken
##           the moment of the cut, and looks toward the Moon or Mars far ahead. The rocket
##           keeps gliding away beneath it, toward the destination.
## Then the landing scene for the mission opens.
## R = restart, Esc = quit.
##
## World axes: +X is the direction of travel (toward the destination), Y is up.

## Per mission: the destination body, the landing scene that follows, and how big the
## destination looks (its apparent radius from the camera).
const DESTINATIONS := {
	"to_the_moon": {
		"name": "Moon",
		"kind": CelestialBody.Kind.MOON,
		"next_scene": "res://moon_landing.tscn",
		"angular_radius_deg": 8.0,
	},
	"delivering_to_mars": {
		"name": "Mars",
		"kind": CelestialBody.Kind.MARS,
		"next_scene": "res://mars_landing.tscn",
		"angular_radius_deg": 6.0,
	},
}
## Used when mission_config.json has no Moon or Mars mission (for example when this scene is
## run on its own from the editor).
const DEFAULT_MISSION := "to_the_moon"

## Leave empty to use mission_config.json. Set it to "to_the_moon" or "delivering_to_mars" to
## preview that destination, e.g. when running this scene on its own from the editor.
@export var mission_override: String = ""

@export_group("Timing")
@export var first_shot_seconds: float = 3.0
@export var second_shot_seconds: float = 3.0

@export_group("Rocket")
## Glide speed, in rocket lengths per second.
@export var glide_speed: float = 1.2
## Show only the upper stage and capsule (what flies on to land) instead of the whole vehicle.
@export var lander_only: bool = false
## Where "the fins" are, measured up the rocket from its tail in rocket lengths. The model
## has no fins, so the default is the tail, where they would be.
@export var fins_height: float = 0.0

@export_group("Shot 1 - camera looks back at the rocket, Earth behind it")
@export var first_camera_fov: float = 70.0
## How far the rocket passes from the camera, in rocket lengths: sideways (z) and below (y).
@export var pass_offset: Vector2 = Vector2(0.22, -0.1)
## Rocket length behind the camera when shot 1 ends: the tail is this far past it.
@export var clear_of_camera: float = 0.15

@export_group("Shot 2 - camera above the fins, destination ahead")
@export var camera_height_above_fins: float = 100.0
## Downward tilt of the camera (degrees) so the rocket stays in frame under it.
@export var second_camera_pitch: float = -30.0
@export var second_camera_fov: float = 90.0

@export_group("Backdrop")
## Distances in scene units from the camera. The sizes follow from how large each body looks.
@export var earth_distance: float = 40000.0
@export var earth_angular_radius: float = 22.0
@export var destination_distance: float = 60000.0
## How far above the horizon the destination sits, in degrees.
@export var destination_elevation: float = 4.0
## Direction toward the sun. From the side, so the Earth and the destination both show a
## day side and a night side.
@export var sun_from: Vector3 = Vector3(0.0, 0.25, 1.0)

@onready var _rocket: Rocket = $Rocket
@onready var _camera: Camera3D = $Camera3D
@onready var _earth: CelestialBody = $Earth
@onready var _destination_body: CelestialBody = $Destination
@onready var _sun: DirectionalLight3D = $Sun

var _destination: Dictionary
var _fins: Marker3D
var _rocket_length: float = 98.0
var _speed: float = 0.0
## Position of the rocket's axis (y, z) while it glides along X.
var _axis_y: float = 0.0
var _axis_z: float = 0.0
## X of the tail at the end of shot 1.
var _tail_x_at_cut: float = 0.0
var _time: float = 0.0
var _shot: int = 1
var _finished: bool = false


func _ready() -> void:
	var config: Dictionary = _read_json("res://mission_config.json")
	var mission_id: String = mission_override if not mission_override.is_empty() else str(config.get("mission_id", ""))
	if not DESTINATIONS.has(mission_id):
		push_warning("Transit: '%s' is not a Moon or Mars mission; showing %s." % [mission_id, DEFAULT_MISSION])
		mission_id = DEFAULT_MISSION
	_destination = DESTINATIONS[mission_id]

	_setup_light()
	_setup_bodies()
	_setup_rocket(config)
	_place_rocket(0.0)
	_begin_shot(1)


func _process(delta: float) -> void:
	if _finished:
		return
	_time += delta
	# The tail's X: it is at `_tail_x_at_cut` at the moment of the cut and the rocket moves
	# at a constant speed, before and after.
	_place_rocket(_tail_x_at_cut + _speed * (_time - first_shot_seconds))
	if _shot == 1 and _time >= first_shot_seconds:
		_begin_shot(2)
	if _time >= first_shot_seconds + second_shot_seconds:
		_finished = true
		get_tree().change_scene_to_file(_destination.next_scene)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		get_tree().reload_current_scene()


func _setup_light() -> void:
	_sun.look_at_from_position(sun_from.normalized() * 100.0, Vector3.ZERO)


func _setup_bodies() -> void:
	# The Earth is behind the rocket (it came from there), the destination is ahead of it.
	_earth.kind = CelestialBody.Kind.EARTH
	_earth.radius = earth_distance * sin(deg_to_rad(earth_angular_radius))
	_earth.position = Vector3(-earth_distance, 0.0, 0.0)
	_earth.build()
	_earth.set_sun_direction(sun_from)

	_destination_body.kind = _destination.kind
	_destination_body.radius = destination_distance * sin(deg_to_rad(_destination.angular_radius_deg))
	_destination_body.position = Vector3(destination_distance, destination_distance * tan(deg_to_rad(destination_elevation)), 0.0)
	_destination_body.build()
	_destination_body.set_sun_direction(sun_from)


func _setup_rocket(config: Dictionary) -> void:
	_rocket.build(_rocket.length / _rocket.visual_scale, _rocket_visuals(config))
	_rocket_length = _rocket.length
	if lander_only:
		_rocket.make_lander()
		_rocket_length = _rocket.length * 0.27 # what is left above the upper stage's base
	_rocket.engines_enabled = false
	_fins = Marker3D.new()
	_fins.name = "Fins"
	_fins.position = Vector3(0.0, fins_height * _rocket_length, 0.0)
	_rocket.add_child(_fins)

	_speed = glide_speed * _rocket_length
	_axis_z = pass_offset.x * _rocket_length
	_axis_y = pass_offset.y * _rocket_length
	# By the cut the whole rocket has passed the camera (which sits at X = 0).
	_tail_x_at_cut = clear_of_camera * _rocket_length


## Rocket horizontal, nose along +X, boosters on either side (along Z), tail at x.
func _place_rocket(tail_x: float) -> void:
	_rocket.set_pose(Vector3(tail_x, _axis_y, _axis_z), Vector3.RIGHT, Vector3.UP)


func _begin_shot(shot: int) -> void:
	_shot = shot
	if shot == 1:
		# At the origin, looking back along -X: the rocket glides toward it, the Earth is behind.
		_camera.fov = first_camera_fov
		_camera.look_at_from_position(Vector3.ZERO, Vector3.LEFT, Vector3.UP)
	else:
		# (x of the fins, y of the fins + 100, z of the fins), looking toward the destination.
		var fins: Vector3 = _fins.global_position
		var at := Vector3(fins.x, fins.y + camera_height_above_fins, fins.z)
		var pitch: float = deg_to_rad(second_camera_pitch)
		_camera.fov = second_camera_fov
		_camera.look_at_from_position(at, at + Vector3(cos(pitch), sin(pitch), 0.0), Vector3.UP)


## The rocket's look, from the components chosen in the builder: the same fields the launch
## scene reads (see rocket_launch.gd, _load_build_data).
func _rocket_visuals(config: Dictionary) -> Dictionary:
	var selected: Dictionary = config.get("selected_components", {})
	var catalog: Dictionary = _read_json("res://catalog.json")
	if selected.is_empty() or catalog.is_empty():
		return {}
	var core: Dictionary = _option(catalog, selected, "core_structure").get("visuals", {})
	var nose: Dictionary = _option(catalog, selected, "nose_cone_tip").get("visuals", {})
	var boosters: Dictionary = _option(catalog, selected, "side_boosters").get("visuals", {})
	return {"visuals": {
		"core_color": core.get("core_color", "#727a83"),
		"body_radius_scale": nose.get("body_radius_scale", 1.0),
		"height_scale": nose.get("height_scale", 1.0),
		"side_booster_count": boosters.get("side_booster_count", 2),
		"escape_tower_visible": nose.get("escape_tower_visible", true),
	}}


func _option(catalog: Dictionary, selected: Dictionary, category_id: String) -> Dictionary:
	for category in catalog.get("categories", []):
		if category.get("id", "") != category_id:
			continue
		for option in category.get("options", []):
			if option.get("id", "") == selected.get(category_id, ""):
				return option
	return {}


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
