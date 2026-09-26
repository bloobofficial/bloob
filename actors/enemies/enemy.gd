class_name Enemy
extends CharacterBody2D
## A monster (prototype: sim/enemies.ts data + sim/ai.ts + sim/enemyAttacks.ts).
##  think(): decisions (squad posture, attack start, orbit / hold / commit, route choice)
##  move():  steering every tick (path + personality + separation), knockback, height,
##           falls and ring-outs, contact / strike resolution
## Every patterned monster telegraphs (WINDUP, aim locks at AIM_LOCK), commits (LUNGE = the
## attack's active ticks), then is open (RECOVER), then keeps its spacing while it recharges.

enum St { APPROACH, ORBIT, HOLD, COMMIT, WINDUP, LUNGE, RECOVER, STAGGER, ANCHOR }
enum Role { NONE, PIN, FLANK, LEAD }

const HALF_PI := PI / 2.0

var world: World
var data: EnemyKindData
var kind := 0
var alive := true
var z := 0.0
var vz := 0.0
var peak_z := 0.0
var vel := Vector2.ZERO          ## steering velocity, units per tick
var knock := Vector2.ZERO        ## knockback, units per tick (decays 18% per tick)
var hp := 10.0
var max_hp := 10.0
var radius := 9.0
var speed := 1.5
var phase := 0.0
var weave_amp := 0.0
var weave_freq := 0.0
var lunge_dir := Vector2.ZERO    ## attack aim (locks during the windup)
var orbit_dir := 1
var route := 0
var anchor := -1
var state: St = St.APPROACH
var timer := 0
var cd := 0                      ## attack cooldown
var atk_cd := 0                  ## contact damage cooldown
var freeze := 0                  ## local hitstop
var flash := 0                   ## hit flash ticks
var squad := -1
var role: Role = Role.NONE
var arrived := false
var level := 1
var affix := 0
var champ := false
var atk: AttackData = null
var aspd := 0.0                  ## current dash / leap speed
var wtot := 1                    ## total windup ticks (closing ring)
var dmg_mul := 1.0
var knock_mul := 1.0
var hex_t := 0
var age := 0
var size := 1.0                  ## visual scale
var leap := false
var struck := false              ## this attack already connected
var target := Vector2.ZERO       ## locked target point (leaps)
var pattern_i := 0               ## bosses: the next attack in their cycle
var enraged := false             ## bosses: below half health they press harder
var dormant := false             ## generated maps: asleep in its glade until Bloob comes close
var home := Vector2.ZERO         ## where a dormant monster strolls about
var _nav := {}

@onready var visual: EnemyVisual = $Visual


func is_brute() -> bool:
	return kind == 5 or data.poise


## match the collision footprint to the rolled radius
func apply_radius() -> void:
	var cs := $Footprint as CollisionShape2D
	var shape := CircleShape2D.new()
	shape.radius = radius
	cs.shape = shape


func setup(w: World, k: int, at: Vector2, pz: float) -> void:
	world = w
	kind = k
	data = Content.enemies[k]
	position = at
	z = pz
	peak_z = pz
	visual.enemy = self
	reset_physics_interpolation()


# ---------------- decisions ----------------

