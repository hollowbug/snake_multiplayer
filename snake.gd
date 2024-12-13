extends Line2D

@onready var _head	:= $Head
@onready var _tail	:= $Tail


func set_color(color: Color) -> void:
	default_color = color
	_head.self_modulate = color
	_tail.self_modulate = color


func move(direction: Vector2, distance: float, move_tail: bool = true) -> void:
	set_point_position(0, points[0] + direction * distance)
	if move_tail:
		move_tail(distance)


func move_tail(distance: float) -> void:
	var movement_left = distance
	while movement_left > 0:
		var num_points = get_point_count()
		if num_points < 2:
			print("snake.gd:move_tail().error: Line2D has less than 2 points")
			return
		var point1 = get_point_position(num_points - 1)
		var point2 = get_point_position(num_points - 2)
		var dist = point1.distance_to(point2)
		if dist <= distance:
			movement_left -= dist
			remove_point(num_points - 1)
		else:
			var dir = point1.direction_to(point2)
			set_point_position(num_points - 1, point1 + dir * movement_left)
			movement_left = 0


func _process(_delta: float) -> void:
	var point_count = get_point_count()
	if point_count < 2:
		return
	var pos0 = get_point_position(0)
	_head.position = pos0
	_head.rotation = get_point_position(1).angle_to_point(pos0)
	_tail.position = get_point_position(point_count - 1)
