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
	vec2 world = (SCREEN_UV - vec2(0.5)) / SCREEN_PIXEL_SIZE + camera_offset * parallax;
	if (!veil) {
		float sky_depth = smoothstep(0.0, 1.0, SCREEN_UV.y);
		vec2 opening = (world - vec2(455.0, -88.0)) / vec2(850.0, 440.0);
		float twilight = exp(-dot(opening, opening) * 1.7) * (1.0 - sky_depth);
		vec3 sky = mix(top_color.rgb, bottom_color.rgb, sky_depth);
		COLOR = vec4(sky + vec3(0.090, 0.042, 0.032) * twilight, 1.0);
	} else {
		vec2 p = world * scale * vec2(0.48, 2.25);
		float t = TIME * drift;
		float banks = fbm(p + vec2(-t * 2.5, t * 0.35));
		float wisps = noise(p * vec2(1.8, 2.7) - vec2(t * 4.0, -t * 0.6));
		float mist = smoothstep(0.25, 0.78, banks * 0.81 + wisps * 0.22);
		float depth = smoothstep(0.19, 1.0, SCREEN_UV.y);
		vec3 haze = mix(mist_color.rgb, mist_color.rgb * vec3(0.86, 0.94, 1.0), depth);
		COLOR = vec4(haze, 0.045 + depth * 0.13 + mist * (0.31 + depth * 0.16));
	}
}