func think() -> void:
	if dormant:
		return
	var p := world.player
	var dist := position.distance_to(p.position)
	if state == St.STAGGER or state == St.WINDUP or state == St.LUNGE or state == St.RECOVER:
		return
	# squad members: the squad brain decides the posture
	if squad >= 0:
		var sq: Dictionary = world.squads[squad]
		if sq.state == Squads.STAGGER:
			return
		if sq.state == Squads.COMMIT:
			# COMMIT: everyone goes in, using their attack pattern when in range
			if try_attack(dist):
				return
			if is_brute():
				if state != St.APPROACH:
					state = St.APPROACH
				route = EnemyKindData.Route.DIRECT
			elif state != St.COMMIT:
				state = St.COMMIT
				timer = 1 << 20
			return
		# GATHER
		if role == Role.FLANK:
			var side := HALF_PI if orbit_dir > 0 else -HALF_PI   # each flanker owns a side
			var k := anchor_for_angle(sq.front + side)
			anchor = k
			var ad := world.anchor_point(k).distance_to(position)
			if ad < 70.0:
				state = St.ANCHOR
				arrived = true
			elif state != St.ANCHOR or ad > 140.0:
				state = St.APPROACH
				route = EnemyKindData.Route.LEFT   # any non-direct route; anchor chosen above
				arrived = false
		else:
			# pinners and the leader hold the front line
			var hold := 260.0 if role == Role.LEAD else 210.0
			if dist < hold + 40.0:
				state = St.HOLD
				timer = 1 << 20   # squad members never self-commit
			else:
				state = St.APPROACH
				route = EnemyKindData.Route.DIRECT
		return
	# free agents: attack pattern first, then personality
	if try_attack(dist):
		return
	if not world.mode.contact and cd > 0 and world.rng.chance(0.004):
		orbit_dir = -orbit_dir
	match kind:
		5:   # Brute
			return
		3:   # Circler
			if state == St.APPROACH and dist < data.orbit_radius + 30.0:
				state = St.ORBIT
				timer = floori(world.rng.rangef(data.orbit_ticks.x, data.orbit_ticks.y))
		4:   # Stalker
			if state == St.APPROACH and dist < data.hold_dist + 20.0:
				state = St.HOLD
				timer = floori(world.rng.rangef(data.hold_ticks.x, data.hold_ticks.y))
			elif state == St.HOLD and p.exposed():
				# the opening it was waiting for
				state = St.COMMIT
				timer = 150
	# route management for anyone still approaching
	if state == St.APPROACH and route != EnemyKindData.Route.DIRECT:
		if anchor < 0:
			anchor = _route_anchor()
		var ad := world.anchor_point(anchor).distance_to(position)
		if ad < 90.0 or dist < 150.0:
			route = EnemyKindData.Route.DIRECT
			anchor = -1


static func anchor_for_angle(a: float) -> int:
	var k := roundi(a / HALF_PI) % 4
	if k < 0:
		k += 4
	return k


func _route_anchor() -> int:
	var a := (position - world.player.position).angle()   # player -> enemy
	match route:
		EnemyKindData.Route.LEFT: return anchor_for_angle(a + HALF_PI)
		EnemyKindData.Route.RIGHT: return anchor_for_angle(a - HALF_PI)
		EnemyKindData.Route.AROUND: return anchor_for_angle(a + PI)
	return -1


# ---------------- attacks (sim/enemyAttacks.ts) ----------------

## Try to start this enemy's attack. Returns true if it began winding up.
func try_attack(dist: float) -> bool:
	if data.boss and not data.attacks.is_empty():
		# bosses don't roll: they cycle (swing, charge, slam, and a long breath after the slam)
		atk = data.attacks[pattern_i % data.attacks.size()]
	if atk == null or cd > 0 or world.dev.passive:
		return false
	if dist > atk.range:
		return false
	var p := world.player
	if p.dead or absf(p.z - z) > 30.0:
		return false
	var frenzy := (affix & Tuning.Affix.FRENZIED) != 0 or enraged
	var w := maxi(8, roundi(atk.windup * (0.75 if frenzy else 1.0)))
	if data.boss:
		pattern_i += 1
	state = St.WINDUP
	timer = w
	wtot = w
	vel = Vector2.ZERO
	# intent: where it means to hit (tracked until AIM_LOCK, then fixed)
	var d := p.position - position
	lunge_dir = d.normalized() if d.length() > 0.0 else Vector2.RIGHT
	target = p.position
	struck = false
	# attack frequency: the map tier (and run setting) shorten or stretch the gap between attacks
	var rate := world.diff.atk_rate * Tuning.RUN_ATK_RATE
	cd = roundi(world.rng.rangef(atk.cooldown.x, atk.cooldown.y) * (0.5 if frenzy else 1.0) / rate) + w + atk.active + atk.recover
	Events.push(Ev.TELL, position.x, position.y, get_instance_id(), 1 if atk.heavy else 0, z)
	if atk.heavy or champ:
		world.time.request_hitstop(3, Tuning.Prio.HIT)   # micro-freeze: the world holds its breath
	return true


