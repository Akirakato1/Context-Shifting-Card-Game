shader_type canvas_item;

void fragment() {
	// Fragment COLOR already includes the texture's alpha and the canvas opacity.
	COLOR = vec4(vec3(1.0), COLOR.a);
}
