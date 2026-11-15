class_name CelestialBody
extends Node3D
## The Earth, the Moon or Mars as a 3D model, built from the supplied model files.
##
## Earth:  earth/earth.blend needs Blender to import, so the same maps go on a sphere: day
##         colour, glossy oceans (land mask), relief (Bump.jpg as a normal map), city lights
##         that appear only on the night side, a cloud shell and a thin haze.
## Moon:   models/Moon.fbx (MoonModel/Moon.fbx) with the 2k Moon map and a normal map made
##         from Moon+Displacement.tif.
## Mars:   models/Mars.obj (Mars/OBJ/Mars.obj) with Mars/DAE/Mars.jpg.
## Every body is scaled so its radius is `radius` scene units, whatever the mesh's own size.
## The textures are made by tools/make_body_assets.sh.

enum Kind { EARTH, MOON, MARS }

const MODELS := {
	Kind.MOON: "res://models/Moon.fbx",
	Kind.MARS: "res://models/Mars.obj",
}
const TEXTURES := "res://textures/bodies/"
## The Moon FBX asks for a colour map (lroc_color_poles_16k.tif) that was not supplied, so
## the project's 2k Moon map is used instead; both are equirectangular, so it fits the mesh.
const MOON_COLOR := "res://textures/2k_moon.jpg"
## Shell radii relative to the surface.
const CLOUD_RADIUS := 1.012
const HAZE_RADIUS := 1.07

@export var kind: Kind = Kind.EARTH
## Radius in scene units.
@export var radius: float = 1000.0
@export var spin_degrees_per_second: float = 0.0
## Strength of the relief shading (the normal map).
@export_range(0.0, 2.0) var relief_strength: float = 1.0
## Build in _ready(). Turn off when a script sets `kind` and `radius` first and calls build().
@export var auto_build: bool = true

var _surface: Node3D
var _clouds: Node3D
var _sun_materials: Array[ShaderMaterial] = []


func _ready() -> void:
	if auto_build:
		build()


## (Re)build the model for the current `kind` and `radius`.
func build() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_sun_materials.clear()
	_clouds = null
	_surface = Node3D.new()
	_surface.name = "Surface"
	add_child(_surface)
	match kind:
		Kind.EARTH:
			_build_earth()
		Kind.MOON:
			_build_moon()
		Kind.MARS:
			_build_mars()


## World-space direction pointing from the body at the sun. Lets the Earth show its city
## lights only on the night side and the haze glow only on the lit side.
func set_sun_direction(to_sun: Vector3) -> void:
	for material in _sun_materials:
		material.set_shader_parameter("sun_direction", to_sun.normalized())


func _process(delta: float) -> void:
	if spin_degrees_per_second == 0.0 or _surface == null:
		return
	var turn: float = deg_to_rad(spin_degrees_per_second) * delta
	_surface.rotate_y(turn)
	if _clouds != null:
		_clouds.rotate_y(turn * 0.4) # clouds drift a little faster than the ground


func _build_earth() -> void:
	var surface := ShaderMaterial.new()
	surface.shader = load("res://earth_surface.gdshader")
	surface.set_shader_parameter("day_tex", _texture("earth_day.jpg"))
	surface.set_shader_parameter("land_mask_tex", _texture("earth_land_mask.png"))
	surface.set_shader_parameter("night_tex", _texture("earth_night.png"))
	surface.set_shader_parameter("normal_tex", _texture("earth_normal.png"))
	surface.set_shader_parameter("normal_strength", relief_strength)
	_sun_materials.append(surface)
	_add_mesh(_surface, _sphere(), surface, radius)

	_clouds = Node3D.new()
	_clouds.name = "Clouds"
	add_child(_clouds)
	var clouds := ShaderMaterial.new()
	clouds.shader = load("res://earth_clouds.gdshader")
	clouds.set_shader_parameter("clouds_tex", _texture("earth_clouds.png"))
	_add_mesh(_clouds, _sphere(), clouds, radius * CLOUD_RADIUS)

	_add_haze(Color(0.35, 0.6, 1.0), 1.4, HAZE_RADIUS)


func _build_moon() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(MOON_COLOR)
	material.normal_enabled = true
	material.normal_texture = _texture("moon_normal.png")
	material.normal_scale = relief_strength
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_add_mesh(_surface, _model_mesh(MODELS[Kind.MOON]), material, radius)


func _build_mars() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_texture = _texture("mars_color.jpg")
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_add_mesh(_surface, _model_mesh(MODELS[Kind.MARS]), material, radius)
	# Mars' air is thin: a faint dusty haze, much weaker than the Earth's.
	_add_haze(Color(0.95, 0.6, 0.4), 0.22, 1.035)


func _texture(file: String) -> Texture2D:
	var path: String = TEXTURES + file
	if not ResourceLoader.exists(path):
		push_warning("CelestialBody: %s is missing; run tools/make_body_assets.sh" % path)
		return null
	return load(path)


func _sphere() -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 192
	sphere.rings = 96
	return sphere


## The mesh of a model file, whatever it was imported as: a Mesh (the OBJ) or a scene (the
## FBX, which also carries a light and a camera that are not wanted here).
func _model_mesh(path: String) -> Mesh:
	var resource: Resource = load(path) if ResourceLoader.exists(path) else null
	if resource is Mesh:
		return resource
	if resource is PackedScene:
		var scene: Node = (resource as PackedScene).instantiate()
		var meshes: Array[Node] = scene.find_children("*", "MeshInstance3D", true, false)
		var found: Mesh = (meshes[0] as MeshInstance3D).mesh if not meshes.is_empty() else null
		scene.free()
		if found != null:
			return found
	push_warning("CelestialBody: could not load %s; using a plain sphere" % path)
	return _sphere()


## Adds `mesh` under `parent`, centred and scaled so its radius is `target_radius`.
func _add_mesh(parent: Node3D, mesh: Mesh, material: Material, target_radius: float) -> MeshInstance3D:
	var bounds: AABB = mesh.get_aabb()
	var mesh_radius: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)) * 0.5
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.scale = Vector3.ONE * target_radius / mesh_radius
	instance.position = -bounds.get_center() * instance.scale
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _add_haze(color: Color, intensity: float, shell_radius: float) -> void:
	var haze := ShaderMaterial.new()
	haze.shader = load("res://atmosphere_glow.gdshader")
	haze.set_shader_parameter("glow_color", color)
	haze.set_shader_parameter("intensity", intensity)
	_sun_materials.append(haze)
	var holder := Node3D.new()
	holder.name = "Haze"
	add_child(holder)
	_add_mesh(holder, _sphere(), haze, radius * shell_radius)
