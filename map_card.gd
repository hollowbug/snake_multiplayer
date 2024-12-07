extends PanelContainer

@onready var _map := %SelectedMap/Map00

func set_map(map: int) -> void:
	_map.queue_free()
	_map = Globals.MAPS[map].instantiate()
	%SelectedMap.add_child(_map)
