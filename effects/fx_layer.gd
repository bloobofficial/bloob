class_name FxLayer
extends Node2D
## Cosmetic effects (prototype: render/fx.ts): particles, rings, slash crescents, death pops,
## screen shake, flash, vignette, room fade, banners and toasts. Fed only by gameplay events
## (Events.game_event); runs on real time scaled by the world's time scale, so particles freeze
## during hitstop while the shake keeps rattling. Uses its own randomness on purpose.

const MAX_PARTICLES := 2000
const SLASH_LIFE := 0.16
const PGRAV := 0.35

var world: World
# particles: [pos Vector2, z, vel Vector2, vz, life, max_life, size, color, square]
var _p: Array = []
var _rings: Array = []       ## [pos, z, r, max_r, life, color]
var _slashes: Array = []     ## dictionaries
var _ghosts: Array = []      ## [pos, z, kind, life, size, flip]

var squash := 0.0             ## Bloob squash impulse
var trauma := 0.0             ## 0..1, shake = trauma^2
var flash := 0.0
var flash_col := Color.WHITE
var vignette := 0.0
var fade := 0.0               ## room transition fade (1 = black)
var shake := Vector2.ZERO
var banner := ""
var banner_t := 0.0
var toast := ""
var toast_t := 0.0
var _t := 0.0


func _ready() -> void:
	Events.game_event.connect(_on_event)


func reset() -> void:
	_p.clear()
	_rings.clear()
	_slashes.clear()
	_ghosts.clear()
	trauma = 0.0
	flash = 0.0
	vignette = 0.0
	squash = 0.0


func particle_count() -> int:
	return _p.size()


func _spawn(pos: Vector2, z: float, vel: Vector2, vz: float, life: float, size: float, col: Color, square := false) -> void:
	if _p.size() >= MAX_PARTICLES:
		_p.pop_front()
	_p.append([pos, z, vel, vz, life, life, size, col, square])


func _burst(pos: Vector2, z: float, n: int, speed: float, life: float, size: float, c: Color, dir := Vector2.ZERO, spread := PI, up := 2.0, square := false) -> void:
	var base := dir.angle()
	var directed := dir != Vector2.ZERO
	for k in n:
		var a := base + randf_range(-1, 1) * spread if directed else randf() * TAU
		var sp := speed * (0.35 + randf() * 0.65)
		_spawn(pos, z, Vector2.from_angle(a) * sp, up * (0.4 + randf()), life * (0.6 + randf() * 0.6), size * (0.6 + randf() * 0.7), c, square)


## v0.9 pixel sparks: square bits in the slash colour, a few white-hot
func _sparks(pos: Vector2, z: float, n: int, speed: float, c: Color, dir: Vector2, spread: float) -> void:
	_burst(pos, z, n, speed, 0.32, 1.1, c, dir, spread, 2.2, true)
	_burst(pos, z, ceili(n / 3.0), speed * 0.8, 0.22, 0.9, Color(1, 0.96, 0.92), dir, spread, 2.0, true)


func ring(pos: Vector2, z: float, max_r: float, life: float, c: Color) -> void:
	if _rings.size() >= 64:
		_rings.pop_front()
	_rings.append([pos, z, 4.0, max_r, life, c])


func add_trauma(v: float) -> void:
	trauma = minf(1.0, trauma + v)


func say(text: String, seconds := 1.6) -> void:
	banner = text
	banner_t = seconds


func note(text: String, seconds := 1.8) -> void:
	toast = text
	toast_t = seconds


func ghost(e: Enemy) -> void:
	if _ghosts.size() >= 64:
		_ghosts.pop_front()
	_ghosts.append([e.position, e.z, e.kind, 0.2, e.size, e.visual.sprite.flip_h if e.visual else false])


