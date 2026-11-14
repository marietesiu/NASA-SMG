class_name Rocket
extends Node3D
## Visual model of the rocket. Purely kinematic: OpenRocket computes the motion,
## this node just shows it. The node origin is the rocket's tail.

@export var core_color: Color = Color(0.85, 0.43, 0.14)
@export var white_color: Color = Color(0.93, 0.93, 0.95)
@export var dark_color: Color = Color(0.12, 0.12, 0.13)
## The model is drawn this many times larger than the design OpenRocket simulates.
@export var visual_scale: float = 230.0

## Height of the drawn vehicle in metres (design length x visual_scale).
var length: float = 98.0
## False = engines off (no flame or smoke), whatever the thrust.
var engines_enabled: bool = true

var _model: Node3D
## Core stage, its engines and the boosters: everything dropped by jettison().
var _lower: Node3D
var _section_parent: Node3D
var _flames: Array[GPUParticles3D] = []
var _smoke: GPUParticles3D
var _flame_light: OmniLight3D
var _parachute: Node3D
var _chute_open: bool = false


func _ready() -> void:
	build(length / visual_scale)


## (Re)build the model for a design of the given length (metres, as OpenRocket reports it).
## The shape follows NASA's Space Launch System: orange core stage, two white solid
## rocket boosters, upper stage, crew capsule and launch abort tower.
func build(design_length: float) -> void:
	length = design_length * visual_scale
	if _model != null:
		_model.queue_free()
	_flames.clear()
	_model = Node3D.new()
	_model.position.y = 0.03 * length # nozzles hang below the core; keep them above the pad
	add_child(_model)
	_lower = Node3D.new()
	_model.add_child(_lower)

	var orange := _material(core_color, 0.8)
	var white := _material(white_color, 0.45)
	var dark := _material(dark_color, 0.6)
	var l: float = length
	var core_r: float = 0.043 * l
	var upper_r: float = 0.026 * l
	var booster_r: float = 0.019 * l
	var booster_x: float = core_r + booster_r

	# Core stage, tapered adapter, upper stage, service module, capsule, abort tower.
	_section_parent = _lower
	_section(0.03 * l, 0.66 * l, core_r, core_r, orange)
	_section(0.66 * l, 0.73 * l, core_r, upper_r, orange)
	_section_parent = _model
	_section(0.73 * l, 0.85 * l, upper_r, upper_r, white)
	_section(0.85 * l, 0.89 * l, upper_r, 0.012 * l, white)
	_section(0.89 * l, 0.97 * l, 0.006 * l, 0.006 * l, white)
	_section(0.97 * l, 1.0 * l, 0.006 * l, 0.0, white)
	# Four core engines.
	_section_parent = _lower
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			_section(-0.015 * l, 0.03 * l, 0.013 * l, 0.006 * l, dark, Vector2(x, z) * 0.02 * l)
	# Solid rocket boosters.
	for side: float in [-1.0, 1.0]:
		var at := Vector2(0.0, side * booster_x) # on Z, so both show from the launch camera on +X
		_section(-0.03 * l, 0.0, 0.021 * l, 0.012 * l, dark, at)
		_section(0.0, 0.04 * l, 0.026 * l, booster_r, white, at)
		_section(0.04 * l, 0.52 * l, booster_r, booster_r, white, at)
		_section(0.52 * l, 0.575 * l, booster_r, 0.0, white, at)

	_build_exhaust(core_r, booster_r, booster_x)
	_build_parachute()


## Drop the core stage and boosters: they fall away behind the upper stage and capsule.
func jettison() -> void:
	if _lower == null:
		return
	var dropped := _lower
	_lower = null
	var tween := create_tween()
	tween.set_parallel()
	tween.tween_property(dropped, "position:y", -6.0 * length, 20.0).set_ease(Tween.EASE_IN)
	tween.tween_property(dropped, "position:x", 1.5 * length, 20.0)
	tween.tween_property(dropped, "rotation:z", 1.2, 20.0)
	tween.chain().tween_callback(dropped.queue_free)


## True = lit by the sun (render layer 1), false = in the Earth's shadow (layer 2).
func set_sunlit(lit: bool) -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).layers = 1 if lit else 2


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat


## One round section of the vehicle between two heights, optionally off the centre line.
func _section(y_bottom: float, y_top: float, r_bottom: float, r_top: float,
		mat: Material, at: Vector2 = Vector2.ZERO) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = r_bottom
	mesh.top_radius = r_top
	mesh.height = y_top - y_bottom
	mesh.radial_segments = 32
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = Vector3(at.x, (y_bottom + y_top) * 0.5, at.y)
	_section_parent.add_child(node)


