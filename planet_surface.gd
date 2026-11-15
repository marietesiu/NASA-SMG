class_name PlanetSurface
extends Node3D
## Ground of the Moon or Mars around the landing site, built in code: terrain with craters,
## dunes and distant hills, scattered rocks, a landing pad and a small outpost.
## The landing site is the node's origin; the ground is level there.

enum Body { MOON, MARS }

@export var body: Body = Body.MOON
@export var terrain_seed: int = 7
## Side of the detailed terrain around the landing site (m) and its number of cells per side.
@export var near_size: float = 640.0
@export var near_cells: int = 200
## Side of the coarse terrain that carries the hills on the horizon (m).
@export var far_size: float = 9000.0
@export var far_cells: int = 110
## The ground stays level out to this distance from the landing site (m), so nothing
## hides the lander from a camera standing inside it.
@export var level_radius: float = 190.0
@export var rock_count: int = 420
@export var crater_count: int = 60
## Line on the ground kept clear of rocks and crater rims (landing site -> camera).
@export var clear_line_to := Vector3(-15.0, 0.0, 150.0)

## Height of the landing pad's top above the ground (m).
const PAD_HEIGHT := 0.25
const PAD_RADIUS := 13.0

var _relief := FastNoiseLite.new()
var _mesas := FastNoiseLite.new()
var _tint := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
## x, z, radius of each crater.
var _craters: Array[Vector3] = []


func _ready() -> void:
	_rng.seed = terrain_seed
	_relief.seed = terrain_seed
	_relief.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_relief.fractal_octaves = 5
	_relief.frequency = 0.0016
	_mesas.seed = terrain_seed + 1
	_mesas.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mesas.fractal_octaves = 2
	_mesas.frequency = 0.0007
	_tint.seed = terrain_seed + 2
	_tint.frequency = 0.012

	_place_craters()
	var ground := _ground_material()
	_add(_terrain_mesh(near_size, near_cells, 0.0, true), Vector3.ZERO, Vector3.ZERO, ground)
	# The coarse terrain lies just under the detailed one, so no gap shows where they meet.
	_add(_terrain_mesh(far_size, far_cells, -1.5, false), Vector3.ZERO, Vector3.ZERO, ground)
	_scatter_rocks()
	_build_pad()
	_build_outpost()
	if body == Body.MARS:
		_build_rover(Vector3(-42.0, 0.0, 96.0), 0.6)
	else:
		_build_earth()


## Ground height (m) at a point, craters included.
func height_at(x: float, z: float) -> float:
	var h: float = _base_height(x, z)
	for c in _craters:
		var d: float = Vector2(x - c.x, z - c.y).length() / c.z
		if d < 1.8:
			h += _crater_profile(d, c.z)
	return h


# ---------------------------------------------------------------- terrain shape

## Height without craters: level at the landing site, rising into hills far away.
func _base_height(x: float, z: float) -> float:
	var r: float = Vector2(x, z).length()
	var far: float = smoothstep(level_radius, 1700.0, r)
	var h: float = far * 70.0 * _relief.get_noise_2d(x, z)
	if body == Body.MARS:
		# Flat-topped mesas, and low dunes everywhere but on the landing site.
		h += far * 150.0 * smoothstep(0.12, 0.3, _mesas.get_noise_2d(x, z))
		h += 0.28 * smoothstep(25.0, 60.0, r) * sin(x * 0.21 + 2.0 * _relief.get_noise_2d(z, x)) \
				* (0.6 + 0.4 * sin(z * 0.05))
	else:
		# Rounded lunar highlands, and a gentle roll close in that stays below eye level.
		h = far * (150.0 * _relief.get_noise_2d(x, z) + 380.0 * maxf(_mesas.get_noise_2d(x, z), 0.0))
		h -= 0.5 * smoothstep(40.0, 120.0, r) * (0.5 + 0.5 * _tint.get_noise_2d(x * 0.3, z * 0.3))
	return h


## Bowl with a raised rim; d = distance from the centre in crater radii.
func _crater_profile(d: float, radius: float) -> float:
	var depth: float = (0.22 if body == Body.MOON else 0.1) * radius
	var bowl: float = -depth * (1.0 - d * d) if d < 1.0 else 0.0
	var rim: float = (0.075 if body == Body.MOON else 0.035) * radius * exp(-pow((d - 1.0) / 0.22, 2.0))
	return bowl + rim


