shader_type canvas_item;

uniform float shimmer_strength : hint_range(0.0, 1.0) = 0.0;
uniform float shimmer_speed = 0.35;
uniform float shimmer_phase = 0.0;

void fragment() {
	vec4 base = COLOR;

	// Distance from the center, normalized to the image corners.
	float radius = length(UV - vec2(0.5)) / 0.707107;

	// Expand from the center, then fade before restarting.
	//float progress = fract(TIME * shimmer_speed);
    float progress = fract(TIME * shimmer_speed + shimmer_phase);
	float front = progress * 1.35;

	// Soft gradient behind the expanding edge.
	float gradient = smoothstep(front - 0.45, front, radius);
	gradient *= 1.0 - smoothstep(front, front + 0.2, radius);

	// Smooth entrance and exit for each pulse.
	float envelope = smoothstep(0.0, 0.12, progress);
	envelope *= 1.0 - smoothstep(0.72, 1.0, progress);

	float highlight = gradient * envelope * shimmer_strength;

	// COLOR = vec4(
	// 	mix(base.rgb, vec3(1.0), highlight),
	// 	base.a
	// );
    vec3 lighter_color = clamp(base.rgb * 2.0, 0.0, 1.0);

	COLOR = vec4(
		mix(base.rgb, lighter_color, highlight),
		base.a
	);
}