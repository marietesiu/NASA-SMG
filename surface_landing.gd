extends Node3D
## Landing on the Moon or on Mars. The coast from the edge of Earth's atmosphere is skipped:
## the scene opens with the lander already falling toward the surface.
##
## The camera stands on the surface and never moves: it watches the lander come down.
## Sequence: approach (nose first) -> flip, paused on three key frames with an explanation
## (about 7 s) -> legs out and braking burn -> touchdown.
## R = restart, Esc = quit.

enum Phase { APPROACH, FLIP, DESCENT, LANDED }

## What changes between the two worlds: gravity, which component turns the lander, and the
## three explanations shown on the key frames of the flip.
const BODIES := {
	PlanetSurface.Body.MOON: {
		"name": "Luna",
		"gravity": 1.62, # m/s^2
		"turn_category": "gimbal_system",
		"turn_label": "Cardán",
		"arrival": "Trayecto Tierra - Luna omitido. Llegando a la superficie lunar.",
		"how_it_turns": "CÓMO GIRA: en la Luna no hay aire, así que las aletas no sirven. "
				+ "El motor se inclina sobre su cardán y el empuje, ya descentrado, hace rotar el cohete.",
		"how_it_lands": "CÓMO ATERRIZA: con la cola hacia abajo despliega las patas, "
				+ "el motor frena la caída hasta casi cero y las patas absorben el contacto.",
		"success": "Alunizaje completado",
		"failure": "Alunizaje fallido",
	},
	PlanetSurface.Body.MARS: {
		"name": "Marte",
		"gravity": 3.71,
		"turn_category": "control_fins",
		"turn_label": "Aletas de control",
		"arrival": "Trayecto Tierra - Marte omitido. Entrada atmosférica superada, llegando a la superficie.",
		"how_it_turns": "CÓMO GIRA: Marte sí tiene aire, cien veces más fino que el de la Tierra. "
				+ "Las aletas de control muerden ese aire para levantar la punta y el motor termina el giro.",
		"how_it_lands": "CÓMO ATERRIZA: el aire ya no frena lo bastante y Marte tira más del doble que la Luna. "
				+ "Con la cola hacia abajo despliega las patas y el motor hace todo el frenado final.",
		"success": "Aterrizaje en Marte completado",
		"failure": "Aterrizaje en Marte fallido",
	},
}
## Fastest touchdown the legs absorb (m/s).
const LEG_LIMIT := 4.0
## Fraction of the upper stage's propellant still on board for the landing.
const LANDING_PROPELLANT_FRACTION := 0.2

@export var body: PlanetSurface.Body = PlanetSurface.Body.MOON
## Direction the sunlight comes from.
@export var sun_from := Vector3(-0.62, 0.42, 0.66)
@export_group("Trajectory")
## Where the lander appears, relative to the landing spot (m).
@export var approach_start := Vector3(-90.0, 125.0, 0.0)
## Height at which it flips and starts the braking burn (m).
@export var burn_altitude: float = 80.0
## Descent speed at the start of the braking burn (m/s).
@export var burn_speed: float = 16.0
@export var approach_time: float = 3.0
@export_group("Explained flip")
## Seconds each key frame is held.
@export var key_frame_hold: float = 2.0
## Seconds per rotation step with a 1.5 deg gimbal; a wider gimbal turns faster.
@export var turn_step_time: float = 0.5
@export_group("Camera on the surface")
@export var camera_position := Vector3(-15.0, 1.7, 150.0)
@export var camera_target := Vector3(-25.0, 52.0, 0.0)

@onready var _surface: PlanetSurface = $Surface
@onready var _rocket: Rocket = $Rocket
@onready var _camera: Camera3D = $SurfaceCamera
@onready var _telemetry: Label = %Telemetry
@onready var _caption: Label = %Caption
@onready var _banner: Label = %Banner

var _phase: Phase = Phase.APPROACH
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

var _turn_time: float = 0.5
var _decel: float = 0.0 # braking deceleration actually flown (m/s^2)
var _touchdown_speed: float = 0.0
var _throttle: float = 0.0
var _descent_time: float = 0.0
var _needed_decel: float = 0.0
var _world: Dictionary
var _gravity: float = 1.62


