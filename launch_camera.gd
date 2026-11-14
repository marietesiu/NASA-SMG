class_name LaunchCamera
extends Camera3D
## Launch camera with a constant angle of elevation to the top of the rocket.
##
## The camera's height (Y) never changes. As the rocket climbs, the camera slides
## back along X just far enough that the top of the rocket stays at the same angle
## above the horizon it had on the pad, and its Z follows the rocket's Z.
## Because the camera gets ever further away, it also zooms in to keep the rocket
## the same size on screen.

@export var target: Node3D
## Camera height above the ground, in rocket lengths.
@export var height_in_lengths: float = 0.1
## Horizontal distance from the rocket on the pad, in rocket lengths. Together with
## the height this fixes the angle of elevation for the whole flight.
@export var initial_distance_in_lengths: float = 3.0
## How many rocket lengths fit in the height of the frame.
@export var lengths_in_frame: float = 4.0
@export var min_fov: float = 1.0
@export var max_fov: float = 60.0

## While true the camera stays exactly where it is and the rocket flies out of frame.
var frozen: bool = false

var _length: float = 1.0
var _height: float = 0.0
var _tan_elevation: float = 1.0


## Set up for a rocket of the given length standing on the pad (origin at its tail).
func frame_target(target_length: float) -> void:
	_length = target_length
	_height = height_in_lengths * target_length
	_tan_elevation = (target_length - _height) / (initial_distance_in_lengths * target_length)
	_follow()


## Angle of elevation from the camera to the top of the rocket, in degrees.
func get_elevation_angle() -> float:
	return rad_to_deg(atan(_tan_elevation))


func _process(_delta: float) -> void:
	if target != null and not frozen:
		_follow()


func _follow() -> void:
	var tail: Vector3 = target.global_position
	var top_height: float = tail.y + _length
	global_position = Vector3(tail.x + (top_height - _height) / _tan_elevation, _height, tail.z)
	var focus: Vector3 = tail + Vector3.UP * _length * 0.5
	look_at(focus)
	var distance: float = global_position.distance_to(focus)
	fov = clampf(rad_to_deg(2.0 * atan(lengths_in_frame * _length * 0.5 / distance)), min_fov, max_fov)
