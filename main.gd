extends Node

@export var SPEED_INCREASE := 2.0

const PLAYER_NAME_LABEL = preload("res://player_name.tscn")
#const PLAYER = preload("res://player.tscn")
const GAME = preload("res://game.tscn")
const GAME_SIZE := Vector2(960, 960)
const MAX_OPPONENT_GAME_SCALE = 0.3
const OPPONENT_GAME_X := 1100
const SHARED_GAME_SIZE := Vector2(1280, 960)

# Host only properties
var 		_players := {}
var 		_settings: Dictionary = Globals.settings
var 	 _num_snakes : int
var    _snakes_alive : int
var	  _highest_score : int
var    _selected_map := 2
var	  _is_shared_map := false
var 	 _game_ended := false
var 		_tilemap : TileMapLayer
var 	  _grid_size : Vector2i
var		  _cell_size : int
var _shared_food_pos : Vector2i
@onready var _setting_nodes := {
	snake_speed = %SettingContainer/Setting,
	speed_increase = %SettingContainer/Setting2,
	allow_reverse = %SettingContainer/Setting3,
	reverse_cooldown = %SettingContainer/Setting4,
}

# Shared properties
var game_state = "menu"

# Client properties
var 	 _player_name := "Player"
var 		 _is_host := false
var 	_map_selector : CanvasLayer
var 			_game : Node2D
@onready var _player_list = %PlayerList
@onready var _button_continue = %ButtonContinue

func _ready() -> void:
	if OS.has_feature("dedicated_server"):
		var port = OS.get_environment("PORT")
		_create_server(int(port) if port else 20527)
	
	else: # Client
		if OS.has_feature("editor"):
			%JoinGameIP.set_text("127.0.0.1")
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		%MainMenu.show()
		%Lobby.hide()
		for node in get_tree().get_nodes_in_group("host_only"):
			node.hide()
		SignalBus.player_added_to_list.connect(_on_player_added_to_list)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			
			KEY_ESCAPE:
				if game_state == "menu":
					get_tree().quit()
				else:
					multiplayer.multiplayer_peer.close()
					_return_to_menu()
			
			KEY_F1: # Add dummy player for debug
				if _is_host and OS.has_feature("editor"):
					print("Adding dummy player...")
					var id = randi() % 999999
					#var color = Color(randf(), randf(), randf())
					_register_player.rpc_id(1, id, "Bot")
					#_players[id].color = color
					#_players[id].color_picker.color = color


func _create_server(port: int) -> void:
	var server = ENetMultiplayerPeer.new()
	var err = server.create_server(port)
	if err:
		print("Failed to create server: ", error_string(err))
		return
	print("Server running on port ", port)
	game_state = "lobby"
	multiplayer.multiplayer_peer = server
	server.peer_disconnected.connect(_on_client_disconnected)
	%Lobby.show()


func _join_server(ip: String, port: int) -> void:
	print("Joining server...")
	var client = ENetMultiplayerPeer.new()
	var err = client.create_client(ip, port)
	if err:
		print("Unable to join server")
		return
	multiplayer.multiplayer_peer = client
	%MainMenu.hide()
	#for node in get_tree().get_nodes_in_group("host_only"):
		#node.hide()


func _on_player_added_to_list(node: HBoxContainer) -> void:
		var is_me = multiplayer.get_unique_id() == int(str(node.name))
		var picker: ColorPickerButton = node.get_node("%ColorPickerButton")
		picker.disabled = !is_me
		if is_me:
			picker.popup_closed.connect(_on_snake_color_changed.bind(picker))


func _on_snake_color_changed(picker: ColorPickerButton) -> void:
	_on_player_changed_color.rpc_id(1, picker.color)


@rpc("any_peer", "reliable")
func _on_player_changed_color(color) -> void:
	var player = multiplayer.get_remote_sender_id()
	_players[player].color = color
	if "color_picker" in _players[player]:
		_players[player].color_picker.color = color


