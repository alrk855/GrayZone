/**
 * Starfield Shader
 * 
 * This shader is adapted from a tutorial by Martijn Steinrucken,
 * also known as "The Art of Code" on YouTube.
 * 
 * All credits for the concept and implementation go to Martijn.
 * This code is shared here for educational and non-commercial purposes.
 * 
 * Original tutorial: https://www.youtube.com/c/TheArtofCodeIsCool
 * 
 * Shader type: canvas_item (2D)
 */

shader_type canvas_item;

uniform vec2 VIEWPORT_SIZE = vec2(1280, 720);

#define NUM_LAYERS 8.0

mat2 Rot(float theta) {
    float cosa = cos(theta);
    float sina = sin(theta);

    return mat2(
        vec2(cosa, -sina),
        vec2(sina,  cosa)
    );
}

float Star(vec2 uv, float flare) {
    float d = length(uv);
    float m = .02 / d;

    float rays = max(0.0, 1.0 - abs(uv.x * uv.y * 10000.0));
    m += rays * flare;
    uv *= Rot(PI / 4.0);
    rays = max(0.0, 1.0 - abs(uv.x * uv.y * 10000.0));
    m += rays * 0.3 * flare;

    m *= smoothstep(1.0, 0.2, d);
    return m;
}

float Hash21(vec2 p) {
    p = fract(p * vec2(123.23, 456.34));
    p += dot(p, p + 45.45);
    return fract(p.x * p.y);	
}

vec3 StarLayer(vec2 uv) {
    vec3 col = vec3(0.0);

    vec2 gv = fract(uv) - 0.5;
    vec2 id = floor(uv);

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 offset = vec2(float(x), float(y));
            float n = Hash21(id + offset);
            float size = fract(n * 534.0);
            float star = Star(gv - offset - vec2(n - 0.5, fract(n * 165.0) - 0.5), smoothstep(0.9, 0.1, size) * 1.0);
            vec3 colors = sin(vec3(0.2, 0.3, 0.9) * fract(n * 2434.0) * 123.0) * 0.5 + 0.5;
            colors *= vec3(1.0, 0.5, 1.0 + size);
            star *= sin(TIME * 3.0 + n * 18.3) * 0.5 + 1.0;
            col += star * size * colors;
        }
    }

    return col;
}

void fragment() {
    vec2 fragCoord = UV * VIEWPORT_SIZE;
    vec2 uv = (fragCoord - 0.5 * VIEWPORT_SIZE) / VIEWPORT_SIZE.y;
    float t = TIME * 0.05;
    uv *= Rot(t);

    vec3 col = vec3(0.0);

    for (float i = 0.0; i < 1.0; i += 1.0 / NUM_LAYERS) {
        float depth = fract(i + t);
        float scale = mix(20.0, 0.5, depth);
        float fade = depth * smoothstep(1.0, 0.9, depth);
        col += StarLayer(uv * scale + i * 343.0) * fade;
    }

    COLOR = vec4(col, 1.0);
}
