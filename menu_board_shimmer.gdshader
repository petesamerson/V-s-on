shader_type canvas_item;
render_mode unshaded;

uniform float shimmer_strength : hint_range(0.0, 0.4) = 0.12;
uniform float shimmer_speed : hint_range(0.0, 2.0) = 0.8;

void fragment() {
	vec4 base = COLOR;

	// Identify colored tiles and pieces; leave neutral grays alone.
	float highest = max(base.r, max(base.g, base.b));
	float lowest = min(base.r, min(base.g, base.b));
	float colored = smoothstep(0.04, 0.18, highest - lowest);

	// Offset the pulse across the screen for a slow traveling shimmer.
	vec2 screen_position = SCREEN_UV;
	float phase = (
		TIME * shimmer_speed
		- screen_position.x * 5.0
		- screen_position.y * 2.0
	);

	float pulse = pow(0.5 + 0.5 * sin(phase), 4.0);
	float highlight = pulse * shimmer_strength * colored;

	vec3 brighter = mix(base.rgb, vec3(1.0), 0.65);
	COLOR = vec4(mix(base.rgb, brighter, highlight), base.a);
}