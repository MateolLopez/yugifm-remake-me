shader_type canvas_item;

uniform bool enabled = true;

void fragment(){
  COLOR = texture(TEXTURE, UV);
	if (enabled) {
	COLOR.r = 0.7;
	COLOR.g = 0.7;
	}
}