func _build_exhaust(core_r: float, booster_r: float, booster_x: float) -> void:
	# Flames: short-lived, stay attached to the nozzles (core + two boosters).
	# x = offset along the booster axis (Z), y = height, z = flame sprite size.
	var nozzles: Array[Vector3] = [
		Vector3(0.0, -0.015 * length, core_r * 2.5),
		Vector3(-booster_x, -0.03 * length, booster_r * 3.5),
		Vector3(booster_x, -0.03 * length, booster_r * 3.5),
	]
	for nozzle in nozzles:
		var flame := _make_emitter(60, 0.12, nozzle.z, Vector2(length * 2.5, length * 4.0), [
			Color(1.0, 0.97, 0.7, 1.0), Color(1.0, 0.55, 0.1, 0.9), Color(1.0, 0.3, 0.05, 0.0),
		], Vector2(1.0, 0.4))
		flame.local_coords = true
		flame.position = Vector3(0.0, nozzle.y, nozzle.x)
		_flames.append(flame)
	# Smoke: left behind in the world as a trail.
	_smoke = _make_emitter(1500, 6.0, core_r * 5.0, Vector2(0.0, length * 0.5), [
		Color(0.85, 0.85, 0.85, 0.55), Color(0.9, 0.9, 0.9, 0.3), Color(1.0, 1.0, 1.0, 0.0),
	], Vector2(0.6, 3.0))
	_smoke.local_coords = false
	_smoke.fixed_fps = 0 # emit every rendered frame; the rocket moves fast
	_smoke.position.y = -0.03 * length

	_flame_light = OmniLight3D.new()
	_flame_light.light_color = Color(1.0, 0.6, 0.2)
	_flame_light.omni_range = length * 2.0
	_flame_light.light_energy = 0.0
	_flame_light.position.y = -0.05 * length
	_model.add_child(_flame_light)


func _make_emitter(amount: int, lifetime: float, size: float, speed: Vector2,
		colors: Array[Color], scale_over_life: Vector2) -> GPUParticles3D:
	# Soft round sprite so puffs don't show up as squares.
	var falloff := Gradient.new()
	falloff.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var sprite := GradientTexture2D.new()
	sprite.gradient = falloff
	sprite.fill = GradientTexture2D.FILL_RADIAL
	sprite.fill_from = Vector2(0.5, 0.5)
	sprite.fill_to = Vector2(1.0, 0.5)

	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw_mat.billboard_keep_scale = true
	draw_mat.albedo_texture = sprite
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	quad.material = draw_mat

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	ramp.colors = PackedColorArray(colors)
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	var growth := Curve.new()
	growth.max_value = maxf(scale_over_life.x, scale_over_life.y)
	growth.add_point(Vector2(0.0, scale_over_life.x))
	growth.add_point(Vector2(1.0, scale_over_life.y))
	var growth_tex := CurveTexture.new()
	growth_tex.curve = growth

	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.DOWN
	process.spread = 6.0
	process.initial_velocity_min = speed.x
	process.initial_velocity_max = speed.y
	process.gravity = Vector3.ZERO
	process.color_ramp = ramp_tex
	process.scale_curve = growth_tex

	var emitter := GPUParticles3D.new()
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.process_material = process
	emitter.draw_pass_1 = quad
	emitter.emitting = false
	# Trails stretch far from the emitter; never cull them.
	emitter.visibility_aabb = AABB(Vector3.ONE * -5000.0, Vector3.ONE * 10000.0)
	_model.add_child(emitter)
	return emitter


func _build_parachute() -> void:
	_parachute = Node3D.new()
	_parachute.visible = false
	_parachute.position.y = length * 0.97
	_model.add_child(_parachute)

	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = core_color
	canopy_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = length * 0.45
	canopy_mesh.height = length * 0.45
	canopy_mesh.is_hemisphere = true
	canopy_mesh.material = canopy_mat
	var canopy := MeshInstance3D.new()
	canopy.mesh = canopy_mesh
	canopy.position.y = length * 0.9
	_parachute.add_child(canopy)

	var line_mesh := CylinderMesh.new()
	line_mesh.top_radius = canopy_mesh.radius
	line_mesh.bottom_radius = 0.0
	line_mesh.height = length * 0.9
	line_mesh.radial_segments = 8
	line_mesh.cap_top = false
	line_mesh.cap_bottom = false
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(1, 1, 1, 0.25)
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	line_mesh.material = line_mat
	var lines := MeshInstance3D.new()
	lines.mesh = line_mesh
	lines.position.y = length * 0.45
	_parachute.add_child(lines)


## Apply a flight state from OpenRocketSim.get_state().
func apply_state(state: Dictionary, delta: float) -> void:
	position = state.position
	var axis: Vector3 = state.axis
	if _chute_open:
		# Under the parachute the rocket hangs from its nose.
		axis = (Vector3.UP * 4.0 - state.velocity.normalized()).normalized()
	var target := Quaternion(Vector3.UP, axis) if axis.dot(Vector3.UP) > -0.999 \
			else Quaternion(Vector3.RIGHT, PI)
	var blend: float = 1.0 - exp(-(4.0 if _chute_open else 40.0) * delta)
	quaternion = quaternion.slerp(target, blend)

	_set_burning(engines_enabled and state.thrust > 0.01)


## Place the vehicle directly: tail at `at`, nose pointing along `nose`, with `side`
## as the (roughly perpendicular) direction its boosters line up on. No smoothing.
func set_pose(at: Vector3, nose: Vector3, side: Vector3) -> void:
	var y: Vector3 = nose.normalized()
	var x: Vector3 = (side - y * side.dot(y)).normalized()
	global_transform = Transform3D(Basis(x, y, x.cross(y)).scaled(scale), at)
	_set_burning(false)


func _set_burning(burning: bool) -> void:
	for flame in _flames:
		flame.emitting = burning
	_smoke.emitting = burning
	_flame_light.light_energy = 2.0 if burning else 0.0


## Remove all flame and smoke particles.
func clear_exhaust() -> void:
	_smoke.restart()
	_smoke.emitting = false
	for flame in _flames:
		flame.restart()
		flame.emitting = false


func deploy_parachute() -> void:
	_chute_open = true
	_parachute.visible = true
	_parachute.scale = Vector3.ONE * 0.05
	create_tween().tween_property(_parachute, "scale", Vector3.ONE, 0.6) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
