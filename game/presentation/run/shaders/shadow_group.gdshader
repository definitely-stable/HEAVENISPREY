shader_type canvas_item;
render_mode unshaded;
// ADR-014 section 5: every cast and contact shadow is drawn opaque into one CanvasGroup buffer;
// the group is composited once, softened by a mipmap level, at a single alpha. Overlapping
// shadows therefore do not get darker. A shadow is the absence of moonlight: inside the pool of
// a lantern or brazier (slice A3) the warm light fills it, so it fades by lantern_fill there.

const int MAX_LIGHTS = 16;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float shadow_alpha = 0.4;
uniform float softness_lod = 1.5;
// Lantern ground points in canvas (projected) px, their radius (world px = screen half width).
uniform vec2 lanterns[MAX_LIGHTS];
uniform int lantern_count = 0;
uniform float lantern_radius = 240.0;
uniform float lantern_fill = 0.75;

varying vec2 canvas_point;

void vertex() {
	canvas_point = VERTEX;
}

void fragment() {
	float coverage = textureLod(screen_texture, SCREEN_UV, softness_lod).a;
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
	COLOR = vec4(0.0, 0.0, 0.0, clamp(coverage, 0.0, 1.0) * shadow_alpha * fill);
}