func _on_connected() -> void:
	_register_player.rpc_id(1, multiplayer.get_unique_id(), _player_name)


@rpc("any_peer", "reliable")
func _register_player(id: int, name_: String):
	if multiplayer.get_unique_id() != 1:
		return
	print("%s joined" % name_)
	_players[id] = {
		name = name_,
		color = Color.WHITE,
		wins = 0,
		alive = false,
		host = false,
	}
	if _players.keys().size() == 1:
		_set_host.rpc_id(id)
		_players[id].host = true
	var node = PLAYER_NAME_LABEL.instantiate()
	node.name = str(id)
	_player_list.add_child(node, true)
	var label = node.get_node("Label")
	label.text = _players[id].name
	var picker = node.get_node("%ColorPickerButton")
	_players[id].player_list_node = node
	_players[id].color_picker = picker
	_update_selected_map.rpc_id(id, _selected_map)
	if game_state == "game":
		_on_game_started.rpc_id(id, _players, _selected_map, _is_shared_map,
				-1, Globals.settings, true)


func _on_client_disconnected(id: int) -> void:
	print("%s disconnected" % _players[id].name)
	_players[id].player_list_node.queue_free()
	_players.erase(id)


func _on_button_create_game_pressed() -> void:
	pass # currently only hosted on dedicated server, not locally
	#_player_name = %PlayerName.text
	#var port = int(%CreateGamePort.text)
	#_create_server(port)


func _on_button_join_game_pressed() -> void:
	_player_name = "%s" % %PlayerName.text
	_join_server(%JoinGameIP.text, int(%JoinGamePort.text))


func _on_button_continue_pressed() -> void:
	if game_state == "lobby":
		_host_start_game.rpc_id(1)
	elif game_state == "game":
		_host_return_to_lobby.rpc_id(1)


@rpc("any_peer", "reliable")
func _host_start_game() -> void:
	game_state = "game"
	_game_ended = false
	%Lobby.hide()
	var players = _players.keys()
	_num_snakes = players.size()
	_snakes_alive = _num_snakes
	_is_shared_map = (players.size() > 1
			and Globals.MAPS[_selected_map].type == "large")
	
	var map
	if _is_shared_map:
		map = Globals.MAPS[_selected_map].scene.instantiate()
		$Players.add_child(map)
		_tilemap = map.get_node("%TileMapLayer")
		_grid_size = map.grid_size
		_cell_size = map.cell_size
		for i in range(players.size()):
			_players[players[i]].snake_cells = map.get_snake_cells(i)
	
	for player in _players:
		_players[player].alive = true
		_players[player].ready = false
		var game = GAME.instantiate()
		game.name = str(player)
		$Players.add_child(game, true)
		_players[player].game = game
		#print("is_shared_map = ", is_shared_map)
	for i in range(players.size()):
		var snake_idx = i if _is_shared_map else 0
		_on_game_started.rpc_id(players[i], _players, _selected_map, _is_shared_map, snake_idx, _settings)
	if _is_shared_map:
		await get_tree().create_timer(0.2).timeout
		_host_move_shared_food()


@rpc("any_peer", "reliable")
func _host_return_to_lobby() -> void:
	game_state = "lobby"
	%Lobby.show()
	for child in $Players.get_children():
		child.queue_free()
	_return_to_lobby.rpc.call_deferred()