func _on_event(type: int, x: float, y: float, a: float, b: float, z: float) -> void:
	var pos := Vector2(x, y)
	match type:
		Ev.HIT:
			_burst(pos, z, 3, 3.2, 0.22, 1.6, Color(1, 0.85, 0.6), Vector2(-a, -b), 0.9, 1.5)
		Ev.KILL:
			var c: Color = Content.enemies[int(a)].color
			var big := b > 12.0
			_burst(pos, z + 10, 40 if big else 12, 6.0 if big else 3.4, 0.8 if big else 0.45, 3.2 if big else 2.2, c, Vector2.ZERO, PI, 4.0 if big else 2.5)
			if big:
				ring(pos, z, 120, 0.45, c)
				add_trauma(0.45)
		Ev.PLAYER_HURT:
			add_trauma(0.5)
			flash = 0.35
			flash_col = Color(0.9, 0.15, 0.2)
			_burst(pos, z + 12, 14, 4, 0.4, 2, Color(1, 0.3, 0.3))
		Ev.PLAYER_DEATH:
			add_trauma(1.0)
			flash = 0.6
			flash_col = Color(0.9, 0.1, 0.15)
			_burst(pos, z + 12, 80, 7, 1.2, 3, Color(1, 0.4, 0.4), Vector2.ZERO, PI, 5)
		Ev.DODGE:
			_burst(pos, z + 2, 7, 1.6, 0.35, 2.4, Color(0.85, 0.8, 0.7), Vector2(-a, -b), 0.5, 0.8)
		Ev.PERFECT_DODGE:
			flash = 0.55
			flash_col = Color(1, 0.95, 0.85)
			add_trauma(0.55)
			vignette = 1.0
			ring(pos, z, 150, 0.5, Color(1, 0.93, 0.75))
			ring(pos, z, 260, 0.9, Color(0.85, 0.7, 0.4))
			_burst(pos, z + 12, 36, 6, 0.6, 2.4, Color(1, 0.9, 0.65), Vector2.ZERO, PI, 3)
		Ev.TELL:
			ring(pos, z, 70, 0.6, Color(1, 0.3, 0.25))
			add_trauma(0.15)
		Ev.LUNGE:
			_burst(pos, z + 4, 16, 3, 0.35, 2.6, Color(1, 0.35, 0.3), Vector2(-a, -b), 0.6, 1)
			add_trauma(0.2)
		Ev.SQUAD_COMMIT:
			ring(pos, z, 90, 0.5, Color(1, 0.5, 0.75))
		Ev.SQUAD_STAGGER:
			ring(pos, z, 50, 0.4, Color(0.7, 0.9, 1))
		Ev.SWING:
			var ws := Ev.unpack_swing(b)
			var wd: WeaponData = Content.weapons[clampi(ws.x, 0, Content.weapons.size() - 1)]
			var sw := wd.swing(ws.y)
			var heavy := sw.heavy
			if _slashes.size() >= 16:
				_slashes.pop_front()
			_slashes.append({pos = pos, z = z, ang = a, rad = sw.range, life = SLASH_LIFE * (1.5 if heavy else 1.0), step = ws.y,
				wd = wd, heavy = heavy, thrust = sw.width, from = sw.sweep_at(0), to = sw.sweep_at(sw.active),
				shape = sw.shape(), impact = sw.impact})
			squash = 1.0 if heavy else 0.6
			if heavy:
				var d := Vector2.from_angle(a)
				_burst(pos + d * 30, z, 12, 2.2, 0.5, 3, Color(0.72, 0.66, 0.58), Vector2.ZERO, PI, 1.2)
				_sparks(pos + d * sw.range * 0.8, z + 10, 10, 3, wd.fx_rim, d, 1.1)
		Ev.MELEE_HIT:
			var ws := Ev.unpack_swing(b)
			var wd: WeaponData = Content.weapons[clampi(ws.x, 0, Content.weapons.size() - 1)]
			var heavy := wd.swing(ws.y).heavy
			_sparks(pos, z + 12, 16 if heavy else 8, 6.0 if heavy else 4.2, wd.fx_rim, Vector2.from_angle(a), 0.75)
			if heavy:
				add_trauma(0.35)
				ring(pos, z, 34, 0.25, Color(1, 0.9, 0.7))
			else:
				add_trauma(0.08)
		Ev.WALL_SPLAT:
			_burst(pos, z + 10, 18, 4.5, 0.45, 2.4, Color(0.75, 0.7, 0.85), Vector2.ZERO, PI, 2.5)
			ring(pos, z, 40 + b, 0.3, Color(0.9, 0.85, 1))
			add_trauma(0.3)
		Ev.LAND:
			_burst(pos, z + 2, 14, 3.5, 0.5, 3, Color(0.72, 0.66, 0.58), Vector2.ZERO, PI, 1)
			ring(pos, z, 30 + b * 2, 0.3, Color(0.9, 0.85, 0.75))
			add_trauma(0.22)
		Ev.RING_OUT:
			_burst(pos, z, 10, 2, 0.6, 2.2, Content.enemies[int(a)].color, Vector2.ZERO, PI, 3)
		Ev.JUMP:
			_burst(pos, z + 1, 8, 1.8, 0.35, 2.6, Color(0.78, 0.72, 0.62), Vector2.ZERO, PI, 0.5)
			squash = 0.5
		Ev.PLAYER_LAND:
			_burst(pos, z + 1, 6 + int(minf(10, a / 8)), 2, 0.35, 2.6, Color(0.78, 0.72, 0.62), Vector2.ZERO, PI, 0.4)
			squash = 0.6
		Ev.DIVE_SLAM:
			ring(pos, z, a, 0.4, Color(1, 0.88, 0.6))
			ring(pos, z, a * 1.5, 0.6, Color(0.9, 0.7, 0.4))
			_burst(pos, z + 2, 30, 5 + a * 0.03, 0.6, 3.2, Color(0.78, 0.7, 0.58), Vector2.ZERO, PI, 2)
			add_trauma(0.35 + minf(0.35, a / 300.0))
			squash = 1.0
		Ev.PICKUP:
			_burst(pos, z, 4, 1.4, 0.25, 1.6, Tuning.res_color(int(a)), Vector2.ZERO, PI, 1.5)
		Ev.LEVEL_UP:
			say("Level %d" % int(a), 1.6)
			ring(pos, z, 110, 0.6, Color(1, 0.85, 0.45))
			_burst(pos, z + 14, 30, 3, 0.8, 2.4, Color(1, 0.88, 0.5), Vector2.ZERO, PI, 4)
			flash = 0.25
			flash_col = Color(1, 0.9, 0.6)
		Ev.DRINK:
			_burst(pos, z + 20, 8, 1, 0.5, 2, Color(0.98, 0.78, 0.32), Vector2.ZERO, PI, 2.5)
		Ev.SKILL_CAST:
			_burst(pos, z + 16, 12, 2.2, 0.45, 2.2, Color(1, 0.95, 0.75), Vector2.ZERO, PI, 3)
		Ev.BLAST:
			var own := int(b)
			var c := Color(1, 0.35, 0.25) if own == 0 else (Color(0.75, 0.45, 1) if own == 2 else Color(1, 0.9, 0.6))
			ring(pos, z, a, 0.35, c)
			if own != 2:
				_burst(pos, z + 4, 18, 3 + a * 0.03, 0.5, 2.8, Color(1, 0.5, 0.35) if own == 0 else Color(0.78, 0.7, 0.58), Vector2.ZERO, PI, 2)
				add_trauma(0.25)
		Ev.TECH_BOUGHT:
			say(Content.techs[int(a)].name, 1.4)
		Ev.JOB_CHANGED:
			say(Content.jobs[int(a)].name, 1.4)
			ring(pos, z, 90, 0.5, Color(1, 0.85, 0.5))
		Ev.LOOT:
			note("Chest! Loot spills out", 1.8)
		Ev.CHAMPION:
			note("Champion: " + Tuning.affix_names(int(a)), 1.8)
		Ev.ROOM_ENTER:
			fade = 1.0
			say(Content.rooms[int(a)].name, 1.4)
		Ev.DOORS_SEALED:
			say("The passages seal", 1.4)
		Ev.WEAPON_FOUND:
			var wd: WeaponData = Content.weapons[int(a)]
			say(wd.name, 1.8)
			var bi := int(b)
			note("You already had one: the spare breaks into Relic Shards" if bi == 2 else ("Bought: " if bi == 1 else "Found: ") + wd.traits, 2.6)
			ring(pos, z, 90, 0.6, wd.fx_heavy_glow)
			_burst(pos, z + 20, 26, 3, 0.8, 2.4, wd.fx_glow, Vector2.ZERO, PI, 4)
			flash = 0.25
			flash_col = Color(1, 0.95, 0.8)
		Ev.WEAPON_EQUIP:
			var wd: WeaponData = Content.weapons[int(a)]
			note(wd.name + " in hand", 1.6)
			ring(pos, z, 40, 0.35, wd.fx_glow)
		Ev.DENIED:
			var wd: WeaponData = Content.weapons[int(b)]
			note(("Not enough to buy the %s yet" if int(a) == 1 else "Already holding the %s") % wd.name, 1.8)
		Ev.ITEM_APPEAR:
			note("Something glints: the " + Content.weapons[int(a)].name, 2.4)
			ring(pos, z, 70, 0.8, Color(1, 0.9, 0.6))
			_burst(pos, z + 10, 20, 2.4, 0.9, 2.2, Color(1, 0.9, 0.6), Vector2.ZERO, PI, 5)
		Ev.WELL_USED:
			note("The well mends you. Flasks refilled.", 2)
			ring(pos, z, 70, 0.6, Color(0.5, 0.85, 1))
			_burst(pos, z + 20, 18, 2, 0.8, 2.2, Color(0.55, 0.85, 1), Vector2.ZERO, PI, 3)
		Ev.NO_MANA:
			note("Not enough mana", 1.2)
		Ev.ROOM_CLEARED:
			say("Cleared. The way opens", 2)
			flash = 0.3
			flash_col = Color(1, 0.9, 0.6)
			ring(pos, z, 320, 1.0, Color(1, 0.85, 0.5))


