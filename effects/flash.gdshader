shader_type canvas_item;
// Tint + hit flash for sprites (prototype sprite shader: mix(tex * tint, white, flash)).
uniform vec4 tint : source_color = vec4(1.0);
uniform float flash = 0.0;

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	COLOR = vec4(mix(t.rgb * tint.rgb, vec3(1.0), flash), t.a * tint.a);
}
