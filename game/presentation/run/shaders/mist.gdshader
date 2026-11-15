shader_type canvas_item;
// ADR-014 section 4 and A3 polish: the mist under the floating courtyard (REF-033, REF-056).
// Two screen-wide rects behind the ground share this shader: the sky (veil = false) is the
// dusk gradient, opaque; the veil (veil = true) is two layers of drifting value noise over
// the distant spires drawn between them, thicker towards the bottom of the screen where the
// abyss is. The camera offset gives the mist a slow parallax. Presentation only.

uniform bool veil = false;
uniform vec4 top_color : source_color = vec4(0.17, 0.13, 0.21, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.08, 0.06, 0.11, 1.0);
uniform vec4 mist_color : source_color = vec4(0.52, 0.45, 0.62, 1.0);
uniform float mist_amount = 0.46;
// Extra mist at the bottom of the screen (0 = even).
uniform float depth_gain = 0.35;
uniform vec2 camera_offset = vec2(0.0);
uniform float parallax = 0.35;
uniform float scale = 0.0032;
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
	for (int octave = 0; octave < 5; octave++) {
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
		vec2 world = FRAGCOORD.xy + camera_offset * parallax;
		vec2 p = world * scale * vec2(1.0, 2.0);
		float t = TIME * drift;
		float low = fbm(p + vec2(t * 3.0, t));
		float high = fbm(p * 2.2 - vec2(t * 5.0, -t * 2.0));
		float mist = smoothstep(0.35, 0.85, low * 0.65 + high * 0.45);
		float depth = 1.0 + depth_gain * (SCREEN_UV.y - 0.5);
		COLOR = vec4(mist_color.rgb, clamp(mist * mist_amount * depth, 0.0, 1.0));
	}
}
