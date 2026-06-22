shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform float distortion_strength = 0.007;
uniform float wave_frequency = 24.0;
uniform float wave_speed = 0.0;
uniform float whiteness = 0.9;
uniform float shimmer_strength = 0.1;
uniform float edge_softness = 0.06;

void fragment() {
	vec2 uv = UV;

	float wave_a = sin((uv.y * wave_frequency) + (TIME * wave_speed));
	float wave_b = cos((uv.x * 10.0) - (TIME * 1.7));
	float wave = wave_a * wave_b;

	vec2 distorted_screen_uv = SCREEN_UV + vec2(wave * distortion_strength, 0.0);
	vec4 screen_col = texture(screen_texture, distorted_screen_uv);

	float edge =
		smoothstep(0.0, edge_softness, uv.x) *
		smoothstep(0.0, edge_softness, uv.y) *
		smoothstep(0.0, edge_softness, 1.0 - uv.x) *
		smoothstep(0.0, edge_softness, 1.0 - uv.y);

	float shimmer = 1.0 + (sin((uv.y * 38.0) + (TIME * 6.0)) * shimmer_strength);

	vec3 final_col = mix(screen_col.rgb, vec3(1.0), whiteness);

	COLOR = vec4(final_col, COLOR.a * edge * shimmer);
}