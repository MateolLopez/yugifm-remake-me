extends Sprite2D

@export var scroll_speed: float = 18.0
@export var scroll_direction: Vector2 = Vector2.LEFT
@export var region_size: Vector2 = Vector2(2200, 1400)

var _offset := Vector2.ZERO


func _ready() -> void:
	if texture == null:
		push_warning("BgDuel no tiene texture asignada.")
		return

	centered = true

	region_enabled = true

	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

	region_rect = Rect2(Vector2.ZERO, region_size)


func _process(delta: float) -> void:
	if texture == null:
		return

	var dir := scroll_direction.normalized()
	_offset += dir * scroll_speed * delta

	var tex_size := texture.get_size()

	if tex_size.x > 0:
		_offset.x = fposmod(_offset.x, tex_size.x)

	if tex_size.y > 0:
		_offset.y = fposmod(_offset.y, tex_size.y)

	region_rect.position = _offset
