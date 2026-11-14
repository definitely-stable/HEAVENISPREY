shader_type canvas_item;
render_mode unshaded;
// ADR-014 section 5: every cast and contact shadow is drawn opaque into one CanvasGroup buffer;
// the group is composited once, softened by a mipmap level, at a single alpha. Overlapping
// shadows therefore do not get darker.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float shadow_alpha = 0.4;
uniform float softness_lod = 1.5;

void fragment() {
	float coverage = textureLod(screen_texture, SCREEN_UV, softness_lod).a;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(coverage, 0.0, 1.0) * shadow_alpha);
}
