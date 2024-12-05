extends PanelContainer
class_name Upgrade

signal upgrade_hovered(upgrade: Upgrade)
signal upgrade_unhovered(upgrade: Upgrade)
signal upgrade_clicked(upgrade: Upgrade)

@export var upgrade_id 			: String
@export var upgrade_name 		: String
@export_multiline var upgrade_description : String
@export_enum("Default", "Percentage", "Cooldown") var mode := "Default"
@export var num_levels 			: int
@export var use_amounts 		:= true
@export var base_amount 		:= 0
@export var amount_per_level 	: int
@export var cost_per_level 		:= [0, 0, 0]
@export var leads_to: Array[NodePath] = []

var level := 0
var lines := []

func _ready() -> void:
	$VBoxContainer/Label.set_text("0/%d" % num_levels)
	var line = $Line2D
	lines.append(line)
	for i in range(leads_to.size()):
		if i != 0:
			line = line.duplicate()
			lines.append(line)
			add_child(line)
		var other = get_node(leads_to[i])
		if !other:
			continue
		line.set_point_position(1, other.position - position + other.size / 2)
		other.hide()
		line.hide()


func set_level(level_: int) -> void:
	# Unlock connected upgrades when buying first level
	if level == 0 and level_ > 0:
		for i in range(leads_to.size()):
			get_node(leads_to[i]).show()
			lines[i].show()
	
	level = level_
	$VBoxContainer/Label.set_text("%d/%d" % [level_, num_levels])
	if level == num_levels:
		self_modulate = Color.GREEN

func set_can_afford(can: bool) -> void:
	if level == num_levels:
		return
	if can:
		self_modulate = Color.WHITE
	else:
		self_modulate = Color.RED


func _on_mouse_entered() -> void:
	upgrade_hovered.emit(self)


func _on_mouse_exited() -> void:
	upgrade_unhovered.emit(self)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		upgrade_clicked.emit(self)
