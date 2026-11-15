extends Node3D
## Transit: a six-second intermission between leaving Earth and arriving at the Moon or Mars.
## One scene serves both missions; mission_config.json says which one.
##
## Everything is seen from far away: the Earth and the destination are hundreds of thousands
## of rocket lengths off, so the rocket's speed reads as tiny next to the distance still to go.
##
## The destination does not stand still. Moons and planets keep moving along their orbits, so
## it drifts a long way across the sky during the six seconds, and an arrow runs from it to the
## point where it will be when the rocket finally arrives. The rocket does not fly at the
## destination: its path leads to that point, bending gradually toward it. There is no
## calculation here, only the picture; the numbers are explained elsewhere
## (docs/transfer_to_moon_and_mars.md).
##
## The rocket lies horizontal, nose along its path, and glides at a steady speed. The camera
## never moves within a shot, and there are two shots:
##   0-3 s   The camera looks at the rocket from the side, with the Earth behind it. The rocket
##           glides toward the camera, passes it and goes out of view behind it.
##   3-6 s   The camera cuts to (x of the fins, y of the fins + 100, z of the fins), taken the
##           moment of the cut, and looks toward the Moon or Mars far ahead. The rocket keeps
##           gliding away beneath it while the destination drifts toward its path.
## Then the landing scene for the mission opens.
## R = restart, Esc = quit.
##
## World axes: +X points from the Earth toward the destination, Y is up, and the destination
## drifts toward +Z. Angles are measured from +X toward +Z.

## Per mission: the destination body, the landing scene that follows, and how big the
## destination looks from the camera (its apparent radius). Both are small: they are far away.
const DESTINATIONS := {
	"to_the_moon": {
		"name": "Moon",
		"kind": CelestialBody.Kind.MOON,
		"next_scene": "res://moon_landing.tscn",
		"angular_radius_deg": 1.6,
	},
	"delivering_to_mars": {
		"name": "Mars",
		"kind": CelestialBody.Kind.MARS,
		"next_scene": "res://mars_landing.tscn",
		"angular_radius_deg": 1.2,
	},
}
## Used when mission_config.json has no Moon or Mars mission (for example when this scene is
## run on its own from the editor).
const DEFAULT_MISSION := "to_the_moon"
const CHALLENGE_DIFFICULTIES := ["easy", "normal"]
const MOON_TARGET_X_KM := 384400.0
const MARS_TARGET_X_KM := 225000000.0

## Leave empty to use mission_config.json. Set it to "to_the_moon" or "delivering_to_mars" to
## preview that destination, e.g. when running this scene on its own from the editor.
@export var mission_override: String = ""

@export_group("Timing")
@export var first_shot_seconds: float = 3.0
@export var second_shot_seconds: float = 3.0

@export_group("Rocket")
## Show only the upper stage and capsule (what flies on to land) instead of the whole vehicle.
@export var lander_only: bool = false
## Where "the fins" are, measured up the rocket from its tail in rocket lengths. The model
## has no fins, so the default is the tail, where they would be.
@export var fins_height: float = 0.0
## Glide speed in rocket lengths per second. Slow: next to the distance still to go it barely
## moves. The first shot's start distance follows from it (a slower rocket starts closer, so
## that it still passes the camera within the first shot).
@export var glide_speed: float = 0.8

@export_group("Path")
## Where the destination will be when the rocket finally arrives, as a bearing in degrees from
## the Earth-destination line toward the side it is moving to. Far larger than the few degrees
## it moves during the six seconds: it has a long way to go. The arrow points there and the
## rocket's path leads there.
@export var intercept_bearing: float = 30.0
## How much the rocket's heading turns during the six seconds (degrees), steadily, centred on
## the intercept bearing: it starts a little beyond it and bends back toward it.
@export var path_bend: float = 10.0
## How far the destination moves along its orbit during the six seconds, as seen from the
## camera, in degrees: its speed across the sky is this over the six seconds. Slow, and well
## short of the intercept bearing, which is where the arrow points.
@export var destination_drift: float = 8.0
## The arrow from the destination to where it will be when the rocket arrives.
@export var show_motion_arrow: bool = true
@export var arrow_color: Color = Color(1.0, 0.82, 0.2)

