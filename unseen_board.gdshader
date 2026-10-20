shader_type canvas_item;
render_mode unshaded;

uniform vec4 fog_tint : source_color = vec4(0.12, 0.15, 0.22, 1.0);
uniform float fog_opacity : hint_range(0.0, 1.0) = 0.65;
uniform float drift_speed = 0.22;

varying vec2 board_position;

vec2 gradient(vec2 p) {
	float angle = fract(
		sin(dot(p, vec2(127.1, 311.7))) * 43758.5453
	) * 6.2831853;

	return vec2(cos(angle), sin(angle));
}

float smooth_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);

	// Smoother interpolation across cell boundaries.
	vec2 blend = local * local * local * (
		local * (local * 6.0 - 15.0) + 10.0
	);

	float a = dot(gradient(cell), local);
	float b = dot(
		gradient(cell + vec2(1.0, 0.0)),
		local - vec2(1.0, 0.0)
	);
	float c = dot(
		gradient(cell + vec2(0.0, 1.0)),
		local - vec2(0.0, 1.0)
	);
	float d = dot(
		gradient(cell + vec2(1.0, 1.0)),
		local - vec2(1.0, 1.0)
	);

	return mix(
		mix(a, b, blend.x),
		mix(c, d, blend.x),
		blend.y
	);
}

float mist_layers(vec2 p) {
	mat2 rotation = mat2(
		vec2(0.8, 0.6),
		vec2(-0.6, 0.8)
	);

	float result = smooth_noise(p) * 0.6;
	p = rotation * p * 1.93 + vec2(8.4, 3.7);

	result += smooth_noise(p) * 0.28;
	p = rotation * p * 2.07 + vec2(2.8, 9.1);

	result += smooth_noise(p) * 0.12;

	return clamp(0.5 + result, 0.0, 1.0);
}

void vertex() {
	board_position = VERTEX;
}

void fragment() {
	vec2 position = board_position / 220.0;
	float time = TIME * drift_speed;

	vec2 drift = vec2(time, -time * 0.35);

	// Bend the pattern so its underlying grid is less apparent.
	vec2 distortion = vec2(
		smooth_noise(position * 0.65 + drift),
		smooth_noise(position * 0.65 - drift + vec2(17.3, 6.2))
	);

	float base_mist = mist_layers(
		position + drift + distortion * 0.9
	);
	// Cross the main drift with smaller wisps so the fog visibly rolls.
	float wisps = mist_layers(
		position * 1.65 + vec2(-time * 0.7, time * 0.55)
		+ distortion * 1.3 + vec2(11.7, 4.2)
	);
	float mist = smoothstep(
		0.22, 0.78, base_mist * 0.65 + wisps * 0.35
	);

	vec3 color = fog_tint.rgb * (
		0.25 + mist * 1.1
	);

	COLOR = vec4(color, fog_opacity);
}
