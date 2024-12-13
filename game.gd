extends Node2D
class_name Game

signal moving_to(cells: Array[Vector2i], speed: float)
signal food_eaten
signal died

enum GAME_STATE { PLAYING, VIEWING_SUMMARY, VIEWING_UPGRADES }

@export var cell_size := 32
@export var grid_size := Vector2i(20, 20)
#@export var FOOD_SCENE : PackedScene
#const FOOD_SCENE = preload("res://food.tscn")

#const DIRECTIONS = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
#const DIAGONALS = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]

var paused			:= true
var current_speed 	: float
var countdown		:= 0.3
var map				: TextureRect
var tilemap 		: TileMapLayer

#var _is_shared_map	: bool
var _input_queue 	:= []
var _snake_length 	:= 4
var _current_reverse_cooldown := 0.0
var _snake_pos 		: Vector2
var _snake_dir		: Vector2
var _move_progress	:= 0.0
var _snake_cells	: Array[Vector2i] = []
var _growing		:= false
var _crashing		:= false
var _crash_dist		: float
var _food_pos		: Vector2i
@onready var _snake	:= $Snake
@onready var _food	:= $Food
@onready var _countdown_label := %Countdown
@onready var _cooldown_bar := %CooldownBar
@onready var _speed_label := %LabelSpeed

@export var player: int
	#set(value):
		#player = value
		##_set_authority(player)
		#_set_authority.call_deferred(player)



func is_cell_empty(pos) -> bool:
	return (
		pos.x >= 0 and pos.x < grid_size.x
		and pos.y >= 0 and pos.y < grid_size.y
		and tilemap.get_cell_tile_data(pos) == null
	)
	
	
static func get_food_pos(tilemap_: TileMapLayer, grid_size_: Vector2i, snake_cells: Array) -> Vector2i:
	var pos: Vector2i
	var attempts = 0
	while true:
		attempts = (attempts + 1) % 300
		# If it takes too long to find a position,
			# try again in the next frame
		if attempts == 0:
			await Globals.wait_for_next_frame()
		pos = Vector2i(randi() % grid_size_.x, randi() % grid_size_.y)
		if ((!tilemap_ or tilemap_.get_cell_tile_data(pos) == null)
			and pos not in snake_cells
		):
			break
	return pos


func set_map(map_idx: int, snake_id: int = 0) -> void:
	_cooldown_bar.max_value = Globals.settings.reverse_cooldown
	var node = Globals.MAPS[map_idx].scene.instantiate()
	add_child(node)
	tilemap = node.get_node("%TileMapLayer")
	cell_size = node.cell_size
	grid_size = node.grid_size
	_cooldown_bar.size.x = node.rect_size.x - 40
	_countdown_label.position.x = node.rect_size.x / 2 - _countdown_label.size.x / 2
	
	if snake_id == -1:
		_snake.queue_free()
	else:
		_snake_pos = node.snakes[snake_id]
		_snake_dir = node.snake_dirs[snake_id]
		_snake.points = PackedVector2Array([
			_grid_pos_to_world(_snake_pos),
			_grid_pos_to_world(_snake_pos + -_snake_dir * (node.snake_length - 1)),
		])
		_snake_cells = node.get_snake_cells(snake_id)
		_snake_length = node.snake_length
		map = node
	
	if is_multiplayer_authority():
		await get_tree().create_timer(0.2).timeout
		move_food()


func set_color(color: Color) -> void:
	_snake.set_color(color)


@rpc("reliable")
func move_food(pos: Vector2i = Vector2i(-1, -1)) -> void:
	if pos == Vector2i(-1, -1):
		pos = await get_food_pos(tilemap, grid_size, _snake_cells)
	_food_pos = pos
	_food.show()
	_food.position = _grid_pos_to_world(pos)


func grow_snake() -> void:
	_growing = true
	_snake_length += 1
	var point_count = _snake.get_point_count()
	var last_point = _snake.get_point_position(point_count - 1)
	var second_to_last = _snake.get_point_position(point_count - 2)
	var dir = second_to_last.direction_to(last_point)
	_snake.set_point_position(point_count - 1, last_point + dir * _move_progress)


@rpc("any_peer", "call_local")
func start_reverse_cooldown() -> void:
	_cooldown_bar.show()
	_cooldown_bar.value = Globals.settings.reverse_cooldown


func set_crashing(crash_dist: float = 0.3) -> void:
	if !_crashing:
		_crashing = true
		_crash_dist = crash_dist
	#if paused:
		#print("game.gd:die() Error: Condition \"paused == true\" is true")
		#return
	#paused = true
	##var collision_offset = 0.65 if head_on_crash else 0.3
	##if _move_progress < 0.3 * cell_size:
	#var crash_dist = collision_offset - _move_progress / cell_size
	#var tween = create_tween()
	#tween.tween_method((func(pos):
		#_snake.set_point_position(0, Vector2(pos.x + 0.5, pos.y + 0.5) * cell_size)
		#),
		#_snake_pos,
		#_snake_pos + _snake_dir * crash_dist,
		#max(0, crash_dist * cell_size / current_speed)
		#)
	#await tween.finished#
	#died.emit()
	##modulate = Color.WEB_GRAY


