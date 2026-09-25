class_name Totem
extends Node2D
## The Warden's goo totem (prototype: sim/skills.ts updateTotems): shoots the nearest enemy
## on roughly the same level every `every` ticks until its life runs out.

var world: World
var z := 0.0
var life := 720
var cd := 10
var aim := 0.0

@onready var sprite: Sprite2D = $Sprite


func setup(w: World, at: Vector2, pz: float, facing: float, lifetime: int) -> void:
	world = w
	position = at
	z = pz
	aim = facing
	life = lifetime
	cd = 10


## returns false when it has expired
func tick() -> bool:
	if world.time.frozen():
		return true
	life -= 1
	if life <= 0:
		return false
	_update_visual()
	cd -= 1
	if cd > 0:
		return true
	var skill := Content.skills[SkillData.Id.TOTEM]
	var best: Enemy = null
	var bd := skill.p("range") * skill.p("range")
	for e: Enemy in world.enemies:
		if absf(e.z - z) > 40.0:
			continue
		var d2 := e.position.distance_squared_to(position)
		if d2 < bd:
			bd = d2
			best = e
	if best == null:
		cd = 6
		return true
	cd = int(skill.p("every"))
	var dir := (best.position - position).normalized()
	aim = dir.angle()
	world.projectiles.spawn(position + dir * 10.0, z + 22.0, dir * 9.0, 50, skill.p("damage") * world.player.out_mul(), Projectiles.OWNER_TOTEM)
	return true


func _update_visual() -> void:
	sprite.texture = Art.frame("totem.idle.%d" % (1 if cd > 11 else 0))
	sprite.flip_h = cos(aim) < 0.0
	sprite.position = Vector2(0, View.lift(z))
	sprite.scale = Vector2(Art.world_scale(0.5), Art.world_scale(0.5) * View.upright())
	queue_redraw()


func _draw() -> void:
	Draw25.ground_ellipse(self, Vector2(0, View.lift(z)), 10.0 * 1.25, 10.0 * 0.8, Color(0, 0, 0, 0.35))
	if life < 120 and (life >> 3) & 1:
		Draw25.ground_ring(self, Vector2(0, View.lift(z)), 14.0, Color(1, 0.85, 0.5, 0.6))
