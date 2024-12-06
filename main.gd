extends Node

@export var SPEED_INCREASE := 2.0

const PLAYER_NAME_LABEL = preload("res://player_name.tscn")
#const PLAYER = preload("res://player.tscn")
const GAME = preload("res://game.tscn")
const GAME_SIZE := Vector2(480, 480)
const OPPONENT_GAME_SCALE = 0.3
const OPPONENT_GAME_X := 500

# Host only properties
var _players := {}
var _snakes_alive : int

# Shared properties
var game_state = "menu"

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
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		%MainMenu.show()
		%Lobby.hide()
		_button_continue.hide()


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
	print("Joined server successfully")
	multiplayer.multiplayer_peer = client
	%MainMenu.hide()
	#for node in get_tree().get_nodes_in_group("host_only"):
		#node.hide()


func _update_player_list() -> void:
	for child in _player_list.get_children():
		child.queue_free()
	for player in _players:
		var label = PLAYER_NAME_LABEL.instantiate()
		label.text = _players[player].name
		_player_list.add_child(label, true)


func _on_connected() -> void:
	_register_player.rpc_id(1, multiplayer.get_unique_id(), _player_name)


@rpc("any_peer", "reliable")
func _register_player(id: int, name_: String):
	if multiplayer.get_unique_id() != 1:
		return
	print("%s joined" % name_)
	if _players.is_empty():
		_set_host.rpc_id(id)
	_players[id] = { name = name_, alive = false }
	_update_player_list()


func _on_client_disconnected(id: int) -> void:
	print("%s disconnected" % _players[id].name)
	_players.erase(id)
	_update_player_list()


func _on_button_create_game_pressed() -> void:
	_player_name = %PlayerName.text
	var port = int(%CreateGamePort.text)
	_create_server(port)


func _on_button_join_game_pressed() -> void:
	_player_name = %PlayerName.text
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
	_on_game_started.rpc(_players)


@rpc("any_peer", "reliable")
func _host_return_to_lobby() -> void:
	game_state = "lobby"
	%Lobby.show()
	for child in $Players.get_children():
		child.queue_free()
	_return_to_lobby.rpc()
	_update_player_list()


@rpc("call_local", "reliable")
func _on_game_started(players: Dictionary) -> void:
	_button_continue.hide()
	# Position opponents
	var num = $Players.get_child_count()
	var gap = GAME_SIZE.y / num
	var offset = 0.0
	for child in $Players.get_children():
		#print(multiplayer.get_unique_id(), " ", child.name)
		var id = int(str(child.name))
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
	_button_continue.show()


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
	game_state = "menu"
	%YouWon.hide()
	%Lobby.hide()
	%MainMenu.show()
	_button_continue.hide()
	for child in $Players.get_children():
		child.queue_free()


func _on_server_disconnected() -> void:
	_return_to_menu()
