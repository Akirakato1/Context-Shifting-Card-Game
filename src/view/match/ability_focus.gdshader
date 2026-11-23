shader_type canvas_item;
render_mode unshaded;

uniform vec4 focus_regions[6];
uniform int region_count;

void fragment() {
	vec2 feather = SCREEN_PIXEL_SIZE * 8.0;
	float lit = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i < region_count) {
			vec4 rect = focus_regions[i];
			vec2 margin = min(UV - rect.xy, rect.zw - UV);
			vec2 inside = smoothstep(-feather, vec2(0.0), margin);
			lit = max(lit, inside.x * inside.y);
		}
	}
	COLOR = vec4(0.012, 0.018, 0.028, 0.20 * (1.0 - lit));
}
