shader_type canvas_item;

uniform vec4 atlas_region;
uniform bool sideways = false;

void fragment() {
	vec2 local_uv = (UV - atlas_region.xy) / atlas_region.zw;
	float travel = sideways ? local_uv.x : local_uv.y;
	float edge = sideways ? local_uv.y : local_uv.x;
	// The outer stones turn into the same paving at both ends of the flight.
	float approach = smoothstep(0.0, 0.09, travel) * smoothstep(0.0, 0.09, 1.0 - travel);
	float side = smoothstep(0.0, 0.02, edge) * smoothstep(0.0, 0.025, 1.0 - edge);
	COLOR.a *= approach * side;
}
