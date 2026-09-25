class_name GameCamera
extends Camera2D
## Follows a target with a little lead toward the aim, like the prototype (src/main.ts):
##   k = 1 - 0.002^dt;  target = player + (aim - player) * 0.1;  cam += (target - cam) * k
## Moves on the physics tick, like the Player, so physics interpolation smooths both the same way
## (the scene sets Process Callback = Physics).
## Room clamping comes later with rooms (use Camera2D limit_* then).

## Who to follow.
@export var target: Player
## How far the camera leans toward the aim: 0 = none. Prototype: 0.1.
@export var aim_lead := 0.1
## Share of the distance still left after one second of following. Prototype: 0.002.
@export_range(0.0001, 1.0, 0.0001) var follow_remaining_per_second := 0.002


func _ready() -> void:
	if target:
		global_position = target.global_position
		reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if not target:
		return
	var goal: Vector2 = target.global_position + (target.aim_position - target.global_position) * aim_lead
	var k := 1.0 - pow(follow_remaining_per_second, delta)
	global_position += (goal - global_position) * k