@export_group("Shot 1 - camera looks at the rocket, Earth behind it")
@export var first_camera_fov: float = 70.0
## Where the camera stands relative to the rocket's path, in rocket lengths: to the side (z)
## and above it (y). The side the sun is on, so the rocket is seen lit.
@export var first_camera_offset: Vector2 = Vector2(1.0, 0.25)
## When shot 1 ends the tail is this far (rocket lengths) past the camera, so the whole
## rocket is behind it.
@export var clear_of_camera: float = 0.15

@export_group("Shot 2 - camera above the fins, destination ahead")
@export var camera_height_above_fins: float = 100.0
## Downward tilt of the camera (degrees) so the rocket stays in frame under it.
@export var second_camera_pitch: float = -20.0
@export var second_camera_fov: float = 85.0

@export_group("Backdrop")
## Distances in scene units from the camera (a rocket is about 100 units long). The sizes
## follow from how large each body looks.
@export var earth_distance: float = 6000000.0
@export var earth_angular_radius: float = 3.0
@export var destination_distance: float = 1800000.0
## Direction toward the sun. From the side, so the Earth and the destination both show a
## day side and a night side.
@export var sun_from: Vector3 = Vector3(0.0, 0.25, 1.0)

@onready var _rocket: Rocket = $Rocket
@onready var _camera: Camera3D = $Camera3D
@onready var _earth: CelestialBody = $Earth
@onready var _destination_body: CelestialBody = $Destination
@onready var _sun: DirectionalLight3D = $Sun

var _destination: Dictionary
var _mission_id: String = ""
var _difficulty: String = "normal"
var _fins: Marker3D
var _arrow: Node3D
var _arrow_shaft: MeshInstance3D
var _arrow_head: MeshInstance3D
var _rocket_length: float = 98.0
var _speed: float = 0.0
## Rocket lengths between the camera and the rocket's nose when shot 1 starts.
var _start_distance: float = 0.0
var _time: float = 0.0
var _shot: int = 1
var _finished: bool = false
var _challenge_active: bool = false
var _challenge_waiting_for_answer: bool = false
var _challenge_hit: bool = false
var _challenge_angle_rad: float = 0.0
var _challenge_a: float = 0.0
var _challenge_b: float = 0.0
var _challenge_c: float = 0.0
var _challenge_target_x_km: float = 0.0
var _challenge_target_y_km: float = 0.0
var _challenge_tolerance_km: float = 0.0
var _challenge_session_id: String = ""
var _api_base_url: String = "http://127.0.0.1:8080/api"
var _http: HTTPRequest
var _http_poll_timer: Timer
var _http_action: String = ""
var _http_busy: bool = false
var _queued_http_action: String = ""
var _queued_http_payload: Dictionary = {}
var _success_elapsed: float = 0.0
var _success_hold_seconds: float = 4.0
var _js_callback: JavaScriptObject


func _ready() -> void:
	var config: Dictionary = _read_json("res://mission_config.json")
	var mission_id: String = mission_override if not mission_override.is_empty() else str(config.get("mission_id", ""))
	if not DESTINATIONS.has(mission_id):
		push_warning("Transit: '%s' is not a Moon or Mars mission; showing %s." % [mission_id, DEFAULT_MISSION])
		mission_id = DEFAULT_MISSION
	_mission_id = mission_id
	_difficulty = str(config.get("difficulty", "normal")).to_lower()
	_destination = DESTINATIONS[mission_id]
	_api_base_url = str(config.get("transit_api_url", _api_base_url))
	_setup_challenge(config, mission_id)

	_setup_light()
	_setup_bodies()
	_setup_rocket(config)
	if show_motion_arrow:
		_build_arrow()
	_update_scene(0.0)
	_begin_shot(1)
	if _challenge_active:
		_start_challenge_session()


func _process(delta: float) -> void:
	if _finished:
		return
	if _challenge_active:
		_process_challenge(delta)
		return
	_time += delta
	_update_scene(_time)
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
	# The camera of shot 1 sits just behind the tail at the moment of the cut. Up to then the
	# rocket covers its start distance, its own length and that clearance at a steady speed,
	# so the start distance is what is left over.
	_start_distance = maxf(_speed * first_shot_seconds / _rocket_length - 1.0 - clear_of_camera, 0.0)


