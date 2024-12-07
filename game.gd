extends Node2D

signal food_eaten
signal died

enum GAME_STATE { PLAYING, VIEWING_SUMMARY, VIEWING_UPGRADES }

@export var CELL_SIZE := 32
@export var GRID_SIZE := Vector2i(20, 20)
#@export var FOOD_SCENE : PackedScene
#const FOOD_SCENE = preload("res://food.tscn")

#const DIRECTIONS = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
#const DIAGONALS = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]

var paused			:= true
var current_speed 	: float

var _input_queue 	:= []
var _snake_length 	:= 4
var _current_reverse_cooldown := 0.0
var _countdown		:= 3.0
var _snake_pos 		:= Vector2(10, 10)
var _snake_dir		:= Vector2(1, 0)
var _move_progress	:= 0.0
var _snake_cells	: Array[Vector2i] = []
var _growing		:= false
var _food_pos		: Vector2i
var _tilemap 		: TileMapLayer
@onready var _line 	:= $Line2D
@onready var _head	:= $Head
@onready var _tail	:= $Tail
@onready var _food	:= $Food
@onready var _countdown_label := %Countdown

@export var player: int
	#set(value):
		#player = value
		##_set_authority(player)
		#_set_authority.call_deferred(player)


func set_map(map: int) -> void:
	#print(multiplayer.get_unique_id(), " is loading map ", map)
	var node = Globals.MAPS[map].instantiate()
	add_child(node)
	_tilemap = node.get_node("TileMapLayer")
	_move_food.call_deferred()


func set_color(color: Color) -> void:
	_line.default_color = color
	_head.modulate = color
	_tail.modulate = color


func _set_authority(id: int) -> void:
	#print("multiplayer = ", multiplayer)
	#print(multiplayer.get_unique_id(), " is setting authority to ", id)
	set_multiplayer_authority(id, true)
	#$MultiplayerSpawner.set_multiplayer_authority(id)
	#$MultiplayerSynchronizer.set_multiplayer_authority(id)


func _ready() -> void:
	player = int(str(name))
	await get_tree().process_frame
	_set_authority(player)
	#_set_authority.call_deferred(player)
	if multiplayer.get_unique_id() == player:
		_initialize()
	else:
		#print(multiplayer.get_unique_id(), " ", player)
		%LabelSpeed.queue_free()
		_countdown_label.queue_free()
		set_process(false)


func _process(delta: float) -> void:
	#queue_redraw()
	if Input.is_action_just_pressed("up"):
		_input_queue.push_back(Vector2(0, -1))
	if Input.is_action_just_pressed("down"):
		_input_queue.push_back(Vector2(0, 1))
	if Input.is_action_just_pressed("left"):
		_input_queue.push_back(Vector2(-1, 0))
	if Input.is_action_just_pressed("right"):
		_input_queue.push_back(Vector2(1, 0))
	if Input.is_action_just_pressed("reverse"):
		pass
		_on_reverse_key_pressed()
	
	if _countdown > 0.0:
		_countdown -= delta
		_countdown_label.set_text(str(ceil(_countdown)))
		if _countdown <= 0.0:
			_countdown_label.hide()
			paused = false
	else:
		_move_snake(delta)
		%LabelSpeed.set_text("Speed: " + str(current_speed))


func _physics_process(_delta: float) -> void:
	var point_count = _line.get_point_count()
	if point_count == 0:
		return
	_head.position = _line.get_point_position(0)
	_tail.position = _line.get_point_position(point_count - 1)


func _initialize() -> void:
	current_speed = Globals.settings.snake_speed
	_line.points = PackedVector2Array([
		_grid_pos_to_world(_snake_pos),
		_grid_pos_to_world(_snake_pos + Vector2(-_snake_length, 0)),
	])
	for i in range(-1, _snake_length):
		_snake_cells.append(Vector2i(_snake_pos.x - i, _snake_pos.y))

#func _draw() -> void:
	#for cell in _snake_cells:
		#var rect = Rect2(cell * CELL_SIZE, Vector2(CELL_SIZE, CELL_SIZE))
		#draw_rect(rect, Color(1, 0, 0, 0.3))


