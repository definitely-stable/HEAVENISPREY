shader_type canvas_item;
render_mode unshaded;
// ADR-014 section 5: cast shadows are black and contact shadows are white in the same
// CanvasGroup buffer. The alpha channel is the union, and red marks contact coverage.
// Torchlight fills a moon shadow, but feet and prop bases still block light at contact.

const int MAX_LIGHTS = 16;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D paving_mask : repeat_disable, filter_nearest;
uniform vec2 paving_size = vec2(1.0);
uniform float shadow_alpha = 0.4;
uniform float softness_lod = 1.5;
// Lanterns: projected ground position, radius, and energy relative to a brazier.
uniform vec4 lanterns[MAX_LIGHTS];
uniform int lantern_count = 0;
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
		vec4 lantern = lanterns[index];
		vec2 offset = (canvas_point - lantern.xy) * vec2(1.0, 2.0);
		lit = max(lit, (1.0 - length(offset) / lantern.z) * lantern.w);
	}
	float fill = 1.0 - lantern_fill * clamp(lit, 0.0, 1.0);
	float coverage = max(mask.a * fill, mask.r * contact_strength);
	vec2 world = vec2(canvas_point.y + canvas_point.x * 0.5, canvas_point.y - canvas_point.x * 0.5) * sqrt(2.0);
	vec2 uv = world / paving_size;
	vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	coverage *= texture(paving_mask, uv).r * inside.x * inside.y;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(coverage, 0.0, 1.0) * shadow_alpha);
}
