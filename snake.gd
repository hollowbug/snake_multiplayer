extends Line2D

@onready var _head	:= $Head
@onready var _tail	:= $Tail


func set_color(color: Color) -> void:
	default_color = color
	_head.self_modulate = color
	_tail.self_modulate = color


func _process(delta: float) -> void:
	var point_count = get_point_count()
	if point_count < 2:
		return
	var pos0 = get_point_position(0)
	_head.position = pos0
	_head.rotation = get_point_position(1).angle_to_point(pos0)
	_tail.position = get_point_position(point_count - 1)
