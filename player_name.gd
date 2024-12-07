extends HBoxContainer

func _ready() -> void:
	SignalBus.player_added_to_list.emit(self)