@rpc("reliable")
func _on_game_started(players: Dictionary, selected_map: int, is_shared_map: bool,
		snake_id: int, settings: Dictionary, spectating: bool = false) -> void:
	Globals.settings = settings
	_button_continue.hide()
	
	# Position opponents
	var num = $Players.get_child_count()
	var opp_scale = min(MAX_OPPONENT_GAME_SCALE, 0.9 / (num - 1))
	var gap = GAME_SIZE.y / (num - 1)
	var offset = 0
	var spectate_large = spectating
	for child in $Players.get_children():
		#print(multiplayer.get_unique_id(), " ", child.name)
		var id = int(str(child.name))
		child.set_color(players[id].color)
		
		if id == multiplayer.get_unique_id(): # Self
			child.set_map.call_deferred(selected_map, snake_id, is_shared_map)
			child.food_eaten.connect(_on_food_eaten)
			child.died.connect(_on_snake_died)
			if is_shared_map:
				child.moving_to.connect(_on_game_moving_to)
				#child.reversed_direction.connect(_on_game_reversed_direction)
			_game = child
		
		else: # Opponent
			child.set_map.call_deferred(selected_map, snake_id, is_shared_map, !is_shared_map or spectate_large)
			if !is_shared_map and !spectate_large:
				child.scale = Vector2(opp_scale, opp_scale)
				child.position = Vector2(OPPONENT_GAME_X, offset)
			if !is_shared_map:
				var box = HBoxContainer.new()
				box.alignment = BoxContainer.ALIGNMENT_CENTER
				if spectate_large:
					child.position.y -= 24
					box.custom_minimum_size.x = GAME_SIZE.x
					box.position = Vector2(0, GAME_SIZE.y)
				else:
					box.custom_minimum_size.x = GAME_SIZE.x * opp_scale
					box.position = Vector2(OPPONENT_GAME_X + GAME_SIZE.x * opp_scale,
							offset + GAME_SIZE.y * opp_scale * 0.5 - 24)
				$Players.add_child(box)
				var label = Label.new()
				label.set_text(players[id].name)
				box.add_child(label)
				if !spectate_large:
					offset += gap
				spectate_large = false


@rpc("reliable")
func _set_host(host: bool = true) -> void:
	_is_host = host
	if host:
		for node in get_tree().get_nodes_in_group("host_only"):
			node.show()
		if !_map_selector:
			var res = preload("res://map_selector.tscn")
			_map_selector = res.instantiate()
			_map_selector.hide()
			_map_selector.map_selected.connect(_on_map_selected)
			add_child(_map_selector)


func _on_map_selected(map: int) -> void:
	_host_set_selected_map.rpc_id(1, map)


@rpc("any_peer", "reliable")
func _host_set_selected_map(map: int) -> void:
	_selected_map = map
	_update_selected_map.rpc(map)


@rpc("reliable")
func _update_selected_map(map: int) -> void:
	%MapCard.set_map(map)


func _on_food_eaten() -> void:
	_on_player_ate_food.rpc_id(1)


@rpc("any_peer", "reliable")
func _on_player_ate_food() -> void:
	var player = multiplayer.get_remote_sender_id()
	if _snakes_alive == 1:
			_increase_speed.rpc_id(player, Globals.settings.speed_increase)
	else: for id in _players:
		if id != player and _players[id].alive:
			_increase_speed.rpc_id(id, float(Globals.settings.speed_increase) / (_snakes_alive - 1))


@rpc("reliable")
func _increase_speed(amount: float) -> void:
	_game.current_speed += amount


func _on_game_moving_to(cells: Array[Vector2i], speed: float) -> void:
	_on_player_moving_to.rpc_id(1, cells, speed)