## Windup finished: the attack happens along the locked aim / at the locked target.
func execute_attack() -> void:
	var p := world.player
	var u := lunge_dir
	match atk.kind:
		AttackData.Kind.DASH, AttackData.Kind.STRIKE:
			state = St.LUNGE
			timer = atk.active
			aspd = atk.speed
			leap = false
			struck = false
			Events.push(Ev.LUNGE, position.x, position.y, u.x, u.y, z)
		AttackData.Kind.SHOOT:
			var base := u.angle()
			for k in atk.shots:
				var a := base + (k - (atk.shots - 1) / 2.0) * atk.spread
				var dir := Vector2.from_angle(a)
				world.projectiles.spawn(position + dir * (radius + 4.0), z + 14.0, dir * atk.speed, Tuning.ENEMY_SHOT_LIFE,
					atk.damage * dmg_mul * world.dev.enemy_damage, Projectiles.OWNER_ENEMY)
			Events.push(Ev.ENEMY_SHOT, position.x, position.y, u.x, u.y, z)
			state = St.RECOVER
			timer = atk.recover
		AttackData.Kind.SLAM:
			Events.push(Ev.BLAST, position.x, position.y, atk.radius, 0, z)
			_blast_player(atk.radius, atk.damage)
			if state == St.WINDUP:
				state = St.RECOVER
				timer = atk.recover
		AttackData.Kind.LEAP:
			# jump to the locked target point; lands after `active` ticks
			var t := atk.active
			var td := target - position
			var tl := maxf(td.length(), 1.0)
			var land := minf(tl, atk.range + 40.0)
			state = St.LUNGE
			timer = t
			lunge_dir = td / tl
			aspd = land / t
			vz = Tuning.GRAVITY * t / 2.0
			leap = true
			Events.push(Ev.LUNGE, position.x, position.y, u.x, u.y, z)


func _blast_player(r: float, dmg: float) -> void:
	var p := world.player
	if not p.dead and position.distance_to(p.position) < r + Player.R and absf(p.z - z) < 30.0:
		if p.in_perfect_window():
			p.perfect(self)
		elif p.hurt(dmg * dmg_mul * world.dev.enemy_damage, position):
			vampire(dmg)


## Active phase ended. Leaps blast on landing.
func finish_attack() -> void:
	if leap:
		leap = false
		Events.push(Ev.BLAST, position.x, position.y, atk.radius, 0, z)
		_blast_player(atk.radius, atk.damage)
	state = St.RECOVER
	timer = atk.recover if atk else 40


## A strike's active ticks: Bloob is hit only inside the wedge it was aimed at (once).
func resolve_strike() -> void:
	if struck:
		return
	var p := world.player
	var dv := p.position - position
	var d := maxf(dv.length(), 0.001)
	if d > atk.range + Player.R * 0.6:
		return
	var ang := acos(clampf(dv.dot(lunge_dir) / d, -1.0, 1.0))
	var pad := asin(Player.R / d) if d > Player.R else PI
	if ang > atk.arc + pad:
		return
	struck = true
	if p.in_perfect_window():
		p.perfect(self)
		return
	if p.hurt(atk.damage * dmg_mul * world.dev.enemy_damage, position):
		vampire(atk.damage)


func vampire(dealt: float) -> void:
	if affix & Tuning.Affix.VAMPIRIC:
		hp = minf(max_hp, hp + dealt * 0.5 * dmg_mul)


func contact_damage(base: float) -> float:
	var dmg := atk.damage if state == St.LUNGE and atk != null else base
	return dmg * dmg_mul * world.dev.enemy_damage


# ---------------- per-tick movement ----------------

