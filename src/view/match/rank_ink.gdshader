shader_type canvas_item;

uniform bool use_tint = false;
uniform bool dark_outline = false;
varying vec4 ink_tint;

void vertex() {
	ink_tint = COLOR;
}

void fragment() {
	// Fragment COLOR already includes the texture's alpha and the canvas opacity.
	vec3 ink = use_tint ? ink_tint.rgb : vec3(1.0);
	if (dark_outline) {
		float glyph = texture(TEXTURE, UV).a;
		vec2 x = vec2(0.055, 0.0);
		vec2 y = vec2(0.0, 0.042);
		float horizontal = max(texture(TEXTURE, UV + x).a, texture(TEXTURE, UV - x).a);
		float vertical = max(texture(TEXTURE, UV + y).a, texture(TEXTURE, UV - y).a);
		float alpha = max(glyph, 0.85 * max(horizontal, vertical));
		COLOR = vec4(mix(vec3(0.10, 0.09, 0.16), ink, glyph), alpha * ink_tint.a);
	} else {
		COLOR = vec4(ink, COLOR.a);
	}
}
