class_name Player
extends CharacterBody2D
## Bloob. Stage 1 of the port: ground movement only.
##
## Ported from mayhem-engine v0.10: src/sim/player.ts (velocity) and src/main.ts (which clip
## plays, which way Bloob faces). The prototype counts world units per 60 Hz tick; here one
## world unit = one pixel and speeds are per second (prototype value x 60).
##
## The node's origin is Bloob's feet (the prototype's ground point). The collision circle is
## the footprint, centred on the feet.
##
## Later stages hook in here: dodge, jump / height, swings, skills, flask, damage.

signal state_changed(previous: State, current: State)

enum State { IDLE, RUN }

const TICK_RATE := 60.0
## animation names in the SpriteFrames resource, by state (prototype clip names)
const ANIMATIONS := { State.IDLE: &"idle", State.RUN: &"run" }

## Run speed. Prototype: SPEED = 3.3 units per tick.
@export var run_speed := 3.3 * TICK_RATE
## Gear / buff multiplier. Prototype: profile.speedMul x rally x weapon moveMul.
@export var speed_mul := 1.0
## Above this speed the run clip plays. Prototype: 0.4 units per tick.
@export var run_anim_threshold := 0.4 * TICK_RATE

var state := State.IDLE
## -1..1 per axis; diagonals are normalized (the prototype scales both axes by SQRT1_2).
var move_input := Vector2.ZERO
## Last direction Bloob moved in. Later: the fallback dodge / swing direction.
var last_move_dir := Vector2.RIGHT
## Mouse position in the world. Bloob faces the aim, not the direction of travel.
var aim_position := Vector2.ZERO
## 1 = facing right, -1 = facing left.
var facing := 1
## Share of run_speed that movement input gets. Later states set it
## (prototype: drinking 0.35, diving 0.15, swinging = the weapon's swingMoveMul, casting 0).
var move_scale := 1.0

@onready var sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	aim_position = global_position + Vector2.RIGHT
	_play_animation()


func _physics_process(_delta: float) -> void:
	move_input = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if move_input != Vector2.ZERO:
		last_move_dir = move_input
	aim_position = get_global_mouse_position()

	# instant start and stop, like the prototype: no acceleration curve
	velocity = move_input * run_speed * speed_mul * move_scale
	# the prototype picks the run clip from the intended velocity, so running into a wall still runs
	var running := velocity.length() > run_anim_threshold
	move_and_slide()

	_update_facing()
	_set_state(State.RUN if running else State.IDLE)


func _update_facing() -> void:
	# prototype: facingX = aimX - x, and the sprite flips when it's negative
	facing = -1 if aim_position.x < global_position.x else 1
	sprite.flip_h = facing < 0


func _set_state(next: State) -> void:
	if next == state:
		return
	var previous := state
	state = next
	_play_animation()
	state_changed.emit(previous, next)


func _play_animation() -> void:
	var anim: StringName = ANIMATIONS[state]
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
