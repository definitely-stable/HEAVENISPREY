shader_type canvas_item;
// ADR-014 section 4 and A3 polish: the mist under the floating courtyard (REF-033, REF-056).
// Two screen-wide rects behind the ground share this shader: the sky (veil = false) is the
// dusk gradient; the veil rolls through the spires and thickens down in the gorge.

uniform bool veil = false;
uniform vec4 top_color : source_color = vec4(0.22, 0.23, 0.31, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.13, 0.15, 0.22, 1.0);
uniform vec4 mist_color : source_color = vec4(0.47, 0.52, 0.66, 1.0);
uniform vec2 camera_offset = vec2(0.0);
uniform float parallax = 0.35;
uniform float scale = 0.0036;
uniform float drift = 0.012;

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

float fbm(vec2 p) {
	float value = 0.0;
	float weight = 0.5;
	for (int octave = 0; octave < 4; octave++) {
		value += weight * noise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		weight *= 0.5;
	}
	return value;
}

void fragment() {
	if (!veil) {
		COLOR = vec4(mix(top_color.rgb, bottom_color.rgb, SCREEN_UV.y), 1.0);
	} else {
		vec2 world = (SCREEN_UV - vec2(0.5)) / SCREEN_PIXEL_SIZE + camera_offset * parallax;
		vec2 p = world * scale * vec2(0.73, 2.0);
		float t = TIME * drift;
		float banks = fbm(p + vec2(-t * 2.5, t * 0.35));
		float wisps = noise(p * 2.2 - vec2(t * 4.0, -t * 0.6));
		float mist = smoothstep(0.2, 0.79, banks * 0.86 + wisps * 0.19);
		float depth = smoothstep(0.19, 1.0, SCREEN_UV.y);
		COLOR = vec4(mist_color.rgb, 0.07 + depth * 0.12 + mist * 0.47);
	}
}
