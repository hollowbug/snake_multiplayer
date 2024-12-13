extends TextureRect

@export var grid_size 		:= Vector2i(20, 20)
@export var cell_size 	 	:= 48
@export var snake_length 	:= 4
@export var snakes 			: PackedVector2Array
@export var snake_dirs 		: PackedVector2Array

@onready var rect_size := Vector2(grid_size.x * cell_size, grid_size.y * cell_size)

func get_snake_cells(snake_id: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for i in range(-1, snake_length - 1):
		cells.append(Vector2i(snakes[snake_id] + i * -snake_dirs[snake_id]))
	return cells

func get_snake_points(snake_id: int) -> Array[Vector2]:
	var tail_pos = snakes[snake_id] - snake_dirs[snake_id] * snake_length
	return [
		Vector2(snakes[snake_id].x + 0.5, snakes[snake_id].y + 0.5) * cell_size,
		Vector2(tail_pos.x + 0.5, tail_pos.y + 0.5) * cell_size,
	] as Array[Vector2]
