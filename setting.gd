extends HBoxContainer


signal value_changed(new_value)


@export_enum("int", "bool", "String") var type := "int"
@export_enum("None", "Seconds") var units := "None"
@export var values 		:= []
@export var min_value	:= 0
@export var max_value	:= 0
@export var step		:= 0


@onready var label := $Value
var value


func _ready() -> void:
	if type == "int":
		value = int(label.text)
	elif type == "bool":
		value = true if label.text == "Yes" else false
	elif type == "String":
		value = label.text


func set_value(value_) -> void:
	value = value_
	if type == "int" and units == "Seconds":
		label.set_text(str(value) + "s")
	elif type == "int":
		label.set_text(str(value))
	elif type == "bool":
		label.set_text("Yes" if value else "No")


func _on_left_pressed() -> void:
	var new_value
	if type == "int":
		new_value = value - step
		if new_value < min_value:
			new_value = max_value
	elif type == "bool":
		new_value = !value
	value_changed.emit(new_value)


func _on_right_pressed() -> void:
	var new_value
	if type == "int":
		new_value = value + step
		if new_value > max_value:
			new_value = min_value
	elif type == "bool":
		new_value = !value
	value_changed.emit(new_value)