func _process(real_dt: float) -> void:
	if world == null:
		return
	_t += real_dt
	var running := world.running
	var dt := real_dt * world.time.world_scale if running else 0.0
	var damp := pow(0.03, dt)
	if dt > 0.0:
		var k := dt * 60.0
		var i := 0
		while i < _p.size():
			var q: Array = _p[i]
			q[4] -= dt
			if q[4] <= 0.0:
				_p.remove_at(i)
				continue
			q[0] += q[2] * k
			q[3] -= PGRAV * k
			q[1] += q[3] * k
			var g := world.map.ground_at(q[0].x, q[0].y)
			if g > -1000 and q[1] < g:
				q[1] = float(g)
				q[3] *= -0.35
				q[2] *= 0.6
			q[2] *= damp
			i += 1
		for r in _rings:
			r[4] -= dt
			r[2] += (r[3] - r[2]) * minf(1.0, dt * 9.0)
		_rings = _rings.filter(func(r): return r[4] > 0.0)
		for s in _slashes:
			s.life -= dt
		_slashes = _slashes.filter(func(s): return s.life > 0.0)
	# shake, flash, vignette, fade run on real time (they sell the freeze)
	trauma = maxf(0.0, trauma - real_dt * 1.6)
	flash = maxf(0.0, flash - real_dt * 2.4)
	vignette = maxf(0.0, vignette - real_dt * 0.5)
	squash = maxf(0.0, squash - real_dt * 5.0)
	fade = maxf(0.0, fade - real_dt * 3.0)
	banner_t = maxf(0.0, banner_t - real_dt)
	toast_t = maxf(0.0, toast_t - real_dt)
	for gh in _ghosts:
		gh[3] -= real_dt
	_ghosts = _ghosts.filter(func(gh): return gh[3] > 0.0)
	var sh := trauma * trauma * 12.0
	shake = Vector2(sh * (sin(_t * 71.3) + sin(_t * 43.1) * 0.5), sh * (cos(_t * 67.7) + sin(_t * 51.9) * 0.5))
	queue_redraw()


