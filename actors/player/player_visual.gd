class_name PlayerVisual
extends Node2D
## How Bloob looks (prototype: src/main.ts drawWorld "Bloob" + drawHeldWeapon).
## Picks the animation frame from Bloob's state every frame, faces the aim, draws the held
## weapon along the swing's real hitbox angle, the shadow, status rings and the aim ring.
##
## Screen: a child scaled to upright screen units (see View); sprites inside it stand up.
## Swing drawings: each swing pose spreads its windup / strike / follow-through over its own
## run of frames (prototype: content/anims.ts SWING_CLIPS).

const BLOOB_SCALE := 0.5           ## world units per atlas pixel (48-unit Bloob)
const ANCHOR := 0.06
const SWING_CLIPS := [
	{windup = ["slash1", 0, 2], strike = ["slash1", 2, 2], follow = ["slash1", 4, 1]},
	{windup = ["slash2", 0, 2], strike = ["slash2", 2, 2], follow = ["slash2", 4, 1]},
	{windup = ["bigslash", 0, 3], strike = ["bigslash", 3, 3], follow = ["recovery", 0, 4]},
]

var player: Player
var frame_name := "bloob.idle.0"

@onready var screen: Node2D = $Screen
@onready var body: Sprite2D = $Screen/Body
@onready var weapon: Sprite2D = $Screen/Weapon
@onready var weapon2: Sprite2D = $Screen/Weapon2


func _process(_delta: float) -> void:
	if player == null or player.world == null:
		return
	_update()
	queue_redraw()


func _screen_off(g: Vector2, h: float) -> Vector2:
	return Vector2(g.x, g.y * View.ground_k - h * View.height_k)


func _pick_frame() -> String:
	var p := player
	var m := p.melee
	var tick := p.world.tick_n
	var phase := m.swing_phase()
	var air := m.atk_step == Tuning.AIR_STEP
	var ground := p.world.map.ground_at(p.position.x, p.position.y)
	if p.invuln > 38 and not p.god:
		return "bloob.hurt.0"
	if p.busy_t > 0 and p.cast_skill >= 0:
		return "bloob.cast.%d" % (0 if p.busy_t > 6 else 1)
	if p.drink_t > 0:
		return "bloob.drink.%d" % (0 if p.drink_t > 10 else 1)
	if p.land_lag > 0:
		return "bloob.land.0"
	if p.diving:
		return "bloob.dive.0"
	if p.dodging():
		return "bloob.dodge.%d" % (0 if p.dodge_elapsed < 8 else 1)
	if air and phase > 0:
		return "bloob.airslash.%d" % (phase - 1)
	if p.z > ground + 1 or p.vz > 0.0:
		return "bloob.jump.%d" % (0 if p.vz > 2.0 else (1 if p.vz > -2.0 else 2))
	if phase > 0:
		return _swing_frame(GameState.weapon_data().pose_of(m.atk_step), phase, m.atk_t, m.current_swing())
	if p.vel.length() > 0.4:
		return "bloob.run.%d" % ((tick / 4) % 6)
	if tick % 210 < 7:
		return "bloob.blink.0"
	return "bloob.idle.%d" % ((tick / 12) % 4)


## the drawing for a swing phase: how far through the phase picks which of its frames
func _swing_frame(pose: int, phase: int, t: int, sw: SwingData) -> String:
	var c: Dictionary = SWING_CLIPS[mini(pose, 2)]
	var part: Array
	var u: float
	if phase == 1:
		part = c.windup
		u = float(t) / maxf(1.0, sw.windup)
	elif phase == 2:
		part = c.strike
		u = float(t - sw.windup) / maxf(1.0, sw.active)
	else:
		# the follow-through settles fast, then holds its last drawing until the swing ends
		part = c.follow
		u = minf(1.0, float(t - sw.windup - sw.active) / maxf(1.0, sw.recover) * 1.4)
	var n: int = part[2]
	var k := clampi(floori(u * n), 0, n - 1)
	return "bloob.%s.%d" % [part[0], part[1] + k]


