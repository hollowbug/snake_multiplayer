extends Node

@export var SPEED_INCREASE := 2.0

const PLAYER_NAME_LABEL = preload("res://player_name.tscn")
#const PLAYER = preload("res://player.tscn")
const GAME = preload("res://game.tscn")
const GAME_SIZE := Vector2(960, 960)
const OPPONENT_GAME_SCALE = 0.3
const OPPONENT_GAME_X := 1100

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
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if game_state == "menu":
			get_tree().quit()
		else:
			multiplayer.multiplayer_peer.close()
			_return_to_menu()


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
	var client = ENetMultiplayerPeer.new()
	var err = client.create_client(ip, port)
	if err:
		print("Unable to join server")
		return
	print("Joined server")
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
	_players[id] = { name = name_, color = Color.WHITE, alive = false, host = false }
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
	_player_name = %PlayerName.text.left(20)
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
	_snakes_alive = _players.keys().size()
	for player in _players:
		_players[player].alive = true
		var game = GAME.instantiate()
		game.name = str(player)
		#game.player = player
		$Players.add_child(game, true)
	_on_game_started.rpc(_players, _selected_map, _settings)


@rpc("any_peer", "reliable")
func _host_return_to_lobby() -> void:
	game_state = "lobby"
	%Lobby.show()
	for child in $Players.get_children():
		child.queue_free()
	_return_to_lobby.rpc()


@rpc("reliable")
func _on_game_started(players: Dictionary, selected_map: int, settings: Dictionary) -> void:
	Globals.settings = settings
	_button_continue.hide()
	# Position opponents
	var num = $Players.get_child_count()
	var gap = GAME_SIZE.y / num
	var offset = 0.0
	for child in $Players.get_children():
		child.set_map(selected_map)
		#print(multiplayer.get_unique_id(), " ", child.name)
		var id = int(str(child.name))
		child.set_color(players[id].color)
		if id == multiplayer.get_unique_id(): # Self
		#if child.player == multiplayer.get_unique_id(): # Self
			child.food_eaten.connect(_on_food_eaten)
			child.died.connect(_on_snake_died)
			_game = child
		else: # Opponent
			child.scale = Vector2(OPPONENT_GAME_SCALE, OPPONENT_GAME_SCALE)
			var y = offset * gap
			child.position = Vector2(OPPONENT_GAME_X, y)
			#var label = PLAYER_NAME_LABEL.instantiate()
			#label.set_text(players[id].name)
			#label.position = Vector2(OPPONENT_GAME_X, y + gap / 2)
			#add_child(label)
			offset += 1.0


func _on_food_eaten() -> void:
	_on_player_ate_food.rpc_id(1)


@rpc("any_peer", "reliable")
func _on_player_ate_food() -> void:
	var player = multiplayer.get_remote_sender_id()
	for id in _players:
		if id != player and _players[id].alive:
			_increase_speed.rpc_id(id, SPEED_INCREASE / (_snakes_alive - 1))


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