func _draw() -> void:
	# death pops: a flash-white copy of the enemy that shrinks away
	for gh in _ghosts:
		var kd: EnemyKindData = Content.enemies[gh[2]]
		var t: float = gh[3] / 0.2
		var size: float = kd.sprite_scale * maxf(0.6, gh[4]) * (0.4 + 0.6 * t)
		var tex := Art.frame("%s.hurt.0" % kd.id)
		var at := View.to_world(gh[0], gh[1])
		draw_set_transform(at, 0, Vector2(size * (1.3 - 0.3 * t), size * t * View.upright()))
		draw_texture(tex, Vector2(-48, -(1.0 - kd.anchor) * 96.0), Color(4, 4, 4, 1))
		draw_set_transform(Vector2.ZERO)
	_draw_slashes()
	for r in _rings:
		var k := minf(1.0, r[4] * 2.5)
		Draw25.ground_ring(self, View.to_world(r[0], r[1]), r[2], Color(r[5], k), 2.5)
	for q in _p:
		var k: float = q[4] / q[5]
		var at := View.to_world(q[0], q[1] + 2.0)
		var col: Color = q[7]
		if q[8]:
			var s: float = q[6] * (1.0 if k > 0.5 else 0.6) * 1.5
			Draw25.upright_rect(self, at, s, Color(col, k))
		else:
			Draw25.upright_circle(self, at, q[6] * (0.4 + k * 0.6), Color(col, k))