func _update() -> void:
	var p := player
	visible = not p.dead
	screen.position = Vector2(0, View.lift(p.z))
	screen.scale = Vector2(1.0, View.upright())
	frame_name = _pick_frame()
	body.texture = Art.frame(frame_name)
	var m := p.melee
	var facing_x := p.dodge_dir.x if p.dodging() else (m.atk_dir.x if m.swinging() else p.aim.x - p.position.x)
	var facing := 1.0 if facing_x >= 0.0 else -1.0
	body.flip_h = facing_x < 0.0
	var wob: float = p.world.fx.squash * sin(Time.get_ticks_msec() * 0.05) * 0.1
	body.scale = Vector2(BLOOB_SCALE * (1.0 + wob), BLOOB_SCALE * (1.0 - wob))
	body.offset = Vector2(0, -(0.5 - ANCHOR) * 96.0)
	# blink while invulnerable after a hit
	var blink := p.invuln > 0 and not p.god and ((p.invuln >> 2) & 1) == 1
	body.visible = not blink
	_update_weapon(facing, blink)


func _place_weapon(s: Sprite2D, wd: WeaponData, ground_off: Vector2, h: float, w_scale: float, h_scale: float, flip: bool, rot_proto: float) -> void:
	s.visible = true
	s.texture = Art.frame(wd.sprite)
	s.position = _screen_off(ground_off, h)
	s.flip_h = flip
	s.rotation = -rot_proto
	s.scale = Vector2(wd.art_scale * w_scale, wd.art_scale * h_scale)
	# the grip sits on the node's origin
	s.offset = Vector2(0, 48.0 - 96.0 * (1.0 - wd.grip))


func _update_weapon(facing: float, hidden: bool) -> void:
	var p := player
	var wd := GameState.weapon_data()
	weapon.visible = false
	weapon2.visible = false
	if hidden or not wd.held:
		return
	var sin_p := View.ground_k
	var bob := sin(Time.get_ticks_msec() * 0.006) * 1.2
	var off := wd.id == "daggers"
	var m := p.melee
	if m.swinging() and not p.dodging() and not p.diving:
		var sw := m.current_swing()
		var v_from := sw.vis_from if sw.has_vis else -1.0
		var v_to := sw.vis_to if sw.has_vis else 1.0
		var v_lift := sw.vis_lift if sw.has_vis else 0.3
		var v_thrust := sw.vis_thrust if sw.has_vis else 0.0
		var aim := m.atk_dir.angle()
		var t := m.atk_t
		var g: float
		var lift: float
		var thrust := 0.0
		if t < sw.windup:
			var u := float(t) / maxf(1.0, sw.windup)
			g = aim + v_from
			lift = 0.5 + (v_lift - 0.5) * u
			thrust = -8.0 * u * (1.0 if v_thrust != 0.0 else 0.0)
		elif t < sw.windup + sw.active:
			# exactly the angle the hitbox uses this tick
			var k := t - sw.windup + 1
			var u := float(k) / maxf(1.0, sw.active)
			var e2 := 1.0 - (1.0 - u) * (1.0 - u)
			g = aim + sw.sweep_at(k)
			lift = v_lift * (1.0 - e2)
			thrust = v_thrust * e2
		else:
			var u := float(t - sw.windup - sw.active) / maxf(1.0, sw.recover)
			g = aim + v_to
			lift = maxf(0.0, u - 0.5) * 0.8
			thrust = v_thrust * (1.0 - u)
		var dx := cos(g)
		var dy := sin(g)
		var vx := (1.0 - lift) * dx
		var vy := (1.0 - lift) * -dy * sin_p + lift
		var length := maxf(Vector2(vx, vy).length(), 0.0001)
		var rot := atan2(-vx, vy)
		_place_weapon(weapon, wd, Vector2(dx, dy) * (6.0 + thrust), 14.0 + lift * 4.0, 1.0, maxf(0.55, length), vx < 0.0, rot)
		if off:
			_place_weapon(weapon2, wd, Vector2(-facing * 10.0, 2.0), 12.0 + bob, 1.0, 1.0, facing > 0.0, facing * wd.rest)
		return
	if p.diving:
		_place_weapon(weapon, wd, Vector2(facing * 6.0, 3.0), 12.0, 1.0, 1.0, facing < 0.0, PI)
		return
	# at rest: held at Bloob's back, tip leaning back over the shoulder
	_place_weapon(weapon, wd, Vector2(-facing * 14.0, 2.0), 8.0 + bob, 1.0, 1.0, facing > 0.0, facing * wd.rest)
	if off:
		_place_weapon(weapon2, wd, Vector2(facing * 11.0, 3.0), 9.0 - bob, 1.0, 1.0, facing < 0.0, -facing * wd.rest)