## Easy and Normal get the same equation exercise; harder profiles keep the original transit.
func _setup_challenge(config: Dictionary, mission_id: String) -> void:
	var difficulty := str(config.get("difficulty", "normal")).to_lower()
	if difficulty not in CHALLENGE_DIFFICULTIES:
		return
	_challenge_active = true
	_challenge_waiting_for_answer = true
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if mission_id == "to_the_moon":
		_challenge_target_x_km = MOON_TARGET_X_KM
		_challenge_a = rng.randf_range(0.7e-8, 2.4e-8)
		_challenge_b = rng.randf_range(0.025, 0.065)
		_challenge_c = rng.randf_range(-600.0, 1200.0)
		_challenge_tolerance_km = 1737.4
	else:
		_challenge_target_x_km = MARS_TARGET_X_KM
		_challenge_a = rng.randf_range(1.0e-11, 3.0e-11)
		_challenge_b = rng.randf_range(0.004, 0.012)
		_challenge_c = rng.randf_range(-50000.0, 100000.0)
		_challenge_tolerance_km = 3389.5
	_challenge_target_y_km = _destination_curve_y(_challenge_target_x_km)
	_challenge_session_id = "%s-%s" % [str(Time.get_ticks_usec()), str(rng.randi())]


func _destination_curve_y(x_km: float) -> float:
	return _challenge_a * x_km * x_km + _challenge_b * x_km + _challenge_c


func _challenge_destination_position() -> Vector3:
	var visual_scale: float = destination_distance / _challenge_target_x_km
	return Vector3(destination_distance, 0.0, _challenge_target_y_km * visual_scale)


func _start_challenge_session() -> void:
	var session_data := {
		"session_id": _challenge_session_id,
		"mission_id": _mission_id,
		"difficulty": _difficulty,
		"a": _challenge_a,
		"b": _challenge_b,
		"c": _challenge_c,
		"target_x_km": _challenge_target_x_km,
		"tolerance_km": _challenge_tolerance_km,
	}
	if OS.has_feature("web"):
		_register_web_bridge()
		_post_to_web({"type": "transit-start", "payload": session_data})
		return
	_http = HTTPRequest.new()
	_http.name = "TransitHttp"
	add_child(_http)
	_http.request_completed.connect(_on_http_request_completed)
	_http_poll_timer = Timer.new()
	_http_poll_timer.name = "TransitAnswerPoll"
	_http_poll_timer.wait_time = 0.35
	_http_poll_timer.timeout.connect(_poll_transit_answer)
	add_child(_http_poll_timer)
	_send_http("start", session_data)


func _register_web_bridge() -> void:
	var window: JavaScriptObject = JavaScriptBridge.get_interface("window")
	_js_callback = JavaScriptBridge.create_callback(_on_web_message)
	window.set("godotTransitReceive", _js_callback)
	JavaScriptBridge.eval(
		"window.addEventListener('message', function(event) { "
		+ "if (event.data && event.data.type === 'transit-answer') "
		+ "window.godotTransitReceive(JSON.stringify(event.data)); });"
	)


func _post_to_web(message: Dictionary) -> void:
	var json_literal: String = JSON.stringify(JSON.stringify(message))
	JavaScriptBridge.eval("window.parent.postMessage(JSON.parse(%s), '*');" % json_literal)


func _on_web_message(args: Array) -> void:
	if args.is_empty():
		return
	var message: Variant = JSON.parse_string(str(args[0]))
	if typeof(message) != TYPE_DICTIONARY or message.get("type", "") != "transit-answer":
		return
	if message.get("session_id", "") == _challenge_session_id:
		_receive_challenge_angle(float(message.get("angle_deg", 0.0)))


