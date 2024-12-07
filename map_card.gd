extends PanelContainer

@onready var _map := %SelectedMap/Map00

func set_map(map: int) -> void:
	_map.queue_free()
	_map = Globals.MAPS[map].scene.instantiate()
	%SelectedMap.add_child(_map)
	%SelectedMap.size_2d_override = _map.rect_size
	var container = $VBoxContainer/SubViewportContainer
	var ratio = _map.rect_size.x / _map.rect_size.y
	container.custom_minimum_size.y = container.custom_minimum_size.x / ratio
