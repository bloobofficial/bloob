class_name EnemyVisual
extends Node2D
## How a monster looks (prototype: src/main.ts drawWorld "enemies" + drawIntent).
## Frames: walk (4), windup, attack, hurt per kind. On top: the hit flash, champion aura,
## hex / squad rings, the windup's closing ring, the attack's danger zone on the ground
## (tracking Bloob until the aim locks), the "!" tell, and a health arc at the feet.

const FLASH_SHADER := preload("res://effects/flash.gdshader")

var enemy: Enemy

@onready var screen: Node2D = $Screen
@onready var sprite: Sprite2D = $Screen/Sprite


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = FLASH_SHADER
	sprite.material = mat


func _process(_delta: float) -> void:
	if enemy == null or enemy.world == null:
		return
	_update()
	queue_redraw()


func _update() -> void:
	var e := enemy
	var d := e.data
	var tick := e.world.tick_n
	var st := e.state
	var p := e.world.player
	var fname := "%s.walk.%d" % [d.id, ((tick >> 3) + e.get_instance_id()) & 3]
	var tint := Color(1, 1, 1)
	var flash := 0.0
	var sw := 1.0
	var sh := 1.0
	if st == Enemy.St.WINDUP:
		fname = d.id + ".windup.0"
		var t := 1.0 - float(e.timer) / maxf(1.0, e.wtot)
		flash = (sin(t * t * 40.0) * 0.5 + 0.5) * 0.55
		sw = 1.0 + t * 0.08
		sh = 1.0 - t * 0.06
	elif st == Enemy.St.LUNGE or (st == Enemy.St.COMMIT and e.position.distance_squared_to(p.position) < 70.0 * 70.0):
		fname = d.id + ".attack.0"
		sw = 1.1
		sh = 0.94
	elif st == Enemy.St.STAGGER:
		fname = d.id + ".hurt.0"
		tint = Color(0.75, 0.88, 1.0)
	elif st == Enemy.St.RECOVER:
		tint = Color(0.6, 0.6, 0.6)
	if e.flash > 0 or e.freeze > 0:
		fname = d.id + ".hurt.0"
		flash = 0.85
		sw = 1.14
		sh = 0.88
	if e.hex_t > 0:
		tint = Color(tint.r * 0.85, tint.g * 0.7, minf(1.0, tint.b * 1.15))
	# spawn: rise up out of the ground
	if e.age < 16:
		var ta := e.age / 16.0
		sh *= 0.25 + 0.75 * ta
		sw *= 1.25 - 0.25 * ta
	var face := e.lunge_dir.x if st == Enemy.St.LUNGE else (e.vel.x if absf(e.vel.x) > 0.2 else p.position.x - e.position.x)
	var hover := d.hover + sin(tick * 0.08 + e.get_instance_id()) * 3.0 if d.hover > 0.0 else 0.0
	screen.position = Vector2(0, View.lift(e.z + hover))
	screen.scale = Vector2(1.0, View.upright())
	sprite.texture = Art.frame(fname)
	sprite.flip_h = face < 0.0
	var size := d.sprite_scale * e.size
	sprite.scale = Vector2(size * sw, size * sh)
	sprite.offset = Vector2(0, -(0.5 - d.anchor) * 96.0)
	var mat := sprite.material as ShaderMaterial
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("flash", flash)