func _send_http(action: String, payload: Dictionary) -> void:
	if _http == null:
		return
	if _http_busy:
		_queued_http_action = action
		_queued_http_payload = payload
		return
	_http_busy = true
	_http_action = action
	var url: String = _api_base_url + "/transit/" + action
	var err := _http.request(url, PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		_http_busy = false
		push_warning("Transit API request could not start: %s" % error_string(err))


func _poll_transit_answer() -> void:
	if _http_busy or _http == null:
		return
	_http_busy = true
	_http_action = "poll"
	var url := "%s/transit/answer?session_id=%s" % [_api_base_url, _challenge_session_id.uri_encode()]
	var err := _http.request(url)
	if err != OK:
		_http_busy = false


func _on_http_request_completed(result: int, response_code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	var action := _http_action
	_http_busy = false
	var response: Variant = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		push_warning("Transit API %s failed (HTTP %d)." % [action, response_code])
		return
	if typeof(response) != TYPE_DICTIONARY:
		return
	if action == "start":
		_http_poll_timer.start()
	elif action == "poll" and response.get("answer") != null:
		_receive_challenge_angle(float(response.answer))
	if not _queued_http_action.is_empty():
		var next_action := _queued_http_action
		var next_payload := _queued_http_payload
		_queued_http_action = ""
		_queued_http_payload = {}
		_send_http(next_action, next_payload)


## Checks the submitted angle against the destination curve. Nothing is flown: a miss is
## reported (the scene stays paused and the player may try again), a hit ends the transit.
func _receive_challenge_angle(angle_deg: float) -> void:
	if not _challenge_active or not _challenge_waiting_for_answer or not is_finite(angle_deg):
		return
	_challenge_waiting_for_answer = false
	var feedback: String
	if angle_deg <= -89.0 or angle_deg >= 89.0:
		feedback = "Angle must be between -89 and 89 degrees. Try again."
		_challenge_hit = false
	else:
		_challenge_angle_rad = deg_to_rad(angle_deg)
		var miss_km: float = absf(tan(_challenge_angle_rad) * _challenge_target_x_km - _challenge_target_y_km)
		_challenge_hit = miss_km <= _challenge_tolerance_km
		if _challenge_hit:
			feedback = "Correct angle. The trajectory reaches %s within %.1f km." % [_destination.name, miss_km]
		else:
			feedback = "Wrong angle: it misses by %.1f km. Try again." % miss_km
	_report_challenge_result(_challenge_hit, feedback)
	if _challenge_hit:
		_success_elapsed = 0.0
		_update_scene(first_shot_seconds)
		_begin_shot(2) # the second part of the scene, shown for the 4 s before the change
	else:
		_challenge_waiting_for_answer = true
		if _http_poll_timer != null:
			_http_poll_timer.start()


## The scene stays paused on its first frame. Only a correct angle moves on.
func _process_challenge(delta: float) -> void:
	if not _challenge_hit:
		return
	_success_elapsed += delta
	if _success_elapsed >= _success_hold_seconds:
		_finished = true
		get_tree().change_scene_to_file(_destination.next_scene)


func _report_challenge_result(hit: bool, feedback: String) -> void:
	var result_data := {
		"session_id": _challenge_session_id,
		"hit": hit,
		"feedback": feedback,
	}
	if OS.has_feature("web"):
		_post_to_web({"type": "transit-result", "payload": result_data})
	else:
		_send_http("result", result_data)


## The arrow: a shaft and a head, both unit-sized cylinders that _update_scene stretches to fit.
func _build_arrow() -> void:
	_arrow = Node3D.new()
	_arrow.name = "MotionArrow"
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = arrow_color

	var shaft := CylinderMesh.new()
	shaft.top_radius = 1.0
	shaft.bottom_radius = 1.0
	shaft.height = 1.0
	shaft.material = material
	_arrow_shaft = MeshInstance3D.new()
	_arrow_shaft.mesh = shaft
	_arrow_shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arrow.add_child(_arrow_shaft)

	var head := CylinderMesh.new()
	head.top_radius = 0.0
	head.bottom_radius = 1.0
	head.height = 1.0
	head.material = material
	_arrow_head = MeshInstance3D.new()
	_arrow_head.mesh = head
	_arrow_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arrow.add_child(_arrow_head)
	add_child(_arrow)


## Everything that moves, at time `t`: the rocket along its path and the destination (with its
## arrow) along its orbit.
func _update_scene(t: float) -> void:
	_rocket.set_pose(_path_position(t), _path_direction(t), Vector3.UP)
	var total: float = first_shot_seconds + second_shot_seconds
	var bearing: float = deg_to_rad(destination_drift) * clampf(t / total, 0.0, 1.0)
	var at := Vector3(cos(bearing), 0.0, sin(bearing)) * destination_distance
	_destination_body.position = at
	if _arrow != null:
		_update_arrow(at)


## From just beside the destination to the point where it will be when the rocket arrives. The
## tail follows the destination as it drifts, the tip stays put, so the arrow shortens as the
## destination gets closer to it.
func _update_arrow(destination_at: Vector3) -> void:
	var intercept: Vector3 = _intercept_point()
	var body_radius: float = _destination_body.radius
	var to_intercept: Vector3 = intercept - destination_at
	var direction: Vector3 = to_intercept.normalized()
	var head_length: float = 1.2 * body_radius
	var shaft_length: float = maxf(to_intercept.length() - 1.4 * body_radius - head_length, 0.001)
	var side: Vector3 = Vector3.UP.cross(direction).normalized()
	_arrow.global_transform = Transform3D(
			Basis(side, direction, side.cross(direction)),
			destination_at + direction * 1.4 * body_radius)
	_arrow_shaft.scale = Vector3(0.2 * body_radius, shaft_length, 0.2 * body_radius)
	_arrow_shaft.position = Vector3(0.0, shaft_length * 0.5, 0.0)
	_arrow_head.scale = Vector3(0.6 * body_radius, head_length, 0.6 * body_radius)
	_arrow_head.position = Vector3(0.0, shaft_length + head_length * 0.5, 0.0)


## Where the destination will be when the rocket arrives, far along its orbit.
func _intercept_point() -> Vector3:
	var bearing: float = deg_to_rad(intercept_bearing)
	return Vector3(cos(bearing), 0.0, sin(bearing)) * destination_distance


## The rocket's heading at time `t`, in radians: it turns steadily over the six seconds by
## `path_bend`, centred on the intercept bearing (starting beyond it, bending back toward it).
func _heading(t: float) -> float:
	var total: float = first_shot_seconds + second_shot_seconds
	var start: float = intercept_bearing + path_bend * 0.5
	var end: float = intercept_bearing - path_bend * 0.5
	return deg_to_rad(lerpf(start, end, clampf(t / total, 0.0, 1.0)))


func _path_direction(t: float) -> Vector3:
	var heading: float = _heading(t)
	return Vector3(cos(heading), 0.0, sin(heading))


## Where the rocket's tail is at time `t`, measured from where it is at the moment of the cut
## (so the cut is at the origin). The rocket moves at a constant speed while its heading
## turns at a constant rate, which is a circular arc; this is that arc in closed form.
func _path_position(t: float) -> Vector3:
	var total: float = first_shot_seconds + second_shot_seconds
	var turn_rate: float = deg_to_rad(-path_bend) / total
	var heading_cut: float = _heading(first_shot_seconds)
	var heading: float = _heading(t)
	if absf(turn_rate) < 0.000001:
		return _speed * (t - first_shot_seconds) * Vector3(cos(heading), 0.0, sin(heading))
	return Vector3(
			_speed / turn_rate * (sin(heading) - sin(heading_cut)),
			0.0,
			-_speed / turn_rate * (cos(heading) - cos(heading_cut)))


func _begin_shot(shot: int) -> void:
	_shot = shot
	if shot == 1:
		# To one side of the rocket's path and just behind where its tail is at the cut,
		# looking at the rocket where it starts: it glides toward the camera, the Earth is
		# behind it.
		var along: Vector3 = _path_direction(first_shot_seconds)
		var side := Vector3(-along.z, 0.0, along.x) # to the +Z side, where the sun is
		var at: Vector3 = -along * clear_of_camera * _rocket_length \
				+ side * first_camera_offset.x * _rocket_length \
				+ Vector3.UP * first_camera_offset.y * _rocket_length
		var rocket_at: Vector3 = _path_position(0.0) + _path_direction(0.0) * 0.5 * _rocket_length
		# Aim between the rocket and the Earth so both are in the picture: the rocket flies at
		# an angle to the Earth-destination line, so the Earth is well off the rocket's line.
		var toward_rocket: Vector3 = (rocket_at - at).normalized()
		var toward_earth: Vector3 = (_earth.position - at).normalized()
		_camera.fov = first_camera_fov
		_camera.look_at_from_position(at, at + (toward_rocket + toward_earth).normalized() * 1000.0, Vector3.UP)
	else:
		# (x of the fins, y of the fins + 100, z of the fins), turned toward the destination
		# and tilted down so the rocket stays in frame beneath it.
		var fins: Vector3 = _fins.global_position
		var at := Vector3(fins.x, fins.y + camera_height_above_fins, fins.z)
		var to_destination: Vector3 = (_destination_body.position - at).normalized()
		var yaw: float = atan2(to_destination.z, to_destination.x)
		var pitch: float = deg_to_rad(second_camera_pitch)
		var forward := Vector3(cos(pitch) * cos(yaw), sin(pitch), cos(pitch) * sin(yaw))
		_camera.fov = second_camera_fov
		_camera.look_at_from_position(at, at + forward, Vector3.UP)


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
