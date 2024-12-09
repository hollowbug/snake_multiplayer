extends Node

const PORT = 15255

const MAPS = [
	{
		type = "small",
		scene = preload("res://maps/map_00.tscn"),
	},
	{
		type = "small",
		scene = preload("res://maps/map_01.tscn"),
	},
	{
		type = "large",
		scene = preload("res://maps/map_02_large.tscn"),
	},
]


var settings = {
	snake_speed = 200,
	speed_increase = 2,
	allow_reverse = true,
	reverse_cooldown = 30,
}


func wait_for_next_frame() -> void:
	await get_tree().process_frame