func move(s: float) -> void:
	if s == 0.0:
		return   # global hitstop: nothing moves
	if freeze > 0:
		freeze -= 1   # local hitstop
		return
	if dormant:
		_idle(s)
		return
	if flash > 0: flash -= 1
	if atk_cd > 0: atk_cd -= 1
	if cd > 0: cd -= 1
	if hex_t > 0: hex_t -= 1
	if age < 65535: age += 1
	var p := world.player
	var dv := p.position - position
	var dist := maxf(dv.length(), 0.0001)
	var u := dv / dist
	var near := dist < Tuning.AI_LOD_NEAR and not world.dev.freeze_ai
	var frozen_ai := world.dev.freeze_ai
	var contact_on := world.mode.contact

	# ---- per-tick timers that must be exact (telegraphs) ----
	if frozen_ai:
		pass   # dev "freeze AI": no decisions, timers or steering; physics still applies
	elif state >= St.ORBIT and state <= St.STAGGER and state != St.HOLD:
		timer -= 1
		# intent: aimed attacks follow Bloob for the first part of the windup, then lock
		if state == St.WINDUP and timer > wtot * Tuning.AIM_LOCK:
			lunge_dir = u
			target = p.position
	elif state == St.HOLD and squad < 0:
		timer -= 1
	if timer <= 0 and not frozen_ai:
		match state:
			St.ORBIT:
				state = St.COMMIT
				timer = 180
			St.HOLD:
				state = St.COMMIT
				timer = 150
			St.COMMIT:
				state = St.APPROACH
			St.WINDUP:
				execute_attack()
			St.LUNGE:
				finish_attack()
			St.RECOVER:
				state = St.APPROACH
			St.STAGGER:
				state = St.HOLD if squad >= 0 else St.APPROACH
				timer = 1 << 20

	# ---- desired direction ----
	var t := Vector2.ZERO
	var mul := 1.0
	var absolute := false   # lunge ignores smoothing
	var st := -1 if frozen_ai else state
	match st:
		St.APPROACH:
			var f := 0 if route == EnemyKindData.Route.DIRECT or anchor < 0 else 1 + anchor
			if f == 0 and dist < 64.0:
				t = u
			else:
				var flow := world.flow(f, position, _nav)
				if flow != Vector2.ZERO:
					t = flow
				elif f == 0:
					t = u
				else:
					t = (world.anchor_point(anchor) - position).normalized()
			if data.charge_dist > 0.0 and dist < data.charge_dist:
				mul = data.charge_mul
			if not contact_on and cd > 0 and atk != null:
				# attack recharging: hold a spacing ring and circle instead of pressing into Bloob
				var space := atk.spacing() + radius
				if dist < space + 70.0:
					var err := clampf((dist - space) / 40.0, -1.0, 1.0)
					t = Vector2(-u.y * orbit_dir * 0.85 + u.x * err, u.x * orbit_dir * 0.85 + u.y * err)
					mul = 0.72
			if data.keep_dist > 0.0 and dist < data.keep_dist + 90.0:
				# ranged: hold its distance and strafe; when Bloob rushes in, back off quickly
				var err := clampf((dist - data.keep_dist) / 60.0, -1.0, 1.0)
				t = Vector2(u.x * err - u.y * orbit_dir * 0.7, u.y * err + u.x * orbit_dir * 0.7)
				mul = 1.3 if dist < data.keep_dist * 0.6 else 0.8
		St.ORBIT:
			var err := clampf((dist - data.orbit_radius) / data.orbit_radius * 2.5, -1.0, 1.0)
			t = Vector2(-u.y * orbit_dir + u.x * err, u.x * orbit_dir + u.y * err)
			mul = 1.1
		St.HOLD:
			var hold := (260.0 if role == Role.LEAD else 210.0) if squad >= 0 else data.hold_dist
			var err := clampf((dist - hold) / 60.0, -1.0, 1.0)
			t = Vector2(u.x * err - u.y * orbit_dir * 0.3, u.y * err + u.x * orbit_dir * 0.3)
			mul = 0.75
		St.ANCHOR:
			var a := world.anchor_point(anchor) - position
			var al := maxf(a.length(), 1.0)
			t = a / al * minf(1.0, al / 60.0)
		St.COMMIT:
			var flow := world.flow(0, position, _nav) if dist > 64.0 else Vector2.ZERO
			t = flow if flow != Vector2.ZERO else u
			mul = maxf(1.35, data.charge_mul)
			if not contact_on and cd > 0 and atk != null:
				# committed but the attack isn't ready: close in to the edge of its reach and circle
				var space := atk.spacing() * 0.8 + radius
				if dist < space + 50.0:
					var err := clampf((dist - space) / 30.0, -1.0, 1.0)
					t = Vector2(-u.y * orbit_dir * 0.9 + u.x * err, u.x * orbit_dir * 0.9 + u.y * err)
					mul = 0.9
		St.WINDUP, St.RECOVER:
			t = Vector2.ZERO
			mul = 0.0
		St.LUNGE:
			t = lunge_dir
			absolute = true
		St.STAGGER:
			t = -u * 0.4

	# weave: zigzag across the travel direction
	if near and data.weave_amp > 0.0 and (state == St.APPROACH or state == St.COMMIT):
		phase += weave_freq * s
		var wv := sin(phase) * weave_amp
		t += Vector2(-t.y, t.x) * wv

	# separation: keep a little space so crowds flow instead of stacking
	if near and not absolute:
		var sep := Vector2.ZERO
		var checks := 0
		var gcx := floori(position.x / Tuning.CELL)
		var gcy := floori(position.y / Tuning.CELL)
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if checks >= 10:
					break
				for o: Enemy in world.grid_at(gcx + ox, gcy + oy):
					if o == self or not o.alive or absf(o.z - z) > 24.0:
						continue
					var od := position - o.position
					var rr := radius + o.radius + 2.0
					var od2 := od.length_squared()
					if od2 < rr * rr and od2 > 0.0001:
						var odl := sqrt(od2)
						sep += od / odl * ((rr - odl) / rr)
					checks += 1
					if checks >= 10:
						break   # hard cap per enemy, like the prototype
		t += sep * 1.6

	# integrate
	var sp := (aspd if absolute else speed * mul * (Content.skills[SkillData.Id.HEX].p("slow", 0.6) if hex_t > 0 else 1.0)) * world.dev.enemy_speed
	var dvv := t * sp
	var dl := dvv.length()
	var max_v := sp * 1.3
	if dl > max_v and dl > 0.0:
		dvv = dvv / dl * max_v
	if absolute:
		vel = dvv
	else:
		vel += (dvv - vel) * (0.18 * s)
	var damp := 1.0 - 0.18 * s
	var k_speed := knock.length()
	var z0 := z
	var g0 := world.map.ground_at(position.x, position.y)
	var airborne0 := g0 == Tuning.VOID_H or z0 > g0 + 0.5 or vz > 0.0
	# knockback (or being mid-air) is the only thing that can carry an enemy over the edge
	var flung := k_speed > 1.5 or airborne0
	var res := _move_body((vel + knock) * s, z0, flung)
	var wall_hit: bool = res[1]
	if wall_hit and k_speed > Tuning.WALL_SPLAT_SPEED:
		# knocked into a wall or cliff face: splat. Bonus damage, longer stun, a crunchy freeze.
		knock = Vector2.ZERO
		freeze = 5
		flash = 6
		if not is_brute() or state == St.RECOVER:
			state = St.STAGGER
			timer = Tuning.WALL_SPLAT_STUN
		Events.push(Ev.WALL_SPLAT, position.x, position.y, k_speed, radius, z)
		if CombatRules.damage_enemy(world, self, Tuning.WALL_SPLAT_DAMAGE):
			return
	elif res[0]:
		knock *= 0.5   # skid along the wall instead of stopping dead
		if data.keep_dist > 0.0 and state == St.APPROACH and world.rng.chance(0.08):
			orbit_dir = -orbit_dir   # backed into a wall: strafe the other way
	knock *= damp

	# ---- height: stairs, drops, knock-ups, falling off the island ----
	var g := world.map.ground_at(position.x, position.y)
	if g == Tuning.VOID_H or z > g + 0.5 or vz > 0.0:
		vz -= Tuning.GRAVITY * s
		z += vz * s
		peak_z = maxf(peak_z, z)
		if g != Tuning.VOID_H and z <= g:
			var drop := peak_z - g
			z = g
			vz = 0.0
			peak_z = g
			if drop > Tuning.FALL_STUN_H and not leap and state != St.LUNGE:
				# heavy landing after being knocked off a ledge
				if not is_brute():
					state = St.STAGGER
					timer = 30
				flash = 4
				Events.push(Ev.LAND, position.x, position.y, drop, radius, g)
				if CombatRules.damage_enemy(world, self, 1.0):
					return
		elif g == Tuning.VOID_H and z < Tuning.FALL_OUT_Z:
			Events.push(Ev.RING_OUT, position.x, position.y, kind, radius, z)
			CombatRules.kill_enemy(world, self, true)
			return
		if g == Tuning.VOID_H or z > g + 0.5:
			return   # no attacking while airborne
	else:
		z = g
		vz = 0.0
		peak_z = g

	# ---- contact / attacks ----
	if p.dead or world.dev.passive or frozen_ai:
		return
	if absf(z - p.z) > 24.0:
		return   # different level: can't touch
	if state == St.LUNGE and atk != null and atk.kind == AttackData.Kind.STRIKE:
		resolve_strike()   # only the wedge it swung at, once
		return
	# no damage just for touching; only a committed attack (a dash) hurts on contact
	var attacking := state == St.LUNGE or (contact_on and (state == St.COMMIT or (kind == 0 and dist < data.charge_dist)))
	var reach := radius + Player.R
	if attacking and dist < reach + 18.0 and p.in_perfect_window():
		p.perfect(self)
		return
	if not contact_on and state != St.LUNGE:
		return
	if dist < reach and atk_cd == 0 and state != St.STAGGER and state != St.WINDUP and state != St.RECOVER:
		var dmg := contact_damage(data.contact_damage)
		if p.hurt(dmg, position):
			vampire(dmg)
			atk_cd = roundi(50.0 / world.diff.atk_rate)
			if state == St.COMMIT and squad < 0:
				state = St.APPROACH


