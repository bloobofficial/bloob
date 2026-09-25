class_name Meter
extends Control
## A HUD bar (prototype: #hp / #mp / #xp): the fill, plus optional damage-lag and
## heal-preview strips drawn behind it.

@export var fill_color := Color("#e0453a")
@export var lag_color := Color(1, 0.85, 0.75, 0.55)
@export var heal_color := Color(0.5, 0.95, 0.55, 0.45)
@export var track_color := Color(0, 0, 0, 0.45)

var value := 1.0
var lag := 1.0
var heal := 0.0
var pulse := false


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, track_color)
	if heal > value:
		draw_rect(Rect2(0, 0, size.x * clampf(heal, 0, 1), size.y), heal_color)
	if lag > value:
		draw_rect(Rect2(0, 0, size.x * clampf(lag, 0, 1), size.y), lag_color)
	var c := fill_color
	if pulse:
		c = c.lerp(Color.WHITE, 0.25 + 0.25 * sin(Time.get_ticks_msec() * 0.01))
	draw_rect(Rect2(0, 0, size.x * clampf(value, 0, 1), size.y), c)
	draw_rect(r, Color(1, 1, 1, 0.12), false, 1.0)
