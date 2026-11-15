extends Node3D
## Landing on the Moon or on Mars. The coast from the edge of Earth's atmosphere is skipped:
## the scene opens with the lander already falling toward the surface.
##
## The camera stands on the surface and never moves: it watches the lander come down.
## Sequence: the lander arrives nose first, swings upright over the pad in one continuous
## manoeuvre (frozen on two key frames with an explanation), then lowers its legs and brakes
## to a touchdown.
## R = restart, Esc = quit.

enum Phase { MANOEUVRE, DESCENT, LANDED }

## What changes between the two worlds: gravity, which component turns the lander, and the
## explanations shown on the two key frames.
const BODIES := {
	PlanetSurface.Body.MOON: {
		"name": "Luna",
		"gravity": 1.62, # m/s^2
		"turn_category": "gimbal_system",
		"turn_label": "Cardán",
		"arrival": "Trayecto Tierra - Luna omitido. Llegando a la superficie lunar.",
		"how_it_turns": "CÓMO GIRA: sin aire las aletas no sirven. El motor se inclina en su cardán "
				+ "y el empuje, ya descentrado, hace rotar el cohete.",
		"how_it_lands": "CÓMO ATERRIZA: cola abajo, patas fuera, y el motor frena la caída hasta posarse.",
		"success": "Alunizaje completado",
		"failure": "Alunizaje fallido",
	},
	PlanetSurface.Body.MARS: {
		"name": "Marte",
		"gravity": 3.71,
		"turn_category": "control_fins",
		"turn_label": "Aletas de control",
		"arrival": "Trayecto Tierra - Marte omitido. Entrada atmosférica superada, llegando a la superficie.",
		"how_it_turns": "CÓMO GIRA: el aire de Marte es cien veces más fino que el de la Tierra. "
				+ "Las aletas muerden ese aire para levantar la punta y el motor inclinado termina el giro.",
		"how_it_lands": "CÓMO ATERRIZA: el aire ya no frena lo bastante. Cola abajo, patas fuera, "
				+ "y el motor hace todo el frenado final.",
		"success": "Aterrizaje en Marte completado",
		"failure": "Aterrizaje en Marte fallido",
	},
}
## Fastest touchdown the legs absorb (m/s).
const LEG_LIMIT := 4.0
## Fraction of the upper stage's propellant still on board for the landing.
const LANDING_PROPELLANT_FRACTION := 0.2
## Damping of the turn: below 1 the nose swings a little past upright and settles back.
const TURN_DAMPING := 0.7
## Largest swing of the exhaust plume drawn while the engine steers (rad).
const GIMBAL_SHOWN := deg_to_rad(14.0)

@export var body: PlanetSurface.Body = PlanetSurface.Body.MOON
## Direction the sunlight comes from.
@export var sun_from := Vector3(-0.62, 0.42, 0.66)
@export_group("Trajectory")
## Where the lander appears, relative to the landing spot (m).
@export var approach_start := Vector3(-95.0, 112.0, 0.0)
## Height at which it is upright and starts the braking burn (m).
@export var burn_altitude: float = 62.0
## Descent speed at the start of the braking burn (m/s).
@export var burn_speed: float = 14.0
@export_group("Explained turn")
## Seconds flown nose first before the turn starts.
@export var lead_in_time: float = 1.0
## Seconds the turn takes with 1.5 deg of control authority; more authority turns faster.
@export var turn_time: float = 3.4
## Seconds each of the two key frames is held.
@export var key_frame_hold: float = 1.7
## Seconds the motion takes to ease to a stop, and to pick up again, around a key frame.
@export var key_frame_ease: float = 0.3
## Tilt (deg from upright) of the first key frame; the second is the lander upright.
@export var first_key_frame_tilt: float = 45.0
@export_group("Camera on the surface")
@export var camera_position := Vector3(-15.0, 1.7, 150.0)
@export var camera_target := Vector3(-25.0, 52.0, 0.0)

