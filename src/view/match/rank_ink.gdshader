shader_type canvas_item;

uniform bool use_tint = false;
varying vec3 ink_tint;

void vertex() {
	ink_tint = COLOR.rgb;
}

void fragment() {
	// Fragment COLOR already includes the texture's alpha and the canvas opacity.
	COLOR = vec4(use_tint ? ink_tint : vec3(1.0), COLOR.a);
}
