shader_type canvas_item;
render_mode unshaded;

uniform vec4 fog_color : source_color = vec4(0.26, 0.28, 0.30, 1.0);
uniform float fog_strength : hint_range(0.0, 1.0) = 0.8;
uniform float drift_speed : hint_range(0.0, 0.1) = 0.1;

uniform bool reduce_animation = false;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	vec2 blend = local * local * (3.0 - 2.0 * local);

	return mix(
		mix(hash(cell), hash(cell + vec2(1.0, 0.0)), blend.x),
		mix(
			hash(cell + vec2(0.0, 1.0)),
			hash(cell + vec2(1.0, 1.0)),
			blend.x
		),
		blend.y
	);
}

float mist(vec2 p) {
	float value = noise(p) * 0.57;
	value += noise(p * 2.03 + vec2(8.2, 3.7)) * 0.28;
	value += noise(p * 4.07 + vec2(2.4, 9.1)) * 0.15;
	return value;
}

void fragment() {
	// Correct proportions for different window sizes.
	vec2 aspect = vec2(
		SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x,
		1.0
	);

	vec2 position = UV * aspect * 5.0;

	float time = reduce_animation ? 0.0 : TIME * drift_speed;

	float clouds = mist(position + vec2(time, -time * 0.4));
	float wisps = mist(
		position * 1.6 + vec2(-time * 0.6, time * 0.5)
	);

	float density = smoothstep(
		0.28, 0.78, clouds * 0.7 + wisps * 0.3
	);

	// Strongest near the edges, lighter around the menu.
	float edge = smoothstep(
		0.18, 0.65, length((UV - vec2(0.5)) * vec2(1.0, 1.2))
	);

	float opacity = density * edge * fog_strength;
	COLOR = vec4(fog_color.rgb, opacity);
}