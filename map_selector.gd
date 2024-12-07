extends CanvasLayer

@export var _MAP_CARD : PackedScene

signal map_selected(map: int)


func _ready() -> void:
	if !_MAP_CARD:
		return
	var small_maps = %SmallMaps
	var large_maps = %LargeMaps
	for i in range(Globals.MAPS.size()):
		var card = _MAP_CARD.instantiate()
		card.gui_input.connect(_on_map_card_gui_input.bind(i))
		if Globals.MAPS[i].type == "small":
			small_maps.add_child(card)
		else:
			large_maps.add_child(card)
		card.set_map(i)


func _on_map_card_gui_input(event: InputEvent, map: int) -> void:
	if (event is InputEventMouseButton and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT):
		print("Selecting map ", map)
		map_selected.emit(map)
		hide()
