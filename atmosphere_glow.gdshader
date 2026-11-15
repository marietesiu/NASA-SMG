shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
// Thin haze at the edge of a planet: a slightly larger sphere that is only visible near its
// silhouette, and only on the sunlit side.

// World-space direction pointing at the sun; set by CelestialBody.set_sun_direction().
uniform vec3 sun_direction = vec3(0.0, 0.0, 1.0);
uniform vec3 glow_color : source_color = vec3(0.35, 0.6, 1.0);
uniform float intensity = 1.4;
uniform float rim_power = 3.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	vec3 sphere_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float sunlit = smoothstep(-0.25, 0.35, dot(sphere_normal, normalize(sun_direction)));
	ALBEDO = glow_color * intensity;
	ALPHA = clamp(rim * sunlit, 0.0, 1.0);
}
