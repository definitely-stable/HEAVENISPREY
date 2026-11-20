shader_type canvas_item;
// ADR-014 A3 polish: the paving of the courtyard. The polygon carries the clean flagstones
// (TEXTURE and its normal map). This shader breaks their repetition three ways, all driven by
// the baked wear mask: patches of a second layer of the same flagstones (turned half a circle,
// with another period), patches of the worn variant (cracked, mossy, strewn with maple leaves:
// REF-033 and REF-001 floor tile sets) and a slow drift of tone. The three layers repeat with
// different periods, so no period of the arena shows one tile twice. Lit by the 2D lights
// like any ground item, plus the sheen of damp stone (ADR-014 section 26): light() adds a
// specular lobe seen from the camera's tilt, so a lantern glints on the slabs between it and
// the viewer, as on the paving of REF-033, and the moon picks out the edges of the slabs.

// The worn flagstones and their normal map, repeating every worn_repeat_px world px.
uniform sampler2D worn_albedo : repeat_enable, filter_linear_mipmap;
uniform sampler2D worn_normal : repeat_enable, filter_linear_mipmap;
uniform float worn_repeat_px = 480.0;
// When the floor vertices are lifted, the original world position is carried in UV.
uniform float uv_world_px = 0.0;
// Red: wear 0..1; green: tone drift around 0.5; blue: the second clean layer 0..1. Covers
// mask_size world px from mask_origin.
uniform sampler2D wear_mask : repeat_disable, filter_linear;
uniform sampler2D terrace_mask : repeat_disable, filter_linear;
uniform sampler2D retaining_atlas : repeat_disable, filter_linear;
uniform vec4 retaining_region = vec4(0.0);
uniform bool has_terraces = false;
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
// Sheen: specular of the clean slab tops, what the damp patches (mask alpha) add, the share
// left on the worn layer (moss and leaves are matte) and on the seams (darker than seam_luma).
uniform float gloss_slab = 0.08;
uniform float gloss_damp = 0.38;
uniform float gloss_worn = 0.3;
uniform float seam_luma = 0.3;
// Damp stone is darker and its cracks fill with water (flatter normals).
uniform float damp_darken = 0.18;
uniform float damp_flatten = 0.5;
// Specular exponent, the screen direction towards the viewer (the camera looks down at the
// floor from the bottom of the screen) and the share of the moon's specular.
uniform float shininess = 28.0;
uniform vec2 view_tilt = vec2(-1.0, 1.0);
uniform float moon_sheen = 0.45;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

varying vec2 world;
varying float face_shade;
varying float tread_edge;
varying float retaining_course;
// Specular of this pixel, from fragment() to light().
varying float gloss;

void vertex() {
	world = uv_world_px > 0.0 ? UV * uv_world_px : VERTEX;
	face_shade = uv_world_px > 0.0 ? COLOR.r : 1.0;
	tread_edge = uv_world_px > 0.0 ? COLOR.g : 0.0;
	retaining_course = uv_world_px > 0.0 ? COLOR.b : 0.0;
}

void fragment() {
	vec2 arena_uv = (world - mask_origin) / mask_size;
	vec4 mask = texture(wear_mask, arena_uv);
	vec2 terrace = has_terraces ? texture(terrace_mask, arena_uv).rg : vec2(0.0);
	// The second clean layer: the same texture turned half a circle (its normals turn with it).
	vec2 alt_uv = alt_shift - UV * alt_scale;
	vec3 alt = texture(TEXTURE, alt_uv).rgb;
	vec3 alt_normal = texture(NORMAL_TEXTURE, alt_uv).rgb;
	alt_normal.xy = 1.0 - alt_normal.xy;
	float layer = smoothstep(0.46, 0.54, mask.b + (clean_mid - dot(alt, LUMA)) * edge_break);
	// COLOR arrives as the clean texture (texture x modulate).
	vec3 base = uv_world_px > 0.0 ? texture(TEXTURE, UV).rgb : COLOR.rgb;
	vec3 albedo = mix(base, alt, layer);
	vec3 normal = mix(texture(NORMAL_TEXTURE, UV).rgb, alt_normal, layer);
	vec2 worn_uv = world / worn_repeat_px;
	vec3 worn = texture(worn_albedo, worn_uv).rgb;
	float wear = smoothstep(0.46, 0.54, mask.r + (worn_mid - dot(worn, LUMA)) * edge_break - terrace.g * 0.13);
	albedo = mix(albedo, worn, wear) * (1.0 + (mask.g - 0.5) * tone_range);
	// The thresholds use the same slabs as the landing, with less wear across the passage.
	float dressing = clamp(terrace.r + terrace.g * 0.67, 0.0, 1.0);
	albedo *= mix(vec3(1.0), vec3(1.20, 1.10, 1.01), dressing);
	float nosing = smoothstep(0.85, 0.98, tread_edge);
	albedo += nosing * vec3(0.075, 0.060, 0.049);
	float damp = mask.a * mix(1.0, 0.64, dressing);
	float tone = face_shade;
	if (retaining_course > 0.0 && retaining_region.z > 0.0) {
		float along = fract((world.x - world.y) * 0.70710678 / 92.0 + 0.26);
		float down = (1.0 - retaining_course) / 0.75;
		albedo = texture(retaining_atlas, retaining_region.xy + vec2(along, down) * retaining_region.zw).rgb;
		tone = 0.81;
		normal = vec3(0.5, 0.52, 1.0);
		wear = 0.0;
		damp = 0.0;
	}
	float seam = smoothstep(seam_luma - 0.08, seam_luma + 0.06, dot(albedo, LUMA));
	gloss = (gloss_slab + gloss_damp * damp) * mix(1.0, gloss_worn, wear) * mix(0.25, 1.0, seam) * face_shade;
	COLOR = vec4(albedo * (1.0 - damp_darken * damp) * tone, COLOR.a);
	normal = mix(normal, texture(worn_normal, worn_uv).rgb, wear);
	NORMAL_MAP = mix(normal, vec3(0.5, 0.5, 1.0), damp_flatten * damp);
}

void light() {
	// The default diffuse term of a 2D light, then the sheen.
	float n_dot_l = max(dot(NORMAL, LIGHT_DIRECTION), 0.0);
	vec3 light = LIGHT_COLOR.rgb * LIGHT_ENERGY;
	vec3 half_vector = normalize(LIGHT_DIRECTION + normalize(vec3(view_tilt, 1.0)));
	float sheen = pow(max(dot(NORMAL, half_vector), 0.0), shininess) * gloss;
	sheen *= LIGHT_IS_DIRECTIONAL ? moon_sheen : 1.0;
	LIGHT = vec4(light * (COLOR.rgb * n_dot_l + sheen), LIGHT_COLOR.a);
}
