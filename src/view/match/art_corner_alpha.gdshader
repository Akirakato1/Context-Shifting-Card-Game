shader_type canvas_item;

void fragment() {
	// The painted surfaces were exported against a pale matte around their bevels.
	vec3 source = texture(TEXTURE, UV).rgb;
	float matte = smoothstep(0.78, 0.89, min(source.r, min(source.g, source.b)));
	COLOR.a *= 1.0 - matte;
}
