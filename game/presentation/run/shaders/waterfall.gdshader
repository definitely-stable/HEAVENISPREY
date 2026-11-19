shader_type canvas_item;
render_mode unshaded;
// REF-029 and REF-064. UV.y follows the fall from the stone lip into the gorge.
uniform vec4 water_color : source_color = vec4(0.38, 0.46, 0.57, 1.0);
uniform vec4 foam_color : source_color = vec4(0.73, 0.79, 0.84, 1.0);
uniform vec4 mist_color : source_color = vec4(0.51, 0.57, 0.68, 1.0);
uniform float spread = 1.0;
uniform float split = 0.5;
uniform float drift = 0.1;
uniform float speed = 1.0;
uniform float phase = 0.0;

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
	float down = UV.y;
	float t = TIME * speed + phase;
	// Equal phase intervals spread out as the water accelerates down the face.
	float flow = sqrt(down + 0.045) * 11.0 - t * 5.0;
	float across = UV.x * 2.0 - 1.0 - drift * down * down;
	float loosens = smoothstep(0.13, 0.69, down);
	float fray = (noise(vec2(across * 7.0 + phase, flow * 0.54)) - 0.5) * loosens * 0.18;
	float half_width = spread * mix(0.25, 0.39, loosens) + fray;
	float main = 1.0 - smoothstep(half_width * 0.45, half_width, abs(across));
	float separation = smoothstep(0.09, 0.29, down) * split;
	float gap = 1.0 - smoothstep(0.009, 0.095, abs(across + 0.04 - fray * 0.3));
	main *= 1.0 - gap * separation * 0.8;
	float side_threads = 1.0 - smoothstep(0.010, 0.056, abs(across + spread * 0.37 + fray));
	float ridges = noise(vec2(across * 21.0 + phase, flow));
	float fine = noise(vec2(across * 49.0 - phase, flow * 1.45 + t * 0.62));
	float ribbons = smoothstep(0.29, 0.84, ridges * 0.65 + fine * 0.35);
	float lip = 1.0 - smoothstep(0.0, 0.065, down);
	float lower_fall = 1.0 - smoothstep(0.58, 0.91, down);
	float stream = (main + side_threads * separation * 0.29) * lower_fall;
	stream = min(1.0, stream * smoothstep(0.0, 0.012, down) * (0.37 + ribbons * 0.49 + lip * 0.27));

	// Eddies drift across the foot, at lower contrast than the lit strands.
	vec2 foot = vec2((across - drift * 0.45) * 1.18, (down - 0.82) * 4.2);
	float cloud = 1.0 - smoothstep(0.15, 0.94, length(foot));
	float eddies = noise(vec2(across * 4.6 - t * 0.38, down * 16.0 + t * 0.54));
	float foot_fade = 1.0 - smoothstep(0.87, 1.0, down);
	float mist = cloud * foot_fade * mix(0.10, 0.41, eddies);
	float droplets = noise(vec2(across * 43.0, flow * 2.1 + phase));
	float scatter = smoothstep(0.77, 0.94, droplets) * cloud * foot_fade * 0.16;

	float foam = clamp(ribbons * 0.71 + lip * 0.68 + scatter, 0.0, 1.0);
	float alpha = stream + (mist + scatter) * (1.0 - stream);
	vec3 water = mix(water_color.rgb, foam_color.rgb, foam);
	COLOR = vec4(mix(mist_color.rgb, water, stream / max(alpha, 0.001)), alpha);
}