@onready var _surface: PlanetSurface = $Surface
@onready var _rocket: Rocket = $Rocket
@onready var _camera: Camera3D = $SurfaceCamera
@onready var _telemetry: Label = %Telemetry
@onready var _caption: Label = %Caption
@onready var _banner: Label = %Banner

var _phase: Phase = Phase.MANOEUVRE
var _phase_time: float = 0.0
## Lander tilt from upright (rad): 90 deg = nose first along its path, 0 = tail down.
var _tilt: float = PI / 2.0
var _speed: float = 0.0

# From the chosen components (mission_config.json + catalog.json), or defaults.
var _gimbal_deg: float = 1.5
var _gimbal_name: String = ""
var _thrust_n: float = 460000.0
var _engine_name: String = "Motor de etapa superior"
var _mass_kg: float = 27400.0

var _turn_time: float = 3.4
var _decel: float = 0.0 # braking deceleration actually flown (m/s^2)
var _touchdown_speed: float = 0.0
var _throttle: float = 0.0
var _descent_time: float = 0.0
var _needed_decel: float = 0.0
var _world: Dictionary
var _gravity: float = 1.62

# The manoeuvre runs on its own clock, which eases to a stop on the key frames.
var _clock: float = 0.0
var _manoeuvre_time: float = 0.0
var _start_velocity := Vector3.ZERO
var _acceleration := Vector3.ZERO
var _turn_rate: float = 0.0 # natural frequency of the turn (rad/s)
var _peak_turn_accel: float = 1.0
## Clock times of the key frames and the text shown on each.
var _key_times: Array[float] = []
var _key_texts: Array[String] = []
var _key_index: int = 0
var _key_timer: float = -1.0 # real seconds into the current key frame, -1 = not in one


func _ready() -> void:
	_world = BODIES[body]
	_gravity = _world.gravity
	_gimbal_name = _world.turn_label
	_load_components()
	_plan_landing()
	_plan_manoeuvre()
	_rocket.make_lander()
	($Sun as DirectionalLight3D).look_at_from_position(sun_from.normalized() * 100.0, Vector3.ZERO)
	# The camera stands on the ground and stays there for the whole landing.
	_camera.global_position = camera_position \
			+ Vector3.UP * _surface.height_at(camera_position.x, camera_position.z)
	_camera.look_at(camera_target, Vector3.UP)
	_caption.text = _world.arrival
	_fly_manoeuvre()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		get_tree().reload_current_scene()


func _process(delta: float) -> void:
	_phase_time += delta
	match _phase:
		Phase.MANOEUVRE:
			_advance_clock(delta)
			_fly_manoeuvre()
			if _clock >= _manoeuvre_time:
				_caption.text = ""
				_rocket.set_gimbal(0.0)
				_rocket.deploy_legs(1.5)
				_set_phase(Phase.DESCENT)
		Phase.DESCENT:
			_process_descent()
	_update_telemetry()


func _set_phase(phase: Phase) -> void:
	_phase = phase
	_phase_time = 0.0


## Height of the lander's origin when it stands on the pad.
func _stand_height() -> float:
	return _rocket.lander_ground_offset + PlanetSurface.PAD_HEIGHT


# ---------------------------------------------------------------- the manoeuvre

## The path and the turn, and where on them the two key frames fall.
func _plan_manoeuvre() -> void:
	_manoeuvre_time = lead_in_time + _turn_time
	# Constant acceleration from the arrival to "over the pad, falling at burn_speed":
	# the lander sheds its sideways speed and joins the braking burn without a jolt.
	var end := Vector3(0.0, burn_altitude, 0.0)
	var end_velocity := Vector3(0.0, -burn_speed, 0.0)
	_start_velocity = 2.0 * (end - approach_start) / _manoeuvre_time - end_velocity
	_acceleration = (end_velocity - _start_velocity) / _manoeuvre_time
	# The turn has died out (to under half a percent) by the time the manoeuvre ends.
	_turn_rate = 5.5 / (TURN_DAMPING * _turn_time)
	_peak_turn_accel = 0.0
	var first_key: float = _manoeuvre_time
	var t: float = 0.0
	while t < _turn_time:
		_peak_turn_accel = maxf(_peak_turn_accel, absf(_turn_accel_at(t)))
		if first_key == _manoeuvre_time and _tilt_at(t) <= deg_to_rad(first_key_frame_tilt):
			first_key = lead_in_time + t
		t += 0.01
	# The motion stops key_frame_ease / 2 of clock after it starts slowing, and needs as much
	# again to pick up, so the second key frame sits that far before the manoeuvre's end.
	_key_times = [first_key, _manoeuvre_time - key_frame_ease * 0.5 - 0.01]
	_key_texts = [
		"%s\n%s: %.1f° de autoridad, giro completo en %.1f s." % [
			_world.how_it_turns, _gimbal_name, _gimbal_deg, _turn_time],
		"%s\n%s: %d kN, frena a %.1f de los %.1f m/s² necesarios (%d %% del empuje)." % [
			_world.how_it_lands, _engine_name, roundi(_thrust_n / 1000.0), _decel, _needed_decel,
			roundi(_throttle * 100.0)],
	]


