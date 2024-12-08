extends Node

@export var SPEED_INCREASE := 2.0

const PLAYER_NAME_LABEL = preload("res://player_name.tscn")
#const PLAYER = preload("res://player.tscn")
const GAME = preload("res://game.tscn")
const GAME_SIZE := Vector2(960, 960)
const MAX_OPPONENT_GAME_SCALE = 0.3
const OPPONENT_GAME_X := 1100
const SHARED_GAME_SIZE := Vector2(1280, 960)
const SHARED_GAME_X := 580

# Host only properties
var _players := {}
var _snakes_alive : int
var _map_selector : CanvasLayer
var _selected_map := 0
@onready var _setting_nodes := {
	snake_speed = %SettingContainer/Setting,
	speed_increase = %SettingContainer/Setting2,
	allow_reverse = %SettingContainer/Setting3,
	reverse_cooldown = %SettingContainer/Setting4,
}

# Shared properties
var game_state = "menu"
var _settings: Dictionary = Globals.settings

# Client properties
var _player_name := "Player"
var _is_host := false
var _game : Node2D
@onready var _player_list = %PlayerList
@onready var _button_continue = %ButtonContinue

func _ready() -> void:
	if OS.has_feature("dedicated_server"):
		var port = OS.get_environment("PORT")
		if port:
			_create_server(int(port))
		else:
			_create_server(20527)
	
	else: # Client
		if OS.has_feature("editor"):
			%JoinGameIP.set_text("192.168.112.119")
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
				print("F1 pressed")
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
	%Lobby.hide()
	var players = _players.keys()
	var is_shared_map = (players.size() > 1
			and Globals.MAPS[_selected_map].type == "large")
	_snakes_alive = players.size()
	
	for player in _players:
		_players[player].alive = true
		var game = GAME.instantiate()
		game.name = str(player)
		#game.player = player
		$Players.add_child(game, true)
		print("is_shared_map = ", is_shared_map)
	for i in range(players.size()):
		var snake_idx = i if is_shared_map else 0
		_on_game_started.rpc_id(players[i], _players, _selected_map, snake_idx, _settings)


@rpc("any_peer", "reliable")
func _host_return_to_lobby() -> void:
	game_state = "lobby"
	%Lobby.show()
	for child in $Players.get_children():
		child.queue_free()
	_return_to_lobby.rpc.call_deferred()


@rpc("reliable")
func _on_game_started(players: Dictionary, selected_map: int,
		snake_id: int, settings: Dictionary) -> void:
	Globals.settings = settings
	_button_continue.hide()
	
	# Position opponents
	var num = $Players.get_child_count()
	var opp_scale = min(MAX_OPPONENT_GAME_SCALE, 0.9 / (num - 1))
	var gap = GAME_SIZE.y / (num - 1)
	var offset = 0
	for child in $Players.get_children():
		#print(multiplayer.get_unique_id(), " ", child.name)
		var id = int(str(child.name))
		var is_shared_map = Globals.MAPS[selected_map].type == "large"
		child.set_color(players[id].color)
		
		if id == multiplayer.get_unique_id(): # Self
			child.set_map.call_deferred(selected_map, snake_id)
			child.food_eaten.connect(_on_food_eaten)
			child.died.connect(_on_snake_died)
			if is_shared_map:
				child.moving_to.connect(_on_game_moving_to.bind(id))
			_game = child
		
		else: # Opponent
			child.set_map.call_deferred(selected_map, snake_id, !is_shared_map)
			if !is_shared_map:
				child.scale = Vector2(opp_scale, opp_scale)
				child.position = Vector2(OPPONENT_GAME_X, offset)
				var box = HBoxContainer.new()
				box.alignment = BoxContainer.ALIGNMENT_CENTER
				box.custom_minimum_size.x = GAME_SIZE.x * opp_scale
				box.position = Vector2(OPPONENT_GAME_X + GAME_SIZE.x * opp_scale,
						offset + GAME_SIZE.y * opp_scale * 0.5 - 24)
				$Players.add_child(box)
				var label = Label.new()
				label.set_text(players[id].name)
				box.add_child(label)
				offset += gap


func _on_food_eaten() -> void:
	_on_player_ate_food.rpc_id(1)


@rpc("any_peer", "reliable")
func _on_player_ate_food() -> void:
	var player = multiplayer.get_remote_sender_id()
	for id in _players:
		if id != player and _players[id].alive:
			_increase_speed.rpc_id(id, float(Globals.settings.speed_increase) / (_snakes_alive - 1))


@rpc("reliable")
func _increase_speed(amount: float) -> void:
	_game.current_speed += amount


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


func _on_game_moving_to(pos: Vector2i, cells: Array[Vector2i], player: int) -> void:
	_on_player_moving_to.rpc_id(1, pos, cells, player)


@rpc("any_peer", "reliable")
func _on_player_moving_to(pos: Vector2i, cells: Array[Vector2i], player: int) -> void:
	for id in _players:
		if player == id or "snake_cells" not in _players[id]:
			continue
		if pos in _players[id].snake_cells:
			_die.rpc_id(player)
	_players[player].snake_cells = cells


@rpc("reliable")
func _die() -> void:
	_game.die()


func _on_snake_died() -> void:
	_on_player_died.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _on_player_died() -> void:
	var player = multiplayer.get_remote_sender_id()
	_players[player].alive = false
	_snakes_alive -= 1
	if _snakes_alive == 1 or _players.keys().size() == 1:
		_game_ended.rpc()
		# If remaining players die within 0.1 seconds of one another,
		# consider it a tie
		await get_tree().create_timer(0.1).timeout
		_check_winner.call_deferred()


func _check_winner() -> void:
	for id in _players:
		if _players[id].alive:
			_on_game_won.rpc_id(id)
			_players[id].wins += 1
			var wins_label = _players[id].player_list_node.get_node("%LabelWins")
			wins_label.set_text("Wins: %d" % _players[id].wins)


@rpc("reliable")
func _game_ended() -> void:
	if _is_host:
		_button_continue.show()
		_button_continue.text = "Continue"


@rpc("authority", "call_local", "reliable")
func _on_game_won() -> void:
	%YouWon.show()
	_game.paused = true


@rpc("authority", "call_local", "reliable")
func _return_to_lobby() -> void:
	%YouWon.hide()
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
