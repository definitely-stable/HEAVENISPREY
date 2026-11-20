shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D surface_mask : repeat_disable, filter_nearest;
uniform vec4 surface_bounds;

varying vec2 canvas_point;
varying float pixels_per_world_px;

void vertex() {
	canvas_point = VERTEX;
	pixels_per_world_px = length(CANVAS_MATRIX[1].xy);
}

void fragment() {
	vec2 uv = (canvas_point - surface_bounds.xy) / surface_bounds.zw;
	vec2 floor_pixel = texture(surface_mask, uv).rg;
	vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	float lift = floor_pixel.r * 127.5 - 64.0;
	vec2 source = SCREEN_UV + vec2(0.0, lift * pixels_per_world_px * SCREEN_PIXEL_SIZE.y);
	vec4 mark = textureLod(screen_texture, source, 0.0);
	mark.rgb /= max(mark.a, 0.0001);
	// Keep the outline continuous while the darker vertical breaks read as stone.
	mark.rgb *= mix(0.62, 1.0, step(0.75, floor_pixel.g));
	mark.a *= step(0.25, floor_pixel.g) * inside.x * inside.y;
	COLOR *= mark;
}
