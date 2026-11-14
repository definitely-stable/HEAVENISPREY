shader_type canvas_item;
render_mode unshaded;
// ADR-014 section 2: upright sprites are lit by modulate (RunLighting.light_at) and get a thin
// rim on the side that faces the moon, read from the silhouette "pillow" normal map. Draws
// without a normal map (primitives) see a flat normal and get no rim.

// Screen direction towards the moon (opposite to where its light travels), y down.
uniform vec2 to_moon = vec2(-0.877, -0.48);
uniform vec3 rim_color : source_color = vec3(0.6, 0.68, 0.72);
uniform float rim_strength = 0.5;

void fragment() {
	vec4 albedo = texture(TEXTURE, UV);
	vec3 n = texture(NORMAL_TEXTURE, UV).rgb * 2.0 - 1.0;
	// Normal maps are y-up; the screen is y-down.
	vec2 side = vec2(n.x, -n.y);
	float edge = smoothstep(0.12, 0.55, 1.0 - n.z);
	// No normal map (primitives) reads as a flat or invalid normal: no rim.
	bool shaped = n.z > 0.05 && length(side) > 0.0001;
	float facing = shaped ? max(dot(normalize(side), to_moon), 0.0) : 0.0;
	float rim = edge * facing * rim_strength;
	vec3 lit = albedo.rgb * COLOR.rgb;
	COLOR = vec4(mix(lit, rim_color, rim), albedo.a * COLOR.a);
}
