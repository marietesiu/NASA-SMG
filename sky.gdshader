shader_type sky;
// Atmosphere gradient that gives way to the star texture as the rocket climbs.
uniform sampler2D stars : source_color, repeat_enable, filter_linear;
uniform float zoom = 4.0;            // >1 magnifies the star texture on screen
uniform float star_brightness = 3.0;
uniform float star_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 top_color : source_color = vec3(0.2, 0.42, 0.78);
uniform vec3 horizon_color : source_color = vec3(0.66, 0.78, 0.9);

void sky() {
	vec3 air = mix(horizon_color, top_color, clamp(abs(EYEDIR.y) * 2.0, 0.0, 1.0));
	vec3 space = texture(stars, SCREEN_UV / zoom + SKY_COORDS).rgb * star_brightness;
	COLOR = mix(air, space, star_amount);
}