func _place_craters() -> void:
	var count: int = crater_count if body == Body.MOON else crater_count / 5
	var tries: int = 0
	while _craters.size() < count and tries < count * 40:
		tries += 1
		var radius: float = lerpf(3.0, 34.0, pow(_rng.randf(), 2.5))
		var at := Vector2(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.5, 0.5)) * (near_size - 80.0)
		if at.length() < PAD_RADIUS + 12.0 + radius * 1.5:
			continue
		if _distance_to_clear_line(at) < radius * 1.6 + 8.0:
			continue
		_craters.append(Vector3(at.x, at.y, radius))


func _distance_to_clear_line(p: Vector2) -> float:
	var b := Vector2(clear_line_to.x, clear_line_to.z)
	var t: float = clampf(p.dot(b) / b.length_squared(), 0.0, 1.15)
	return p.distance_to(b * t)


## Square grid of the terrain. `detailed` stamps the craters into it.
func _terrain_mesh(size: float, cells: int, offset: float, detailed: bool) -> ArrayMesh:
	var n: int = cells + 1
	var step: float = size / cells
	var heights := PackedFloat32Array()
	var shades := PackedFloat32Array()
	heights.resize(n * n)
	shades.resize(n * n)
	for j in n:
		var z: float = -size * 0.5 + j * step
		for i in n:
			var x: float = -size * 0.5 + i * step
			heights[j * n + i] = _base_height(x, z) + offset
			shades[j * n + i] = 0.8 + 0.2 * _tint.get_noise_2d(x, z) + 0.12 * _mesas.get_noise_2d(x * 6.0, z * 6.0)
	if detailed:
		for c in _craters:
			var reach: int = ceili(c.z * 1.8 / step)
			var ci: int = roundi((c.x + size * 0.5) / step)
			var cj: int = roundi((c.y + size * 0.5) / step)
			for j in range(maxi(cj - reach, 0), mini(cj + reach, cells) + 1):
				for i in range(maxi(ci - reach, 0), mini(ci + reach, cells) + 1):
					var x: float = -size * 0.5 + i * step
					var z: float = -size * 0.5 + j * step
					var d: float = Vector2(x - c.x, z - c.y).length() / c.z
					if d >= 1.8:
						continue
					heights[j * n + i] += _crater_profile(d, c.z)
					# Dark floor, bright freshly thrown rim.
					shades[j * n + i] *= lerpf(0.6, 1.0, smoothstep(0.3, 1.0, d)) \
							+ 0.4 * exp(-pow((d - 1.05) / 0.25, 2.0))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n:
		for i in n:
			var s: float = shades[j * n + i]
			st.set_color(Color(s, s, s))
			st.add_vertex(Vector3(-size * 0.5 + i * step, heights[j * n + i], -size * 0.5 + j * step))
	for j in cells:
		for i in cells:
			var a: int = j * n + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + n)
			st.add_index(a + 1)
			st.add_index(a + n + 1)
			st.add_index(a + n)
	st.generate_normals()
	return st.commit()


# ---------------------------------------------------------------- materials

func _noise_texture(seed_offset: int, frequency: float, octaves: int, ramp: Gradient,
		normal_strength: float = 0.0) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = terrain_seed + seed_offset
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = octaves
	noise.frequency = frequency
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	if normal_strength > 0.0:
		tex.as_normal_map = true
		tex.bump_strength = normal_strength
	else:
		tex.color_ramp = ramp
	return tex


func _ramp(colors: Array[Color]) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	for i in colors.size():
		offsets.append(float(i) / (colors.size() - 1))
	g.offsets = offsets
	g.colors = PackedColorArray(colors)
	return g


