shader_type canvas_item;
render_mode unshaded;

varying vec3 ink;

void vertex() {
	ink = COLOR.rgb;
}

void fragment() {
	float opacity = texture(TEXTURE, UV).a;
	vec2 width = 1.6 * max(fwidth(UV), TEXTURE_PIXEL_SIZE);
	float adjacent = min(
		min(texture(TEXTURE, UV + vec2(width.x, 0.0)).a, texture(TEXTURE, UV - vec2(width.x, 0.0)).a),
		min(texture(TEXTURE, UV + vec2(0.0, width.y)).a, texture(TEXTURE, UV - vec2(0.0, width.y)).a)
	);
	float edge = smoothstep(0.05, 0.70, opacity - adjacent);
	COLOR = vec4(ink, opacity * mix(0.15, 0.86, edge));
}
