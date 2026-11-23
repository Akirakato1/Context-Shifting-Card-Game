shader_type canvas_item;

varying vec4 card_tint;

void vertex() {
	card_tint = COLOR;
}

void fragment() {
	vec4 art = texture(TEXTURE, UV);
	// Sample across the original painted silhouette, including its diagonal divide.
	float rim = 0.0;
	for (int layer = 0; layer < 2; layer++) {
		vec2 radius = layer == 0 ? vec2(0.028, 0.019) : vec2(0.009, 0.006);
		vec2 x = vec2(radius.x, 0.0);
		vec2 y = vec2(0.0, radius.y);
		float horizontal = min(texture(TEXTURE, UV + x).a, texture(TEXTURE, UV - x).a);
		float vertical = min(texture(TEXTURE, UV + y).a, texture(TEXTURE, UV - y).a);
		rim += (1.0 - min(horizontal, vertical)) * (layer == 0 ? 0.30 : 0.70);
	}
	vec3 violet = vec3(0.72, 0.48, 1.0);
	vec3 pearl = vec3(0.56, 0.96, 1.0);
	vec3 sheen = mix(violet, pearl, smoothstep(0.18, 0.83, UV.x));
	COLOR = vec4(mix(art.rgb, sheen, rim), art.a) * card_tint;
}
