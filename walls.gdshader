shader_type canvas_item;

uniform sampler2D large_texture;  // The texture to tile across walls
uniform vec2 texture_size = vec2(128, 128);
//uniform vec2 texture_offset = vec2(0.0, 0.0); // Optional offset for texture alignment

void fragment() {
    vec2 uv = fract(FRAGCOORD.xy / texture_size);

    COLOR = texture(large_texture, uv);
}