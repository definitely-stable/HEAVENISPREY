shader_type canvas_item;
render_mode unshaded;
// ADR-014 A5b: a fallen enemy decays (REF-010 "decay"). The modulate carries the light of the
// body in rgb and what is left of it in alpha (1 whole, 0 gone). As it decays the body darkens to
// ink and an ink noise eats it with a thin crimson edge; nothing of it stays translucent.

uniform sampler2D noise : filter_linear, repeat_enable;
// Atlas texels per noise tile: the pattern is fixed on the body, not on the screen.
uniform float noise_texels = 128.0;
uniform vec3 ember : source_color = vec3(0.95, 0.16, 0.2);
uniform vec3 ink : source_color = vec3(0.05, 0.02, 0.05);
// Width of the burning edge in noise units.
uniform float edge = 0.08;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 painted = texture(TEXTURE, UV);
	float decay = clamp(1.0 - tint.a, 0.0, 1.0);
	vec2 texel = UV / TEXTURE_PIXEL_SIZE;
	float n = texture(noise, texel / noise_texels).r * 0.7 + texture(noise, texel / (noise_texels * 0.35)).r * 0.3;
	// From a little below 0 (nothing eaten) to a little above 1 (all of it).
	float cut = decay * (1.0 + edge * 2.0) - edge;
	if (n < cut) {
		discard;
	}
	vec3 body = mix(painted.rgb * tint.rgb, ink, clamp(decay * 1.6, 0.0, 0.75));
	float burning = (1.0 - smoothstep(cut, cut + edge, n)) * step(0.001, decay);
	COLOR = vec4(mix(body, ember, burning), painted.a);
}