func _ready() -> void:
	_world = BODIES[body]
	_gravity = _world.gravity
	_gimbal_name = _world.turn_label
	_load_components()
	_plan_landing()
	_rocket.make_lander()
	($Sun as DirectionalLight3D).look_at_from_position(sun_from.normalized() * 100.0, Vector3.ZERO)
	# The camera stands on the ground and stays there for the whole landing.
	_camera.global_position = camera_position \
			+ Vector3.UP * _surface.height_at(camera_position.x, camera_position.z)
	_camera.look_at(camera_target, Vector3.UP)
	_rocket.position = approach_start
	_apply_tilt()
	_caption.text = _world.arrival


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		get_tree().reload_current_scene()


func _process(delta: float) -> void:
	_phase_time += delta
	match _phase:
		Phase.APPROACH:
			_process_approach()
		Phase.FLIP:
			_process_flip()
		Phase.DESCENT:
			_process_descent()
	_update_telemetry()


func _set_phase(phase: Phase) -> void:
	_phase = phase
	_phase_time = 0.0


func _hover_point() -> Vector3:
	return Vector3(0.0, burn_altitude + _stand_height(), 0.0)


## Height of the lander's origin when it stands on the pad.
func _stand_height() -> float:
	return _rocket.lander_ground_offset + PlanetSurface.PAD_HEIGHT


func _process_approach() -> void:
	var w: float = clampf(_phase_time / approach_time, 0.0, 1.0)
	_rocket.position = approach_start.lerp(_hover_point(), w)
	_speed = approach_start.distance_to(_hover_point()) / approach_time
	if w >= 1.0:
		_set_phase(Phase.FLIP)


## Three held key frames with two rotation steps between them.
func _process_flip() -> void:
	_rocket.position = _hover_point()
	_speed = burn_speed
	var t: float = _phase_time
	var hold: float = key_frame_hold
	if t < hold:
		_tilt = PI / 2.0
		_rocket.set_engine(true)
		_caption.text = _world.how_it_turns
	elif t < hold + _turn_time:
		_tilt = lerpf(PI / 2.0, PI / 4.0, smoothstep(0.0, 1.0, (t - hold) / _turn_time))
		_caption.text = ""
	elif t < 2.0 * hold + _turn_time:
		_tilt = PI / 4.0
		_caption.text = "DOS COMPONENTES LO DECIDEN: %s (%.1f° de autoridad: cada paso de giro tarda %.2f s) " \
				% [_gimbal_name, _gimbal_deg, _turn_time] \
				+ "y %s (%d kN: frena a %.1f m/s² de los %.1f que hacen falta, con el %d %% del empuje)." \
				% [_engine_name, roundi(_thrust_n / 1000.0), _decel, _needed_decel, roundi(_throttle * 100.0)]
	elif t < 2.0 * hold + 2.0 * _turn_time:
		_tilt = lerpf(PI / 4.0, 0.0, smoothstep(0.0, 1.0, (t - 2.0 * hold - _turn_time) / _turn_time))
		_caption.text = ""
	elif t < 3.0 * hold + 2.0 * _turn_time:
		_tilt = 0.0
		_caption.text = _world.how_it_lands
	else:
		_tilt = 0.0
		_caption.text = ""
		_rocket.deploy_legs(1.5)
		_set_phase(Phase.DESCENT)
	_apply_tilt()


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
			create_tween().tween_property(_rocket, "rotation:z", -PI / 2.0, 1.6) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			create_tween().tween_property(_rocket, "position:y", PlanetSurface.PAD_HEIGHT + 2.5, 1.6)
		_banner.show()
		_caption.text = "Contacto a %.1f m/s (las patas aguantan %.1f m/s).%s" % [
			_touchdown_speed, LEG_LIMIT,
			"" if soft else " El motor no tenía empuje suficiente para frenar esta masa.",
		]
		_set_phase(Phase.LANDED)


func _apply_tilt() -> void:
	# The nose leans toward +X, the direction the lander arrives in.
	_rocket.rotation = Vector3(0.0, 0.0, -_tilt)


func _update_telemetry() -> void:
	var altitude: float = maxf(_rocket.position.y - _stand_height(), 0.0)
	if _phase == Phase.LANDED:
		altitude = 0.0
	_telemetry.text = _world.name + "\nAltitud %6.1f m\nVelocidad %5.1f m/s\nInclinación %3.0f°\nMasa %d kg" % [
		altitude, _speed, rad_to_deg(_tilt), roundi(_mass_kg),
	]


## The braking the engine must deliver, and what happens if it cannot.
func _plan_landing() -> void:
	_turn_time = clampf(turn_step_time * 1.5 / maxf(_gimbal_deg, 0.1), 0.25, 1.0)
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