## asleep in its glade: amble to a spot near home, rest, amble again (never attacks)
func _idle(s: float) -> void:
	if flash > 0: flash -= 1
	if age < 65535: age += 1
	timer -= 1
	if timer <= 0:
		var rng := world.rng
		if rng.chance(0.55):
			target = home + Vector2(rng.rangef(-56, 56), rng.rangef(-40, 40))
			timer = 90 + rng.pick(120)
		else:
			target = position
			timer = 60 + rng.pick(120)
	var d := target - position
	var t := d.normalized() * minf(1.0, d.length() / 24.0) if d.length() > 4.0 else Vector2.ZERO
	vel += (t * speed * 0.35 - vel) * (0.12 * s)
	var res := _move_body(vel * s, z, false)
	if res[0]:
		target = position   # bumped into something: stop there
	var g := world.map.ground_at(position.x, position.y)
	if g != Tuning.VOID_H:
		z = g


## move by `delta` world units at height z0. Returns [hit_anything, hit_solid].
func _move_body(delta: Vector2, z0: float, allow_void: bool) -> Array:
	collision_mask = world.collision.mask_for(z0, allow_void)
	velocity = delta * Tuning.TICK_RATE
	move_and_slide()
	var hit := false
	var solid := false
	for i in get_slide_collision_count():
		var kind_hit := RoomCollision.hit_kind(get_slide_collision(i))
		if kind_hit > 0:
			hit = true
			if kind_hit == 2:
				solid = true
	return [hit, solid]