func _ready() -> void:
	player = int(str(name))
	await get_tree().process_frame
	set_multiplayer_authority(player, true)
	if multiplayer.get_unique_id() == player:
		current_speed = Globals.settings.snake_speed
		_food.hide()
	else:
		_speed_label.queue_free()


func _process(delta: float) -> void:
	if countdown > 0.0:
		countdown -= delta
		_countdown_label.set_text(str(ceil(countdown)))
		if countdown <= 0.0:
			_countdown_label.hide()
			paused = false
	
	if is_multiplayer_authority() and !OS.has_feature("dedicated_server"):
		if current_speed == int(current_speed):
			_speed_label.set_text("Speed: %d" % int(current_speed))
		else:
			_speed_label.set_text("Speed: %.1f" % current_speed)
		queue_redraw()
		if Input.is_action_just_pressed("up"):
			_input_queue.push_back(Vector2(0, -1))
		if Input.is_action_just_pressed("down"):
			_input_queue.push_back(Vector2(0, 1))
		if Input.is_action_just_pressed("left"):
			_input_queue.push_back(Vector2(-1, 0))
		if Input.is_action_just_pressed("right"):
			_input_queue.push_back(Vector2(1, 0))
		if (Input.is_action_just_pressed("reverse") and Globals.settings.allow_reverse
				and _current_reverse_cooldown <= 0.0):
			_reverse_snake()
		if countdown <= 0:
			_move_snake(delta)


func _physics_process(delta: float) -> void:
	if _current_reverse_cooldown > 0 and !paused:
		_current_reverse_cooldown -= delta
		_cooldown_bar.value = _current_reverse_cooldown
		if _current_reverse_cooldown <= 0:
			_cooldown_bar.hide()


func _draw() -> void:
	for cell in _snake_cells:
		var rect = Rect2(cell * cell_size, Vector2(cell_size, cell_size))
		draw_rect(rect, Color(1, 0, 0, 0.3))


func _move_snake(delta: float) -> void:
	if paused:
		return
	
	var dist_to_next_cell = cell_size - _move_progress
	var movement_left = current_speed * delta
	if _crashing:
		movement_left = clampf(_crash_dist * cell_size - _move_progress, 0, movement_left)
		#print("%d\t%.3f %.3f" % [multiplayer.get_unique_id(), _move_progress / cell_size, _crash_dist])
	
	while dist_to_next_cell <= movement_left:
		_move_progress = 0.0
		var movement = min(dist_to_next_cell, movement_left)
		movement_left -= movement
		_snake_pos = round(_snake_pos + _snake_dir * movement / cell_size)
		var point_pos = Vector2(_snake_pos.x + 0.5, _snake_pos.y + 0.5) * cell_size
		_snake.set_point_position(0, point_pos)
		dist_to_next_cell = cell_size
		var input
		while !_input_queue.is_empty():
			input = _input_queue.pop_front()
			if input.x != _snake_dir.x and input.y != _snake_dir.y:
				_snake_dir = input
				_snake.add_point(point_pos, 0)
				break
		var new_pos = Vector2i(_snake_pos + _snake_dir)
		if _growing:
			_growing = false
		else:
			_snake_cells.pop_back()
			_snake.move_tail(movement)
		if new_pos in _snake_cells or !is_cell_empty(new_pos):
			set_crashing()
		else:
			if _food_pos == new_pos:
				food_eaten.emit()
				grow_snake()
				move_food()
			_snake_cells.push_front(new_pos)
			moving_to.emit(_snake_cells, current_speed)
	
	_snake_pos += movement_left * _snake_dir / cell_size
	_snake.set_point_position(0, Vector2(_snake_pos.x + 0.5, _snake_pos.y + 0.5) * cell_size)
	_move_progress += movement_left
	if _crashing and _move_progress >= _crash_dist * cell_size:
		paused = true
		died.emit()
	if !_growing:
		_snake.move_tail(movement_left)


func _grid_pos_to_world(pos: Vector2i) -> Vector2:
	return Vector2(pos.x + 0.5, pos.y + 0.5) * cell_size


func _reverse_snake() -> void:
	_current_reverse_cooldown = Globals.settings.reverse_cooldown
	var points = _snake.points
	points.reverse()
	_snake.set_points(points)
	_snake_dir = points[1].direction_to(points[0])
	_snake_pos = _snake.get_point_position(0) / cell_size - Vector2(0.5, 0.5)
	_move_progress = cell_size - _move_progress
	_snake_cells.reverse()
	_snake_cells.push_front(_snake_cells[0] + Vector2i(_snake_dir))
	_snake_cells.pop_back()
	_input_queue = []
	_crashing = false
	#if _is_shared_map:
		#start_reverse_cooldown()
	#else:
	start_reverse_cooldown.rpc()
