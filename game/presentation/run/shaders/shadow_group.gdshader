shader_type canvas_item;
render_mode unshaded;
// ADR-014 section 5: cast shadows are black and contact shadows are white in the same
// CanvasGroup buffer. The alpha channel is the union, and red marks contact coverage.
// Torchlight fills a moon shadow, but feet and prop bases still block light at contact.

const int MAX_LIGHTS = 16;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float shadow_alpha = 0.4;
uniform float softness_lod = 1.5;
// Lantern ground points in canvas (projected) px, their radius (world px = screen half width).
uniform vec2 lanterns[MAX_LIGHTS];
uniform int lantern_count = 0;
uniform float lantern_radius = 240.0;
uniform float lantern_fill = 0.75;
uniform float contact_strength = 0.75;

varying vec2 canvas_point;

void vertex() {
	canvas_point = VERTEX;
}

void fragment() {
	vec4 mask = textureLod(screen_texture, SCREEN_UV, softness_lod);
	float lit = 0.0;
	for (int index = 0; index < MAX_LIGHTS; index++) {
		if (index >= lantern_count) {
			break;
		}
		// A world circle is a 2:1 ellipse on screen.
		vec2 offset = (canvas_point - lanterns[index]) * vec2(1.0, 2.0);
		lit = max(lit, 1.0 - length(offset) / lantern_radius);
	}
	float fill = 1.0 - lantern_fill * clamp(lit, 0.0, 1.0);
	float coverage = max(mask.a * fill, mask.r * contact_strength);
	COLOR = vec4(0.0, 0.0, 0.0, clamp(coverage, 0.0, 1.0) * shadow_alpha);
}
