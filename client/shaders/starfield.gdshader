shader_type canvas_item;

uniform float density : hint_range(0.95, 1.0) = 0.987;
uniform float twinkle_speed : hint_range(0.0, 5.0) = 1.5;
uniform float nebula_strength : hint_range(0.0, 1.0) = 0.22;
uniform vec3 nebula_color_a : source_color = vec3(0.08, 0.04, 0.22);
uniform vec3 nebula_color_b : source_color = vec3(0.28, 0.06, 0.12);
uniform vec3 nebula_color_c : source_color = vec3(0.04, 0.12, 0.22);
uniform float drift_speed : hint_range(0.0, 0.05) = 0.004;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 hash32(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

vec3 star_layer(vec2 uv, float scale, float seed) {
	vec2 p = uv * scale + seed;
	vec2 cell = floor(p);
	vec2 fp = fract(p);
	vec3 h = hash32(cell);
	if (h.x < density) {
		return vec3(0.0);
	}

	vec2 star_pos = h.xy * 0.6 + 0.2;
	float d = length(fp - star_pos);

	float rarity = (h.x - density) / (1.0 - density);
	float core = 0.11 + rarity * 0.22;
	float halo = core * 4.0;
	float intensity = smoothstep(halo, 0.0, d) * 0.45 + smoothstep(core, 0.0, d);

	vec3 color = vec3(1.0);
	if (h.z > 0.985) {
		color = vec3(1.00, 0.42, 0.30);
	} else if (h.z > 0.965) {
		color = vec3(1.00, 0.85, 0.55);
	} else if (h.z > 0.94) {
		color = vec3(0.55, 0.75, 1.00);
	} else if (h.z > 0.91) {
		color = vec3(0.70, 1.00, 0.92);
	}

	float t = TIME * twinkle_speed;
	float twinkle = 0.55 + 0.45 * sin(t + h.y * 6.2832) * cos(t * 0.73 + h.x * 12.566);

	return color * intensity * twinkle * (0.6 + 0.4 * rarity);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

	vec2 drift = vec2(TIME * drift_speed, TIME * drift_speed * 0.4);

	vec3 col = vec3(0.0);
	col += star_layer(uv + drift,        60.0,   0.0);
	col += star_layer(uv + drift * 1.5,  150.0, 17.0) * 0.75;
	col += star_layer(uv + drift * 2.2,  340.0, 53.0) * 0.55;

	float n  = smoothstep(0.45, 0.85, fbm(uv * 2.0 + TIME * 0.012));
	float n2 = smoothstep(0.55, 0.90, fbm(uv * 4.5 + 9.7 - TIME * 0.008));
	float pick = fbm(uv * 0.8 + 31.0);
	vec3 neb = mix(nebula_color_a, nebula_color_b, smoothstep(0.4, 0.6, pick));
	neb = mix(neb, nebula_color_c, smoothstep(0.6, 0.85, pick));
	col += neb * (n * 0.7 + n2 * 0.3) * nebula_strength;

	col += vec3(0.004, 0.006, 0.012);

	COLOR = vec4(col, 1.0);
}
