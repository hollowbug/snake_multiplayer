extends Node

const PORT = 15255

const MAPS = [
	preload("res://maps/map_00.tscn"),
	preload("res://maps/map_01.tscn"),
]


var settings = {
	snake_speed = 200,
	speed_increase = 2,
	allow_reverse = true,
	reverse_cooldown = 30,
}
