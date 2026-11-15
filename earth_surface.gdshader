shader_type spatial;
// Earth's surface: day colour, glossy oceans, relief, and city lights that show only on the
// night side. Textures come from earth/ via tools/make_body_assets.sh.

uniform sampler2D day_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// White = land in the supplied mask.
uniform sampler2D land_mask_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D night_tex : source_color, hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// World-space direction pointing at the sun; set by CelestialBody.set_sun_direction().
uniform vec3 sun_direction = vec3(0.0, 0.0, 1.0);
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
// The supplied night-lights map is very dark, so the lights need a large boost.
uniform float night_energy = 6.0;
uniform vec3 night_tint : source_color = vec3(1.0, 0.8, 0.45);

void fragment() {
	ALBEDO = texture(day_tex, UV).rgb;
	float ocean = 1.0 - texture(land_mask_tex, UV).r;
	ROUGHNESS = mix(0.85, 0.42, ocean);
	SPECULAR = mix(0.25, 0.45, ocean);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;

	// NORMAL still holds the smooth sphere normal here (the normal map is applied after
	// fragment()), which is what decides day and night.
	vec3 sphere_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float night = 1.0 - smoothstep(-0.12, 0.12, dot(sphere_normal, normalize(sun_direction)));
	EMISSION = texture(night_tex, UV).r * night_tint * night_energy * night;
}
