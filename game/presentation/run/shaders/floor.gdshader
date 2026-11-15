shader_type canvas_item;
// ADR-014 A3 polish: the paving of the courtyard. The polygon carries the clean flagstones
// (TEXTURE and its normal map). This shader breaks their repetition three ways, all driven by
// the baked wear mask: patches of a second layer of the same flagstones (turned half a circle,
// with another period), patches of the worn variant (cracked, mossy, strewn with maple leaves:
// REF-033 and REF-001 floor tile sets) and a slow drift of tone. The three layers repeat with
// different periods, so no period of the arena shows one tile twice. Lit by the 2D lights
// like any ground item.

// The worn flagstones and their normal map, repeating every worn_repeat_px world px.
uniform sampler2D worn_albedo : repeat_enable, filter_linear_mipmap;
uniform sampler2D worn_normal : repeat_enable, filter_linear_mipmap;
uniform float worn_repeat_px = 480.0;
// Red: wear 0..1; green: tone drift around 0.5; blue: the second clean layer 0..1. Covers
// mask_size world px from mask_origin.
uniform sampler2D wear_mask : repeat_disable, filter_linear;
uniform vec2 mask_origin = vec2(0.0);
uniform vec2 mask_size = vec2(1.0);
// UV scale of the second clean layer (its period is 1 / alt_scale of the first) and its shift.
uniform float alt_scale = 0.8889;
uniform vec2 alt_shift = vec2(0.37, 0.61);
// The seams and cracks of a layer (darker than its mid luma) take over first, so a patch ends
// along the joints of the slabs instead of a soft blur.
uniform float clean_mid = 0.38;
uniform float worn_mid = 0.36;
uniform float edge_break = 0.55;
uniform float tone_range = 0.14;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

varying vec2 world;

void vertex() {
	world = VERTEX;
}

void fragment() {
	vec3 mask = texture(wear_mask, (world - mask_origin) / mask_size).rgb;
	// The second clean layer: the same texture turned half a circle (its normals turn with it).
	vec2 alt_uv = alt_shift - UV * alt_scale;
	vec3 alt = texture(TEXTURE, alt_uv).rgb;
	vec3 alt_normal = texture(NORMAL_TEXTURE, alt_uv).rgb;
	alt_normal.xy = 1.0 - alt_normal.xy;
	float layer = smoothstep(0.46, 0.54, mask.b + (clean_mid - dot(alt, LUMA)) * edge_break);
	// COLOR arrives as the clean texture (texture x modulate).
	vec3 albedo = mix(COLOR.rgb, alt, layer);
	vec3 normal = mix(texture(NORMAL_TEXTURE, UV).rgb, alt_normal, layer);
	vec2 worn_uv = world / worn_repeat_px;
	vec3 worn = texture(worn_albedo, worn_uv).rgb;
	float wear = smoothstep(0.46, 0.54, mask.r + (worn_mid - dot(worn, LUMA)) * edge_break);
	albedo = mix(albedo, worn, wear) * (1.0 + (mask.g - 0.5) * tone_range);
	COLOR = vec4(albedo, COLOR.a);
	NORMAL_MAP = mix(normal, texture(worn_normal, worn_uv).rgb, wear);
}