func _draw() -> void:
	var p := player
	if p == null or p.world == null or p.dead:
		return
	var map := p.world.map
	var g := map.ground_at(p.position.x, p.position.y)
	var gz := p.z if g == Tuning.VOID_H else float(g)
	Draw25.ground_ellipse(self, Vector2(0, View.lift(gz)), Player.R * 1.5 * 1.25, Player.R * 1.5 * 0.8, Color(0, 0, 0, 0.42))
	var feet := Vector2(0, View.lift(p.z))
	if p.in_perfect_window():
		Draw25.ground_ring(self, feet, Player.R + 10, Color(1, 0.85, 0.45, 0.9), 2.5)
	if p.buff > 0:
		Draw25.ground_ring(self, feet, Player.R + 6, Color(1, 0.75, 0.35, 0.6), 2.0)
	if p.rally_t > 0:
		Draw25.ground_ring(self, feet, Player.R + 14 + sin(p.world.tick_n * 0.3) * 2, Color(1, 0.45, 0.3, 0.6), 2.0)
	if p.guard_t > 0:
		draw_set_transform(Vector2(0, View.lift(p.z + 14)), 0, Vector2(1, View.upright()))
		draw_arc(Vector2.ZERO, Player.R + 12, 0, TAU, 32, Color(0.75, 0.85, 1, 0.7), 2.5)
		draw_set_transform(Vector2.ZERO)
	# the aim ring on the ground where the mouse points
	var ag := map.ground_at(p.aim.x, p.aim.y)
	var aim_w := View.to_world(p.aim, p.z if ag == Tuning.VOID_H else float(ag))
	Draw25.ground_ring(self, aim_w - p.position, 7.0, Color(0.85, 0.7, 0.4, 0.55), 1.5)
	if p.world.debug_hitboxes:
		_draw_hitboxes(feet)


func _draw_hitboxes(feet: Vector2) -> void:
	var p := player
	Draw25.ground_ring(self, feet, Player.R, Color(0.3, 1, 0.5, 1), 1.5)
	Draw25.ground_ring(self, feet, GameState.magnet, Color(0.98, 0.78, 0.32, 0.35), 1.0)
	var m := p.melee
	if not m.swinging():
		return
	var sw := m.current_swing()
	var a := m.atk_dir.angle()
	var k := clampi(m.atk_t - sw.windup, 0, sw.active)
	var live := m.atk_t >= sw.windup and m.atk_t < sw.windup + sw.active
	match sw.shape():
		SwingData.Shape.THRUST:
			var tip := sw.tip_at(k + 1)
			var pts := PackedVector2Array()
			var dir := m.atk_dir
			var n := Vector2(-dir.y, dir.x) * sw.width * 0.5
			for v in [n, dir * tip + n, dir * tip - n, -n]:
				pts.append(feet + v)
			draw_colored_polygon(pts, Color(1, 0.5, 0.3, 0.8 if live else 0.35))
		SwingData.Shape.SMASH:
			var c := maxf(0.0, sw.range - sw.impact)
			Draw25.ground_ring(self, feet + m.atk_dir * c, sw.impact, Color(1, 0.5, 0.3, 0.9 if live and k == sw.active - 1 else 0.35), 2.0)
		_:
			var f0 := sw.sweep_at(0)
			var f1 := sw.sweep_at(sw.active)
			Draw25.ground_arc_band(self, feet, sw.range * 0.5, sw.range, a + minf(f0, f1), a + maxf(f0, f1), Color(1, 0.5, 0.3, 0.3))
			if live:
				var s0 := sw.sweep_at(k)
				var s1 := sw.sweep_at(k + 1)
				Draw25.ground_arc_band(self, feet, sw.range * 0.5, sw.range, a + minf(s0, s1) - 0.05, a + maxf(s0, s1) + 0.05, Color(1, 0.9, 0.4, 0.9))