@rpc("any_peer", "reliable")
func _on_player_moving_to(cells: Array[Vector2i], speed: float) -> void:
	var player = multiplayer.get_remote_sender_id()
	print(player, " ", cells[0])
	_players[player].tick = Time.get_ticks_msec()
	_players[player].snake_cells = cells
	_players[player].speed = speed
	var pos = _players[player].snake_cells[0]
	var direction = _players[player].snake_cells[0] - _players[player].snake_cells[1]
	for id in _players:
		if player == id or "snake_cells" not in _players[id]:
			continue
		
		if pos == _players[id].snake_cells[0]: # Colliding into a snake's head
			if _players[id].alive:
				var time_passed = (Time.get_ticks_msec() - _players[id].tick) * .001
				var move_progress = _players[player].speed * time_passed / _cell_size
				var opp_dir = _players[id].snake_cells[0] - _players[id].snake_cells[1]
				var crash_dist = (1.0 - move_progress) * 0.5 * speed / _players[id].speed
				_set_crashing.rpc_id(player, crash_dist + 0.05)
				_players[player].snake_cells.pop_front()
			else:
				_set_crashing.rpc_id(player, 0.5)
				_players[player].snake_cells.pop_front()
				_players[player].alive = false
		
		elif pos in _players[id].snake_cells.slice(0, -1): # Colliding into the side of a snake
			_set_crashing.rpc_id(player, 0.5)
			_players[player].snake_cells.pop_front()
	
	if _is_shared_map and _shared_food_pos == pos:
		_grow_snake.rpc_id(player)
		_host_move_shared_food()


func _host_move_shared_food() -> void:
	var snake_cells = []
	for player in _players:
		snake_cells.append_array(_players[player].snake_cells)
	_shared_food_pos = await Game.move_food(_tilemap, _grid_size, snake_cells)
	_move_shared_food.rpc(_shared_food_pos)


@rpc("reliable")
func _move_shared_food(pos: Vector2i) -> void:
	_game.move_shared_food(pos)


@rpc("reliable")
func _grow_snake() -> void:
	_game.grow_snake()


@rpc("reliable")
func _set_crashing(crash_dist: float = 0.3) -> void:
	_game.set_crashing(crash_dist)


func _on_snake_died() -> void:
	_on_player_died.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _on_player_died() -> void:
	var player = multiplayer.get_remote_sender_id()
	_players[player].alive = false
	_snakes_alive -= 1
	if _snakes_alive < 2:
		if !_game_ended:
			_game_ended = true
			# If remaining players die within 0.1 seconds of one another,
			# consider it a tie
			await get_tree().create_timer(0.1).timeout
			_end_game.rpc()
			for id in _players:
				if _players[id].alive:
					_show_winner.rpc(id, _players[id].name)
					_players[id].wins += 1
					var wins_label = _players[id].player_list_node.get_node("%LabelWins")
					wins_label.set_text("Wins: %d" % _players[id].wins)
					return
			if _num_snakes > 1:
				_show_winner.rpc(-1, "")


@rpc("reliable")
func _end_game() -> void:
	if _game:
		_game.paused = true
	if _is_host:
		_button_continue.show()
		_button_continue.text = "Continue"
		
		
@rpc("reliable")
func _show_winner(winner_id: int, winner_name: String) -> void:
	%LabelWinner.show()
	if winner_id == -1:
		%LabelWinner.set_text("DRAW")
	elif winner_id == multiplayer.get_unique_id():
		%LabelWinner.set_text("YOU WON!")
	else:
		%LabelWinner.set_text(winner_name + " won")


@rpc("call_local", "reliable")
func _return_to_lobby() -> void:
	%LabelWinner.hide()
	for child in $Players.get_children():
		child.queue_free()
	if _is_host:
		_button_continue.set_text("Start Game")


func _return_to_menu() -> void:
	#game_state = "menu"
	#%YouWon.hide()
	#%Lobby.hide()
	#%MainMenu.show()
	#_button_continue.hide()
	#for child in $Players.get_children():
		#child.queue_free()
	get_tree().reload_current_scene()


func _on_button_change_map_pressed() -> void:
	if !_map_selector:
		return
	_map_selector.show()


func _on_setting_value_changed(new_value: Variant, setting: String) -> void:
	_host_change_setting.rpc_id(1, new_value, setting)


@rpc("any_peer", "reliable")
func _host_change_setting(new_value: Variant, setting: String) -> void:
	assert(_players[multiplayer.get_remote_sender_id()].host)
	_settings[setting] = new_value
	_setting_nodes[setting].set_value(new_value)


func _on_server_disconnected() -> void:
	_return_to_menu()
