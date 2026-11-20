shader_type canvas_item;
render_mode unshaded;
// ADR-014 section 2: upright sprites are lit by modulate (RunLighting.light_at) and get a thin
// rim on the side that faces the moon, read from the silhouette "pillow" normal map. Near a
// lantern or brazier the side that faces its flame catches a warm rim as well, flickering with
// the fire (section 26). Draws without a normal map (primitives) see a flat normal and get no
// rim.

const int MAX_FLAMES = 16;

// Screen direction towards the moon (opposite to where its light travels), y down.
uniform vec2 to_moon = vec2(-0.877, -0.48);
uniform vec3 rim_color : source_color = vec3(0.6, 0.68, 0.72);
uniform float rim_strength = 0.5;
// Flames: screen position of the fire, reach in px, and energy relative to a brazier.
uniform vec4 flames[MAX_FLAMES];
uniform float flame_energy[MAX_FLAMES];
uniform int flame_count = 0;
uniform vec3 warm_color : source_color = vec3(1.0, 0.68, 0.3);
uniform float warm_strength = 0.0;

varying vec2 canvas_point;

void vertex() {
	canvas_point = VERTEX;
}

void fragment() {
	vec3 n = texture(NORMAL_TEXTURE, UV).rgb * 2.0 - 1.0;
	// Normal maps are y-up; the screen is y-down. A mirrored sprite (a negative region width)
	// samples the map right to left: its normals point the other way across.
	float across = dFdx(UV.x) < 0.0 ? -1.0 : 1.0;
	vec2 side = vec2(n.x * across, -n.y);
	float edge = smoothstep(0.12, 0.55, 1.0 - n.z);
	// No normal map (primitives) reads as a flat or invalid normal: no rim.
	bool shaped = n.z > 0.05 && length(side) > 0.0001;
	vec2 dir = shaped ? normalize(side) : vec2(0.0);
	float rim = edge * max(dot(dir, to_moon), 0.0) * rim_strength;
	float warm = 0.0;
	if (shaped && warm_strength > 0.0) {
		for (int i = 0; i < min(flame_count, MAX_FLAMES); i++) {
			vec2 to_flame = flames[i].xy - canvas_point;
			float reach = 1.0 - length(to_flame) / flames[i].z;
			if (reach > 0.0) {
				warm += max(dot(dir, normalize(to_flame)), 0.0) * reach * reach * flame_energy[i] * flames[i].w;
			}
		}
	}
	warm = min(warm, 1.0) * edge * warm_strength;
	// COLOR arrives as texture x modulate (the light of RunLighting.light_at): the painted
	// colours are kept as they are, only the rims are mixed in.
	COLOR = vec4(mix(COLOR.rgb, rim_color, rim) + warm_color * warm, COLOR.a);
}
