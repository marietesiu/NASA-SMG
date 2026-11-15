shader_type spatial;
// Cloud layer: a slightly larger sphere around the Earth. White in the map = cloud. It is lit
// like the planet, so clouds go dark on the night side.

uniform sampler2D clouds_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float density : hint_range(0.0, 1.0) = 0.9;

void fragment() {
	ALBEDO = vec3(1.0);
	ALPHA = clamp(texture(clouds_tex, UV).r * density, 0.0, 1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
