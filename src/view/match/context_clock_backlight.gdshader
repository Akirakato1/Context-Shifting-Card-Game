shader_type canvas_item;

uniform vec3 backlight = vec3(0.0);
varying vec4 dial_modulate;

void vertex() {
	dial_modulate = COLOR;
}

void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	// The three letterforms share a registered atlas. Light only the requested name.
	int sector = UV.y < 0.44 ? 0 : (UV.x > 0.5 ? 1 : 2);
	float strength = backlight[sector];
	vec3 ink_color = ink.rgb * mix(0.3, 1.0, smoothstep(0.0, 0.42, strength));
	if (strength > 0.0) {
		vec3 context_tint = sector == 0 ? vec3(0.49, 0.81, 1.0)
			: (sector == 1 ? vec3(0.69, 1.0, 0.45) : vec3(1.0, 0.65, 0.40));
		float field_light = smoothstep(0.42, 1.0, strength);
		vec3 tint = mix(vec3(1.0), context_tint, field_light);
		float blurred = 0.0;
		for (int tap = 0; tap < 8; tap++) {
			float angle = float(tap) * TAU / 8.0;
			vec2 ray = vec2(cos(angle), sin(angle));
			blurred += texture(TEXTURE, UV + ray * 0.018).a * 0.10;
			blurred += texture(TEXTURE, UV + ray * 0.044).a * 0.045;
		}
		float pulse = 1.0 - field_light * (0.11 + 0.11 * sin(TIME * 3.1));
		float light = (1.0 - exp(-blurred * 3.5)) * strength * pulse;
		float alpha = ink.a + light * (1.0 - ink.a);
		vec3 lit_ink = mix(ink_color, tint, 0.20 * strength);
		vec3 color = mix(tint, lit_ink, ink.a / max(alpha, 0.001));
		COLOR = vec4(color, alpha) * dial_modulate;
	} else {
		COLOR = vec4(ink_color, ink.a) * dial_modulate;
	}
}
