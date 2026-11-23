shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform vec3 weights = vec3(1.0, 0.0, 0.0);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

uniform sampler2D rise_art : source_color, filter_linear, repeat_disable;
uniform sampler2D flourish_art : source_color, filter_linear, repeat_disable;
uniform sampler2D fall_art : source_color, filter_linear, repeat_disable;
uniform bool has_rise = false;
uniform bool has_flourish = false;
uniform bool has_fall = false;
uniform vec4 rise_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 flourish_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 fall_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 rise_fallback : source_color = vec4(0.0);
uniform vec4 flourish_fallback : source_color = vec4(0.0);
uniform vec4 fall_fallback : source_color = vec4(0.0);


vec4 context_color(sampler2D art, bool has_art, vec4 region, vec4 fallback, vec2 uv) {
	vec4 texel = has_art ? texture(art, region.xy + uv * region.zw) : vec4(0.0);
	vec4 result = vec4(texel.rgb * texel.a, texel.a);
	return result + vec4(fallback.rgb * fallback.a, fallback.a) * (1.0 - texel.a);
}


void fragment() {
	// Blend the registered layers before applying opacity so they never darken
	// the background or weaken the table tint halfway through a transition.
	vec4 result = vec4(0.0);
	if (weights.x > 0.0) {
		result += weights.x * context_color(rise_art, has_rise, rise_region, rise_fallback, UV);
	}
	if (weights.y > 0.0) {
		result += weights.y * context_color(flourish_art, has_flourish, flourish_region, flourish_fallback, UV);
	}
	if (weights.z > 0.0) {
		result += weights.z * context_color(fall_art, has_fall, fall_region, fall_fallback, UV);
	}
	vec4 tint = COLOR;
	COLOR = vec4(result.rgb * tint.rgb, result.a) * (opacity * tint.a);
}