## Two layers of colour and relief, mapped on the world so they never stretch on slopes:
## broad patches every `patch` metres and grain every `grain` metres.
func _rough_material(colors: Array[Color], patch: float, grain: float, bump: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _noise_texture(10, 0.012, 5, _ramp(colors))
	mat.normal_enabled = true
	mat.normal_texture = _noise_texture(11, 0.02, 5, null, bump)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / patch
	mat.detail_enabled = true
	mat.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	mat.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	mat.detail_albedo = _noise_texture(12, 0.05, 4, _ramp([Color(0.62, 0.62, 0.62), Color(1, 1, 1)]))
	mat.detail_normal = _noise_texture(13, 0.06, 4, null, bump * 1.5)
	mat.uv2_triplanar = true
	mat.uv2_world_triplanar = true
	mat.uv2_scale = Vector3.ONE / grain
	return mat


func _ground_material() -> StandardMaterial3D:
	if body == Body.MARS:
		return _rough_material([Color(0.36, 0.17, 0.1), Color(0.62, 0.33, 0.18), Color(0.8, 0.5, 0.3)], 70.0, 4.0, 7.0)
	return _rough_material([Color(0.13, 0.13, 0.14), Color(0.33, 0.33, 0.33), Color(0.6, 0.59, 0.57)], 70.0, 4.0, 12.0)


func _rock_material() -> StandardMaterial3D:
	if body == Body.MARS:
		return _rough_material([Color(0.16, 0.1, 0.09), Color(0.33, 0.19, 0.13), Color(0.5, 0.3, 0.2)], 3.0, 0.7, 8.0)
	return _rough_material([Color(0.14, 0.14, 0.15), Color(0.3, 0.3, 0.3), Color(0.46, 0.45, 0.44)], 3.0, 0.7, 8.0)


func _plain(color: Color, roughness: float = 0.6, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


# ---------------------------------------------------------------- rocks

## One boulder: a squashed sphere with its surface pushed in and out, flat shaded.
func _rock_mesh() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.5
	sphere.radial_segments = 9
	sphere.rings = 5
	var arrays: Array = sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var lumps := FastNoiseLite.new()
	lumps.seed = terrain_seed + 20
	lumps.frequency = 0.9
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in indices:
		var v: Vector3 = vertices[index]
		st.set_color(Color.WHITE)
		st.add_vertex(v * (1.0 + 0.3 * lumps.get_noise_3dv(v * 2.0)))
	st.generate_normals()
	return st.commit()


func _scatter_rocks() -> void:
	var mesh := _rock_mesh()
	mesh.surface_set_material(0, _rock_material())
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	var transforms: Array[Transform3D] = []
	var tries: int = 0
	while transforms.size() < rock_count and tries < rock_count * 20:
		tries += 1
		var at := Vector2.from_angle(_rng.randf() * TAU) * lerpf(PAD_RADIUS + 4.0, near_size * 0.48, sqrt(_rng.randf()))
		var size: float = lerpf(0.12, 1.9, pow(_rng.randf(), 4.0))
		if _distance_to_clear_line(at) < 3.0 + size * 3.0:
			continue
		var turn := Basis.from_euler(Vector3(_rng.randf() * 0.5, _rng.randf() * TAU, _rng.randf() * 0.5))
		var shape := Vector3(size * _rng.randf_range(0.7, 1.4), size * _rng.randf_range(0.5, 1.0), size)
		# Sunk a little into the ground.
		var origin := Vector3(at.x, height_at(at.x, at.y) + shape.y * 0.25, at.y)
		transforms.append(Transform3D(turn.scaled(shape), origin))
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	add_child(node)


# ---------------------------------------------------------------- structures

func _add(mesh: Mesh, at: Vector3, turn: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	node.rotation = turn
	parent.add_child(node)
	return node


func _cylinder(radius: float, height: float, top_radius: float = -1.0) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	return mesh


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _dome(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius
	mesh.is_hemisphere = true
	return mesh


## Circular landing pad with a marked ring and four lamps.
func _build_pad() -> void:
	var deck: Color = Color(0.3, 0.3, 0.32) if body == Body.MOON else Color(0.34, 0.27, 0.24)
	_add(_cylinder(PAD_RADIUS, PAD_HEIGHT), Vector3(0, PAD_HEIGHT * 0.5, 0), Vector3.ZERO, _plain(deck, 0.9))
	var ring := TorusMesh.new()
	ring.inner_radius = PAD_RADIUS * 0.62
	ring.outer_radius = PAD_RADIUS * 0.68
	_add(ring, Vector3(0, PAD_HEIGHT - 0.28, 0), Vector3.ZERO, _plain(Color(0.85, 0.82, 0.7), 0.8))
	var lamp := _plain(Color(1.0, 0.75, 0.3))
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.65, 0.2)
	lamp.emission_energy_multiplier = 3.0
	var bulb := SphereMesh.new()
	bulb.radius = 0.22
	bulb.height = 0.44
	for i in 4:
		var dir := Vector3(cos(i * PI / 2.0), 0.0, sin(i * PI / 2.0))
		_add(bulb, dir * (PAD_RADIUS - 0.6) + Vector3.UP * (PAD_HEIGHT + 0.2), Vector3.ZERO, lamp)


## Small base beside the pad: two habitat modules, a dome, solar panels and an antenna.
func _build_outpost() -> void:
	var base := Node3D.new()
	base.position = Vector3(58.0, 0.0, -18.0)
	base.position.y = height_at(base.position.x, base.position.z)
	add_child(base)
	var hull := _plain(Color(0.86, 0.86, 0.84), 0.55)
	var dark := _plain(Color(0.2, 0.2, 0.22), 0.7)
	var panel := _plain(Color(0.04, 0.07, 0.22), 0.25, 0.6)
	var foil := _plain(Color(0.78, 0.6, 0.22), 0.35, 0.7)

	# Habitat modules: cylinders on their side, half sunk, joined by a tunnel.
	var module := CapsuleMesh.new()
	module.radius = 2.6
	module.height = 13.0
	_add(module, Vector3(0, 1.5, 0), Vector3(0, 0, PI / 2.0), hull, base)
	_add(module, Vector3(4.0, 1.5, -9.0), Vector3(0, 0.5, PI / 2.0), hull, base)
	_add(_cylinder(1.1, 6.0), Vector3(1.5, 1.2, -4.5), Vector3(PI / 2.0, 0.3, 0), dark, base)
	_add(_cylinder(1.0, 0.25), Vector3(0, 1.5, 2.65), Vector3(PI / 2.0, 0, 0), dark, base) # airlock door
	# Greenhouse dome.
	_add(_dome(4.2), Vector3(-12.0, 0.0, -5.0), Vector3.ZERO, _plain(Color(0.7, 0.8, 0.85), 0.15, 0.3), base)
	_add(_cylinder(4.4, 0.5), Vector3(-12.0, 0.25, -5.0), Vector3.ZERO, dark, base)
	# Solar panels on posts, facing the sun.
	for i in 4:
		var at := Vector3(11.0 + i * 5.5, 0.0, 6.0)
		at.y = height_at(base.position.x + at.x, base.position.z + at.z) - base.position.y
		_add(_cylinder(0.12, 2.4), at + Vector3.UP * 1.2, Vector3.ZERO, dark, base)
		_add(_box(Vector3(4.6, 0.08, 2.6)), at + Vector3.UP * 2.5, Vector3(0.7, 0.0, 0.0), panel, base)
	# Antenna: mast, dish and feed.
	var mast_at := Vector3(-3.0, 0.0, -14.0)
	_add(_cylinder(0.16, 9.0), mast_at + Vector3.UP * 4.5, Vector3.ZERO, dark, base)
	_add(_cylinder(0.2, 0.7, 1.9), mast_at + Vector3(0.0, 9.2, 0.25), Vector3(1.0, 0.0, 0.0), hull, base)
	# Fuel tanks.
	for i in 2:
		_add(_dome(1.6), Vector3(19.0 + i * 4.0, 1.4, -8.0), Vector3.ZERO, foil, base)
		_add(_cylinder(1.6, 1.4), Vector3(19.0 + i * 4.0, 0.7, -8.0), Vector3.ZERO, foil, base)


## Six-wheeled rover with a camera mast.
func _build_rover(at: Vector3, heading: float) -> void:
	var rover := Node3D.new()
	rover.position = Vector3(at.x, height_at(at.x, at.z), at.z)
	rover.rotation.y = heading
	add_child(rover)
	var body_mat := _plain(Color(0.8, 0.78, 0.72), 0.5)
	var dark := _plain(Color(0.1, 0.1, 0.11), 0.8)
	_add(_box(Vector3(2.6, 0.5, 1.5)), Vector3(0, 0.95, 0), Vector3.ZERO, body_mat, rover)
	_add(_box(Vector3(2.2, 0.05, 1.3)), Vector3(-0.1, 1.24, 0), Vector3.ZERO, _plain(Color(0.04, 0.07, 0.22), 0.25, 0.6), rover)
	_add(_cylinder(0.05, 1.3), Vector3(1.0, 1.85, 0.4), Vector3.ZERO, dark, rover)
	_add(_box(Vector3(0.22, 0.2, 0.45)), Vector3(1.0, 2.55, 0.4), Vector3.ZERO, body_mat, rover)
	for side: float in [-1.0, 1.0]:
		for i in 3:
			_add(_cylinder(0.36, 0.3), Vector3(-1.05 + i * 1.05, 0.36, side * 0.95), Vector3(PI / 2.0, 0, 0), dark, rover)


## The Earth in the lunar sky, lit by the same sun as the ground.
func _build_earth() -> void:
	var globe := SphereMesh.new()
	globe.radius = 260.0
	globe.height = 520.0
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://textures/earth_8k.jpg")
	mat.roughness = 1.0
	var node := _add(globe, Vector3(0.45, 0.52, -0.72).normalized() * 15000.0, Vector3(0.4, 2.0, 0.0), mat)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
