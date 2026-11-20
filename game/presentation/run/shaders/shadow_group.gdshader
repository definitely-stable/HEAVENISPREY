shader_type canvas_item;
render_mode unshaded;
// ADR-014 section 5: green stores the cast silhouette on the zero-height plane.
// Red stores contact coverage at the visible surface. Both share a CanvasGroup buffer.

const int MAX_LIGHTS = 16;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D paving_mask : repeat_disable, filter_nearest;
uniform vec2 paving_size = vec2(1.0);
uniform vec4 surface_bounds = vec4(0.0);
uniform vec2 surface_shift = vec2(0.0);
uniform float shadow_alpha = 0.4;
uniform float penumbra_px = 1.5;
// Lanterns: projected ground position, radius, and energy relative to a brazier.
uniform vec4 lanterns[MAX_LIGHTS];
uniform int lantern_count = 0;
uniform float lantern_fill = 0.75;
uniform float contact_strength = 0.75;

varying vec2 canvas_point;
varying vec2 pixels_per_level;
varying float pixels_per_world_px;

void vertex() {
	canvas_point = VERTEX;
	pixels_per_level = (CANVAS_MATRIX * vec4(surface_shift, 0.0, 0.0)).xy;
	pixels_per_world_px = length(CANVAS_MATRIX[1].xy);
}

void fragment() {
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
	vec2 uv;
	float surface;
	float elevation = 0.0;
	if (surface_bounds.z > 0.0) {
		uv = (canvas_point - surface_bounds.xy) / surface_bounds.zw;
		vec2 paving = texture(paving_mask, uv).rg;
		surface = step(0.25, paving.g);
		elevation = paving.r * 127.5 - 64.0;
	} else {
		vec2 world = vec2(canvas_point.y + canvas_point.x * 0.5, canvas_point.y - canvas_point.x * 0.5) * sqrt(2.0);
		uv = world / paving_size;
		surface = texture(paving_mask, uv).r;
	}
	vec2 sample_uv = SCREEN_UV + elevation * pixels_per_level * SCREEN_PIXEL_SIZE;
	// Bilinear taps soften the cast edge in Compatibility as well as Forward+.
	vec2 spread = SCREEN_PIXEL_SIZE * penumbra_px * pixels_per_world_px;
	vec2 x = vec2(spread.x, 0.0);
	vec2 y = vec2(0.0, spread.y);
	float cast = 0.56 * textureLod(screen_texture, sample_uv, 0.0).g + 0.11 * (
		textureLod(screen_texture, sample_uv - x, 0.0).g + textureLod(screen_texture, sample_uv + x, 0.0).g +
		textureLod(screen_texture, sample_uv - y, 0.0).g + textureLod(screen_texture, sample_uv + y, 0.0).g);
	float contact = textureLod(screen_texture, SCREEN_UV, 0.0).r;
	float coverage = max(cast * fill, contact * max(fill, contact_strength));
	vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	coverage *= surface * inside.x * inside.y;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(coverage, 0.0, 1.0) * shadow_alpha);
}
