class_name GameCamera
extends Camera2D
## The game camera (prototype: src/main.ts camera follow + render/camera.ts).
##  - follows Bloob with a little lead toward the aim:  k = 1 - 0.002^dt,
##    target = bloob + (aim - bloob) * 0.1, cam += (target - cam) * k
##  - kept inside the room plus a margin of scenery, so the view never slides off the world
##  - follows height (70% as fast) so climbing a plateau lifts the view
##  - the 2.5D tilt: zoom is squashed vertically by sin(pitch) (see View)
##  - screen shake from the effects layer
## Moves on the physics tick so physics interpolation smooths it together with Bloob.

var world: World
var cam := Vector2.ZERO       ## ground-plane target
var cam_z := 0.0
@export var aim_lead := 0.1
@export var follow_remaining_per_second := 0.002


func snap() -> void:
	if world == null:
		return
	cam = _clamp(world.player.position)
	cam_z = world.player.z
	_apply()
	reset_smoothing()


func _physics_process(delta: float) -> void:
	if world == null:
		return
	var p := world.player
	var k := 1.0 - pow(follow_remaining_per_second, delta)
	var target := _clamp(p.position + (p.aim - p.position) * aim_lead)
	cam += (target - cam) * k
	var g := world.map.ground_at(p.position.x, p.position.y)
	var tz := p.z if g == Tuning.VOID_H else minf(p.z, g + 8.0)
	cam_z += (tz - cam_z) * k * 0.7
	_apply()


func _apply() -> void:
	var z := View.zoom_for(get_viewport_rect().size)
	zoom = Vector2(z, z * View.ground_k)
	var shake := world.fx.shake if world.fx else Vector2.ZERO
	global_position = Vector2(cam.x + shake.x, cam.y + shake.y + View.lift(cam_z))


## half-extents of the view on the ground: [half width, half depth]
func _extents() -> Vector2:
	var vs := get_viewport_rect().size
	var z := View.zoom_for(vs)
	return Vector2(vs.x / z / 2.0, vs.y / (z * View.ground_k) / 2.0)


func _clamp(p: Vector2) -> Vector2:
	var m := world.map
	var e := _extents()
	var C := float(Tuning.CELL)
	var min_x := -4 * C + e.x
	var max_x := m.px_w + 4 * C - e.x
	var min_y := -4 * C + e.y
	var max_y := m.px_h + 2 * C - e.y
	var cx := m.px_w / 2.0 if min_x > max_x else clampf(p.x, min_x, max_x)
	var cy := (min_y + max_y) / 2.0 if min_y > max_y else clampf(p.y, min_y, max_y)
	return Vector2(cx, cy)