## Tilt (rad from upright) `t` seconds into the turn: the response of a damped attitude
## controller told to stand the lander up. It starts from rest, swings through, overshoots
## upright by a few degrees and settles.
func _tilt_at(t: float) -> float:
	if t <= 0.0:
		return PI / 2.0
	var decay: float = TURN_DAMPING * _turn_rate
	var swing: float = _turn_rate * sqrt(1.0 - TURN_DAMPING * TURN_DAMPING)
	return PI / 2.0 * exp(-decay * t) * (cos(swing * t) + decay / swing * sin(swing * t))


## Angular acceleration of the turn (rad/s^2): what the engine's deflection has to produce.
func _turn_accel_at(t: float) -> float:
	var h: float = 0.01
	return (_tilt_at(t + h) - 2.0 * _tilt_at(t) + _tilt_at(t - h)) / (h * h)


## Advance the manoeuvre clock, easing it to a stop on each key frame and away again.
func _advance_clock(delta: float) -> void:
	var rate: float = 1.0
	if _key_index < _key_times.size():
		if _key_timer < 0.0 and _clock >= _key_times[_key_index] - key_frame_ease * 0.5:
			_key_timer = 0.0
			_caption.text = _key_texts[_key_index]
		if _key_timer >= 0.0:
			_key_timer += delta
			if _key_timer < key_frame_ease:
				rate = 1.0 - _key_timer / key_frame_ease
			elif _key_timer < key_frame_ease + key_frame_hold:
				rate = 0.0
			elif _key_timer < 2.0 * key_frame_ease + key_frame_hold:
				rate = (_key_timer - key_frame_ease - key_frame_hold) / key_frame_ease
				_caption.text = ""
			else:
				_key_timer = -1.0
				_key_index += 1
	_clock = minf(_clock + delta * rate, _manoeuvre_time)


## Place the lander for the current clock time.
func _fly_manoeuvre() -> void:
	var t: float = _clock
	var at: Vector3 = approach_start + _start_velocity * t + 0.5 * _acceleration * t * t
	_rocket.position = at + Vector3.UP * _stand_height()
	_speed = (_start_velocity + _acceleration * t).length()
	var turning: float = t - lead_in_time
	_tilt = _tilt_at(turning)
	_apply_tilt()
	# The engine lights for the turn; its plume swings with the torque it is producing.
	_rocket.set_engine(turning > 0.0)
	_rocket.set_gimbal(GIMBAL_SHOWN * _turn_accel_at(turning) / _peak_turn_accel if turning > 0.0 else 0.0)
	if turning > 0.0 and _key_timer < 0.0 and _key_index == 0:
		_caption.text = ""


