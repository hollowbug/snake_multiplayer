extends TextureRect

@export var grid_size := Vector2i(20, 20)
@export var cell_size := 48
@export var snakes : PackedVector2Array
@export var snake_dirs : PackedVector2Array

@onready var rect_size := Vector2(grid_size.x * cell_size, grid_size.y * cell_size)

#func _ready() -> void:
	#rect_size = Vector2(grid_size.x * cell_size, grid_size.y * cell_size)
