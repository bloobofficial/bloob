class_name InputFrame
extends RefCounted
## What Bloob is asked to do this tick (prototype: core/input.ts InputFrame).
## Sampled from the Input Map once per physics tick (see sample()); passage walk-outs and the
## automated tests build frames directly.

var move := Vector2.ZERO   ## -1..1 per axis
var aim := Vector2.ZERO    ## ground point
var fire := false          ## goo spit (held)
var dodge := false         ## edge
var atk := false           ## pressed or held
var jump := false          ## edge
var heal := false          ## edge
var sk1 := false           ## edge
var sk2 := false           ## edge
var use := false           ## edge


func copy_from(o: InputFrame) -> void:
	move = o.move; aim = o.aim; fire = o.fire; dodge = o.dodge; atk = o.atk
	jump = o.jump; heal = o.heal; sk1 = o.sk1; sk2 = o.sk2; use = o.use


## Read the Input Map. `aim_ground` is where the mouse (or right stick) points on the ground.
static func sample(aim_ground: Vector2) -> InputFrame:
	var f := InputFrame.new()
	# digital like the prototype: each axis -1, 0 or 1 (the player normalizes diagonals)
	var mx := Input.get_axis(&"move_left", &"move_right")
	var my := Input.get_axis(&"move_up", &"move_down")
	f.move = Vector2(signf(mx) if absf(mx) > 0.35 else 0.0, signf(my) if absf(my) > 0.35 else 0.0)
	f.aim = aim_ground
	f.fire = Input.is_action_pressed(&"spit")
	f.dodge = Input.is_action_just_pressed(&"dodge")
	f.atk = Input.is_action_pressed(&"attack")
	f.jump = Input.is_action_just_pressed(&"jump")
	f.heal = Input.is_action_just_pressed(&"heal")
	f.sk1 = Input.is_action_just_pressed(&"skill_1")
	f.sk2 = Input.is_action_just_pressed(&"skill_2")
	f.use = Input.is_action_just_pressed(&"use")
	return f