## Constant braking from burn_speed at burn_altitude down to the surface.
func _process_descent() -> void:
	var t: float = minf(_phase_time, _descent_time)
	var height: float = burn_altitude - burn_speed * t + 0.5 * _decel * t * t
	_speed = burn_speed - _decel * t
	_rocket.position = Vector3(0.0, maxf(height, 0.0) + _stand_height(), 0.0)
	_rocket.set_engine(_throttle > 0.0)
	if _phase_time >= _descent_time:
		_speed = 0.0
		_rocket.set_engine(false)
		var soft: bool = _touchdown_speed <= LEG_LIMIT
		_banner.text = _world.success if soft else _world.failure
		if not soft:
			# The legs give way and the lander goes over.
			create_tween().tween_property(_rocket, "rotation:z", -deg_to_rad(64.0), 1.4) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			create_tween().tween_property(_rocket, "position:y", PlanetSurface.PAD_HEIGHT + 1.2, 1.4)
		_banner.show()
		_caption.text = "Contacto a %.1f m/s (las patas aguantan %.1f m/s).%s" % [
			_touchdown_speed, LEG_LIMIT, "" if soft else " Faltó empuje para esta masa.",
		]
		_set_phase(Phase.LANDED)


func _apply_tilt() -> void:
	# The nose leans toward +X, the direction the lander arrives in.
	_rocket.rotation = Vector3(0.0, 0.0, -_tilt)


func _update_telemetry() -> void:
	var altitude: float = maxf(_rocket.position.y - _stand_height(), 0.0)
	if _phase == Phase.LANDED:
		altitude = 0.0
	_telemetry.text = _world.name + "\nAltitud %6.1f m\nVelocidad %5.1f m/s\nInclinación %3d°\nMasa %d kg" % [
		altitude, _speed, roundi(rad_to_deg(_tilt)), roundi(_mass_kg),
	]


## The braking the engine must deliver, and what happens if it cannot.
func _plan_landing() -> void:
	# More control authority turns the lander faster.
	_turn_time = clampf(turn_time * 1.5 / maxf(_gimbal_deg, 0.1), turn_time * 0.8, turn_time * 1.25)
	var needed: float = burn_speed * burn_speed / (2.0 * burn_altitude) # to stop exactly at the surface
	var available: float = _thrust_n / _mass_kg - _gravity # at full thrust
	_needed_decel = needed
	_decel = clampf(needed, -_gravity, available)
	_throttle = clampf((_decel + _gravity) * _mass_kg / _thrust_n, 0.0, 1.0)
	if _decel >= needed:
		_touchdown_speed = 0.0
		_descent_time = 2.0 * burn_altitude / burn_speed
	else:
		# Not enough thrust: it reaches the ground still moving.
		_touchdown_speed = sqrt(maxf(burn_speed * burn_speed - 2.0 * _decel * burn_altitude, 0.0))
		_descent_time = 2.0 * burn_altitude / (burn_speed + _touchdown_speed)


func _load_components() -> void:
	var config: Dictionary = _read_json("res://mission_config.json")
	var catalog: Dictionary = _read_json("res://catalog.json")
	var selected: Dictionary = config.get("selected_components", {})
	if selected.is_empty() or catalog.is_empty():
		return
	var gimbal: Dictionary = _option(catalog, selected, _world.turn_category)
	var engine: Dictionary = _option(catalog, selected, "upper_stage_engine")
	var stage: Dictionary = _option(catalog, selected, "upper_stage")
	if not gimbal.is_empty():
		_gimbal_deg = float(gimbal.physics.get("gimbal_max", _gimbal_deg))
		_gimbal_name = "%s %s" % [_world.turn_label, gimbal.get("tier", "")]
	if not engine.is_empty():
		_thrust_n = float(engine.physics.get("thrust_vac", _thrust_n))
		_engine_name = "Motor superior %s" % engine.get("tier", "")
	if not stage.is_empty() and not engine.is_empty():
		_mass_kg = float(stage.physics.get("dry_mass", 0.0)) + float(engine.physics.get("dry_mass", 0.0)) \
				+ LANDING_PROPELLANT_FRACTION * float(stage.physics.get("propellant", 0.0))


func _option(catalog: Dictionary, selected: Dictionary, category_id: String) -> Dictionary:
	for category in catalog.get("categories", []):
		if category.get("id", "") != category_id:
			continue
		for option in category.get("options", []):
			if option.get("id", "") == selected.get(category_id, "") and option.get("physics") is Dictionary:
				return option
	return {}


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
