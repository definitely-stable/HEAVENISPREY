shader_type canvas_item;
render_mode unshaded;
// ADR-014 section 20: the tone of the whole world frame after REF-023, applied once over the
// scene and under the HUD (FrameGrade). An S-curve on each channel opens the range (the floor
// sinks, lantern pools and gold light climb) and a vignette darkens the corners. Mirrors
// FrameGrade.apply().

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float curve = 0.6;
uniform float pivot = 0.5;
uniform float vignette = 0.42;
uniform float vignette_inner = 0.38;
uniform float vignette_outer = 0.95;
uniform float aspect = 1.7778;
uniform float highlight_low = 0.55;
uniform float highlight_high = 0.85;

vec3 s_curve(vec3 c) {
	vec3 low = pivot * pow(clamp(c / pivot, 0.0, 1.0), vec3(2.0));
	vec3 high = 1.0 - (1.0 - pivot) * pow(clamp((1.0 - c) / (1.0 - pivot), 0.0, 1.0), vec3(2.0));
	vec3 shaped = mix(low, high, step(vec3(pivot), c));
	return mix(c, shaped, curve);
}

void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;
	c = s_curve(c);
	vec2 d = (SCREEN_UV - 0.5) * vec2(aspect, 1.0);
	float edge = smoothstep(vignette_inner, vignette_outer, length(d) / (0.5 * length(vec2(aspect, 1.0))));
	// Lights keep their heat in the corners: the vignette darkens the stone, not the flames.
	float bright = smoothstep(highlight_low, highlight_high, dot(c, vec3(0.2126, 0.7152, 0.0722)));
	COLOR = vec4(c * (1.0 - vignette * edge * (1.0 - bright)), 1.0);
}