## slash crescents: a pixel crescent on the ground that traces exactly the hitbox's sweep,
## a soft glow over it, and for heavy finishers a tall crescent in the air
func _draw_slashes() -> void:
	for s in _slashes:
		var wd: WeaponData = s.wd
		var heavy: bool = s.heavy
		var max_l := SLASH_LIFE * (1.5 if heavy else 1.0)
		var t: float = 1.0 - s.life / max_l
		var alpha := 1.0 if t < 0.6 else 1.0 - (t - 0.6) / 0.4
		var zz: float = s.z + (2.0 if heavy else (14.0 if s.step == Tuning.AIR_STEP else 10.0))
		var origin := View.to_world(s.pos, zz)
		var rim := wd.fx_rim
		var g := wd.fx_heavy_glow if heavy else wd.fx_glow
		var ang: float = s.ang
		if s.thrust > 0.0:
			# thrust: a long streak along the aim with a hot centre line
			var length: float = s.rad * (0.55 + 0.45 * minf(1.0, t * 2.5))
			var d := Vector2.from_angle(ang)
			var n: Vector2 = Vector2(-d.y, d.x) * s.thrust * 0.5 * (0.9 if heavy else 0.7)
			var tip := origin + d * length
			draw_colored_polygon(PackedVector2Array([origin + n * 0.3, tip + n * 0.15, tip + d * 6, tip - n * 0.15, origin - n * 0.3]), Color(g, alpha * 0.35))
			draw_colored_polygon(PackedVector2Array([origin + n, tip, origin - n]), Color(rim, alpha))
			draw_line(origin, tip, Color(1, 0.96, 0.92, alpha), 2.0)
			continue
		if s.shape == SwingData.Shape.SMASH:
			var c := maxf(0.0, s.rad - s.impact)
			var cen := origin + Vector2.from_angle(ang) * c
			var r: float = s.impact * (0.75 + 0.3 * t)
			Draw25.ground_circle(self, cen, r, Color(rim, alpha * 0.45))
			Draw25.ground_ring(self, cen, r, Color(rim, alpha * 0.9), 4.0)
			Draw25.ground_ring(self, cen, r * 0.7, Color(1, 0.96, 0.92, alpha * 0.9), 2.5)
			Draw25.ground_ring(self, cen, s.impact * (0.8 + 0.3 * t), Color(g, alpha * 0.5), 2.0)
			if heavy:
				_air_crescent(s, t, alpha, rim)
			continue
		# arcs and rings: the trail grows from where the blade started to where it is now
		var grow := minf(1.0, t / 0.35)
		var f0: float = s.from
		var cur: float = f0 + (s.to - f0) * (1.0 - (1.0 - grow) * (1.0 - grow))
		var a0 := ang + minf(f0, cur)
		var a1 := ang + maxf(f0, cur)
		var rad: float = s.rad * (0.97 + 0.06 * t)
		var thick := 0.3 if heavy else 0.22
		Draw25.ground_arc_band(self, origin, rad * (1.0 - thick * 1.2), rad * 1.03, a0 - 0.06, a1 + 0.06, Color(g, alpha * 0.4))
		Draw25.ground_arc_band(self, origin, rad * (1.0 - thick), rad, a0 - 0.06, a1 + 0.06, Color(rim, alpha))
		Draw25.ground_arc_band(self, origin, rad * (1.0 - thick * 0.45), rad * (1.0 - thick * 0.15), a0, a1, Color(1, 0.96, 0.92, alpha))
		if heavy:
			_air_crescent(s, t, alpha, rim)


## the concept sheet's Big Slash: a tall crescent sweeping over Bloob, facing the swing
func _air_crescent(s: Dictionary, t: float, alpha: float, rim: Color) -> void:
	var right := cos(s.ang) >= 0.0
	var grow := minf(1.0, t / 0.4)
	var sweep := 2.6 * (1.0 - (1.0 - grow) * (1.0 - grow))
	var start := -2.5 if right else -0.64
	var dir := 1.0 if right else -1.0
	var r := minf(46.0, s.rad * 0.6)
	var c := View.to_world(s.pos, s.z + 18.0)
	draw_set_transform(c, 0, Vector2(1, View.upright()))
	var a0 := start
	var a1 := start + dir * sweep
	Draw25.ground_arc_band(self, Vector2.ZERO, r * 0.74, r, minf(a0, a1), maxf(a0, a1), Color(rim, alpha * 0.9))
	draw_set_transform(Vector2.ZERO)