func _draw() -> void:
	var e := enemy
	if e == null or e.world == null:
		return
	var map := e.world.map
	var tick := e.world.tick_n
	var g := map.ground_at(e.position.x, e.position.y)
	var gz := e.z if g == Tuning.VOID_H else float(g)
	var feet := Vector2(0, View.lift(gz))
	if g != Tuning.VOID_H:
		var air := maxf(0.0, e.z - g)
		var sr := e.radius * 1.35 * maxf(0.4, 1.0 - air / 120.0)
		Draw25.ground_ellipse(self, feet, sr * 1.25, sr * 0.8, Color(0, 0, 0, 0.38))
	if e.squad >= 0 and e.squad < e.world.squads.size():
		var sqs: int = e.world.squads[e.squad].state
		var c := Color(1, 0.45, 0.7) if sqs == 1 else (Color(0.6, 0.85, 1) if sqs == 2 else Color(0.85, 0.8, 0.7))
		Draw25.ground_ring(self, feet, e.radius + 5, Color(c, 0.45), 1.5)
	if e.state == Enemy.St.WINDUP:
		var t := 1.0 - float(e.timer) / maxf(1.0, e.wtot)
		# closing ring = the dodge timing indicator
		Draw25.ground_ring(self, feet, e.radius + 8 + (1.0 - t) * 46.0, Color(1, 0.35, 0.3, 0.5 + t * 0.5), 2.0)
		if e.atk != null:
			_draw_intent(feet, gz, t, e.timer <= e.wtot * Tuning.AIM_LOCK)
		# "!" over its head
		var locked := e.timer <= e.wtot * Tuning.AIM_LOCK
		var ic := Color(1, 0.3, 0.2) if locked else Color(1, 0.82, 0.3)
		var head := e.z + e.data.sprite_scale * 96.0 * e.size * 0.95 + 8.0 + sin(tick * 0.5) * 1.5
		var hp := Vector2(0, View.lift(head))
		draw_set_transform(hp, 0, Vector2(1, View.upright()))
		draw_rect(Rect2(-2, -12, 4, 11), Color(ic, 0.95))
		draw_circle(Vector2(0, 4), 2.6, Color(ic, 0.95))
		draw_set_transform(Vector2.ZERO)
	elif e.state == Enemy.St.LUNGE and e.atk != null and e.atk.kind == AttackData.Kind.STRIKE:
		# the swipe itself: a bright slash across the wedge
		var ang := e.lunge_dir.angle()
		var rr := (e.atk.range + 6.0) / 0.9
		Draw25.ground_arc_band(self, feet, rr * 0.86, rr, ang - e.atk.arc, ang + e.atk.arc, Color(1, 0.45, 0.35, 0.8))
	if e.hex_t > 0:
		Draw25.ground_ring(self, feet, e.radius + 3, Color(0.75, 0.45, 1, 0.55), 1.5)
	if e.champ:
		var c := Tuning.first_affix_color(e.affix)
		var pulse := 0.5 + 0.5 * sin(tick * 0.15 + e.get_instance_id())
		Draw25.ground_ring(self, feet, e.radius + 7 + pulse * 3, Color(c, 0.8), 2.0)
		Draw25.upright_circle(self, Vector2(0, View.lift(e.z + e.radius)), e.radius * 1.5, Color(c, 0.1))
	# health: an arc at the feet that shrinks as it takes damage (skipped for hordes)
	if e.hp < e.max_hp and e.world.enemies.size() <= 40:
		var frac := maxf(0.0, e.hp / maxf(1.0, e.max_hp))
		var hc := Tuning.first_affix_color(e.affix) if e.champ else Color(1, 0.42, 0.32)
		Draw25.ground_ring(self, feet, e.radius + 12, Color(0, 0, 0, 0.3), 2.0)
		var span := maxf(0.06, frac * PI)
		draw_arc(feet, e.radius + 12, PI / 2 - span, PI / 2 + span, 24, Color(hc, 0.9), 2.5)
	if e.world.debug_hitboxes:
		Draw25.ground_ring(self, feet, e.radius, Color(0.3, 1, 0.5, 0.9), 1.5)
	if e.world.debug_states:
		var sc := [Color(0.7, 0.7, 0.75), Color(0.7, 0.5, 1), Color(0.3, 0.85, 0.8), Color(1, 0.45, 0.7), Color(1, 0.25, 0.2), Color(1, 0.6, 0.2), Color(0.35, 0.3, 0.4), Color(0.5, 0.75, 1), Color(0.9, 0.9, 0.5)]
		Draw25.ground_ring(self, feet, e.radius + 2, Color(sc[e.state], 0.95), 2.0)


## the attack's danger zone on the ground (t = windup progress)
func _draw_intent(feet: Vector2, gz: float, t: float, locked: bool) -> void:
	var e := enemy
	var def := e.atk
	var ang := e.lunge_dir.angle()
	var a := 0.12 + 0.3 * t
	var c := Color(1, 0.2, 0.15) if locked else Color(1, 0.55, 0.25)
	match def.kind:
		AttackData.Kind.STRIKE:
			var r := (def.range + 6.0) / 1.2
			Draw25.ground_arc_band(self, feet, 0.0, r, ang - def.arc, ang + def.arc, Color(c, a))
			Draw25.ground_arc_band(self, feet, r * 1.2, r * 1.25, ang - def.arc, ang + def.arc, Color(c, 0.55 if locked else 0.25))
		AttackData.Kind.DASH:
			var L := def.speed * def.active * 0.95
			var w := e.radius + 4.0
			var n := Vector2(-e.lunge_dir.y, e.lunge_dir.x) * w
			var pts := PackedVector2Array([feet + n, feet + e.lunge_dir * L + n, feet + e.lunge_dir * L - n, feet - n])
			draw_colored_polygon(pts, Color(c, a))
			if locked:
				draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(c, 0.35), 1.5)
		AttackData.Kind.SHOOT:
			for k in range(1, 7):
				Draw25.ground_circle(self, feet + e.lunge_dir * k * 22.0, 2.2, Color(c, (0.7 if locked else 0.35) * (1.0 - k / 8.0)))
		AttackData.Kind.SLAM:
			Draw25.ground_circle(self, feet, def.radius, Color(c, a * 0.8))
		AttackData.Kind.LEAP:
			var tz := e.world.map.ground_at(e.target.x, e.target.y)
			var at := View.to_world(e.target, gz if tz == Tuning.VOID_H else float(tz)) - e.position
			Draw25.ground_circle(self, at, def.radius, Color(c, a * 0.8))
			Draw25.ground_ring(self, at, def.radius, Color(c, 0.7 if locked else 0.35), 2.0)