func _move_snake(delta: float) -> void:
	if paused:
		return
	
	var dist_to_next_cell = CELL_SIZE - _move_progress
	var movement_left = current_speed * delta
	
	while dist_to_next_cell <= movement_left:
		_move_progress = 0.0
		var movement = min(dist_to_next_cell, movement_left)
		movement_left -= movement
		_snake_pos = round(_snake_pos + _snake_dir * movement / CELL_SIZE)
		var point_pos = Vector2(_snake_pos.x + 0.5, _snake_pos.y + 0.5) * CELL_SIZE
		_line.set_point_position(0, point_pos)
		dist_to_next_cell = CELL_SIZE
		if !_input_queue.is_empty():
			var dir = _input_queue.pop_front()
			if dir.x != _snake_dir.x and dir.y != _snake_dir.y:
				_snake_dir = dir
				_line.add_point(point_pos, 0)
		var new_pos = Vector2i(_snake_pos + _snake_dir)
		if _growing:
			_growing = false
		else:
			_snake_cells.pop_back()
			_move_tail(movement)
		if new_pos in _snake_cells or !_is_cell_empty(new_pos):
			paused = true
			var crash_dist = 0.3
			var tween = create_tween()
			tween.tween_method((func(pos):
				_line.set_point_position(0, Vector2(pos.x + 0.5, pos.y + 0.5) * CELL_SIZE)
				),
				_snake_pos,
				_snake_pos + _snake_dir * crash_dist,
				crash_dist * CELL_SIZE / current_speed
				)
			died.emit()
			modulate = Color.WEB_GRAY
			return
		_snake_cells.push_front(new_pos)
		if _food_pos == new_pos:
			_growing = true
			_snake_length += 1
			food_eaten.emit()
			_move_food()
	
	_snake_pos += movement_left * _snake_dir / CELL_SIZE
	_line.set_point_position(0, Vector2(_snake_pos.x + 0.5, _snake_pos.y + 0.5) * CELL_SIZE)
	_move_progress += movement_left
	if !_growing:
		_move_tail(movement_left)

	if _current_reverse_cooldown > 0.0:
		_current_reverse_cooldown -= min(delta, _current_reverse_cooldown)
		# Snake blinks when cooldown is about to end
		if _current_reverse_cooldown <= 2.5 and fmod(_current_reverse_cooldown, 1.0) > 0.5:
			_line.default_color = Color.AQUAMARINE
		elif _current_reverse_cooldown <= 2.5:
			_line.default_color = Color.WHITE


func _move_tail(amount: float) -> void:
	var movement_left = amount
	while movement_left > 0:
		var num_points = _line.get_point_count()
		if num_points == 0:
			print("Error: Trying to move tail past head")
			return
		var point1 = _line.get_point_position(num_points - 1)
		var point2 = _line.get_point_position(num_points - 2)
		var dist = point1.distance_to(point2)
		if dist <= amount:
			movement_left -= dist
			_line.remove_point(num_points - 1)
		else:
			var dir = point1.direction_to(point2)
			_line.set_point_position(num_points - 1, point1 + dir * movement_left)
			movement_left = 0


func _move_food() -> void:
	var pos: Vector2i
	var attempts = 0
	
	# Find a random position for the food
	while true:
		attempts = (attempts + 1) % 300
		# If it takes too long to find a position,
			# try again in the next frame
		if attempts == 0:
			_food_pos = Vector2i(-1, -1)
			_food.hide()
			await get_tree().process_frame
		pos = Vector2i(randi() % GRID_SIZE.x, randi() % GRID_SIZE.y)
		if (_tilemap.get_cell_tile_data(pos) == null
			and pos not in _snake_cells
		):
			break
		#print("move_food(): Position ", pos, " is occupied.")
	_food_pos = pos
	_food.show()
	_food.position = _grid_pos_to_world(pos)
	#print("Creating food at position ", pos, " (", _food.position, ")")


func _grid_pos_to_world(pos: Vector2i) -> Vector2:
	return Vector2(pos.x + 0.5, pos.y + 0.5) * CELL_SIZE


func _is_cell_empty(pos) -> bool:
	return (
		pos.x >= 0 and pos.x < GRID_SIZE.x
		and pos.y >= 0 and pos.y < GRID_SIZE.y
		and _tilemap.get_cell_tile_data(pos) == null
	)


func _on_reverse_key_pressed() -> void:
	if !Globals.settings.allow_reverse or _current_reverse_cooldown > 0.0:
		return
	_current_reverse_cooldown = Globals.settings.reverse_cooldown
	_line.default_color = Color.AQUAMARINE
	var points = _line.points
	points.reverse()
	_line.set_points(points)
	_snake_dir = points[1].direction_to(points[0])
	_snake_pos = round(_line.get_point_position(0) / CELL_SIZE - Vector2(0.5, 0.5))
	_snake_cells.reverse()
	_input_queue = []
