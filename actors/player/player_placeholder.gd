extends Node2D
## Stand-in drawing for Bloob until the pixel-art SpriteFrames exist. Delete this node then.
## Shadow on the feet, a cream body, eyes toward the facing side, and a ring at the aim point
## (the prototype draws the same aim ring on the ground).

const BODY := Color(0.94, 0.9, 0.8)
const INK := Color(0.1, 0.08, 0.12)
const SHADOW := Color(0, 0, 0, 0.35)
const AIM := Color(0.85, 0.7, 0.4, 0.55)

@onready var player: Player = get_parent()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 13.0, SHADOW)
	draw_set_transform(Vector2.ZERO)

	var centre := Vector2(0, -15)
	draw_circle(centre, 14.0, BODY)
	draw_arc(centre, 14.0, 0.0, TAU, 32, INK, 1.5)
	var f := float(player.facing)
	draw_circle(centre + Vector2(3 * f, -2), 1.8, INK)
	draw_circle(centre + Vector2(9 * f, -2), 1.8, INK)

	# the aim ring, in world space
	var aim := to_local(player.aim_position)
	draw_arc(aim, 7.0, 0.0, TAU, 20, AIM, 1.5)
