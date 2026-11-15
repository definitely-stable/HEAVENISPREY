shader_type canvas_item;
render_mode unshaded;
// ADR-014 A3 polish: a waterfall pouring from under the edge of the courtyard into the mist
// (REF-033, REF-029, REF-056). A rect on the cliff face: UV.x runs across the stream, UV.y
// down it. Thin strands of value noise slide down a narrow stream that frays as it falls and
// ends in a soft cloud of spray. Unlit: water catches the sky, not the lanterns.
// Presentation only.

uniform vec4 water_color : source_color = vec4(0.52, 0.58, 0.82, 1.0);
uniform vec4 foam_color : source_color = vec4(0.9, 0.92, 0.98, 1.0);
uniform float speed = 1.5;
uniform float opacity = 0.9;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float across = UV.x * 2.0 - 1.0;
	float down = UV.y;
	float fall = TIME * speed;
	// The stream: half of the rect wide, its edges frayed by noise that falls with it.
	float fray = (noise(vec2(UV.x * 5.0, down * 6.0 - fall * 1.3)) - 0.5) * 0.18;
	float half_width = mix(0.36, 0.56, smoothstep(0.0, 0.6, down)) + fray;
	float stream = 1.0 - smoothstep(half_width * 0.55, half_width, abs(across));
	// Thin bright strands with darker gaps between them, a finer layer falling faster.
	float strands = noise(vec2(UV.x * 26.0, down * 1.6 - fall));
	strands = mix(strands, noise(vec2(UV.x * 58.0, down * 3.4 - fall * 1.8)), 0.4);
	strands = smoothstep(0.25, 0.8, strands);
	float lip = 1.0 - smoothstep(0.0, 0.06, down);
	float falling = stream * (0.42 + 0.58 * strands) * smoothstep(0.0, 0.015, down) * (1.0 - smoothstep(0.62, 0.86, down));
	// Spray: a wide soft cloud around the foot of the fall, breathing slowly.
	vec2 foot = vec2(across, (down - 0.8) * 5.0);
	float spray = (1.0 - smoothstep(0.25, 1.0, length(foot))) * (0.55 + 0.45 * noise(vec2(UV.x * 4.0 - fall * 0.2, down * 9.0 - fall * 0.5)));
	float foam = clamp(strands * strands * 0.8 + lip + spray, 0.0, 1.0);
	float alpha = clamp(falling + spray * 0.55, 0.0, 1.0) * opacity;
	COLOR = vec4(mix(water_color.rgb, foam_color.rgb, foam), alpha);
}
