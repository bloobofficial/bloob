class_name Player
extends CharacterBody2D
## Bloob (prototype: sim/player.ts): movement, jump (coyote time + buffer), dodge (i-frames +
## perfect window), dive slam, flask, skills, goo spit, damage and the perfect dodge.
## The weapon combo lives in the Melee child (player_melee.gd), drawing in Visual (player_visual.gd).
##
## Units: the prototype's. Positions in world units on the ground plane, `z` = height of the feet,
## timers in ticks, speeds in units per tick. The World calls tick() once per physics frame in
## the prototype's order; movement goes through move_and_slide with velocity = units/tick x 60.

signal died

const R := Tuning.PLAYER_R

var world: World
var z := 0.0
var vz := 0.0
var vel := Vector2.ZERO             ## units per tick (the prototype's vx, vy)
var hp := float(Tuning.BASE_HP)
var max_hp := Tuning.BASE_HP
var mana := float(Tuning.MANA_BASE)
var max_mana := Tuning.MANA_BASE
var dead := false
var god := false
var dodge_t := 0
var dodge_elapsed := 0
var dodge_cd := 0
var dodge_buffer := 0
var dodge_dir := Vector2.ZERO
var perfect_done := false
var perfect_cd := 0
var fire_cd := 0
var invuln := 0
var buff := 0                        ## empowered after a perfect dodge
var aim := Vector2.ZERO              ## ground point
var perfects := 0
var last_move := Vector2.RIGHT
# healing, skills, buffs
var drink_t := 0
var heal_left := 0.0
var heal_rate := 0.0
var busy_t := 0                      ## skill cast lock
var skill_cd := [0, 0]
var cast_skill := -1
var rally_t := 0
var guard_t := 0
var drinks := 0
var casts := 0
var no_mana_t := 0
# jump / air
var jump_buffer := 0
var coyote := 0
var air_swings := 0
var diving := false
var land_lag := 0
var peak_z := 0.0
var jumps := 0
var dives := 0
## scripted input (tests); when null the Input Map is sampled
var scripted: InputFrame = null
var last_input := InputFrame.new()
## set while a panel is over the game: clicks and T belong to the panel, not to Bloob
var block_actions := false

@onready var melee: PlayerMelee = $Melee
@onready var visual: PlayerVisual = $Visual


func setup(w: World) -> void:
	world = w
	melee.player = self
	visual.player = self


func reset_state() -> void:
	z = 0.0; vz = 0.0; vel = Vector2.ZERO
	max_hp = GameState.max_hp
	hp = max_hp
	max_mana = GameState.mana_max
	mana = max_mana
	dead = false
	god = false
	dodge_t = 0; dodge_elapsed = 0; dodge_cd = 0; dodge_buffer = 0
	perfect_done = false; perfect_cd = 0; fire_cd = 0; invuln = 0; buff = 0; perfects = 0
	last_move = Vector2.RIGHT
	drink_t = 0; heal_left = 0.0; heal_rate = 0.0; busy_t = 0; skill_cd = [0, 0]; cast_skill = -1
	rally_t = 0; guard_t = 0; drinks = 0; casts = 0; no_mana_t = 0
	jump_buffer = 0; coyote = 0; air_swings = 0; diving = false; land_lag = 0; peak_z = 0.0; jumps = 0; dives = 0
	melee.reset()


func place(p: Vector2, pz: float) -> void:
	global_position = p
	z = pz
	vz = 0.0
	peak_z = pz
	reset_physics_interpolation()


# ---------------- queries ----------------

## outgoing damage multiplier: level, techs, job, Rally
func out_mul() -> float:
	return GameState.dmg_mul * (_skill_param(SkillData.Id.RALLY, "dmg", 1.4) if rally_t > 0 else 1.0) * world.dev.player_damage


func busy() -> bool:
	return drink_t > 0 or busy_t > 0


func dodging() -> bool:
	return dodge_t > 0


func invulnerable() -> bool:
	return god or invuln > 0 or (dodge_t > 0 and dodge_elapsed < Tuning.DODGE_IFRAMES)


func in_perfect_window() -> bool:
	return dodge_t > 0 and dodge_elapsed < Tuning.PERFECT_WINDOW and not perfect_done and perfect_cd == 0


## the opening stalkers wait for: dodge spent, still on cooldown
func exposed() -> bool:
	return dodge_t == 0 and dodge_cd > 0


func grounded_now() -> bool:
	return z <= world.map.ground_at(position.x, position.y) + 0.5 and vz <= 0.0


func _skill_param(id: int, key: String, fallback: float) -> float:
	return Content.skills[id].p(key, fallback)


func gain_mana(n: float) -> void:
	mana = minf(max_mana, mana + n)


# ---------------- the tick ----------------

func read_input(walking: bool) -> InputFrame:
	var f: InputFrame
	if scripted != null:
		f = scripted
	else:
		f = InputFrame.sample(world.aim_ground(z))
		f.atk = f.atk or Input.is_action_just_pressed(&"attack")
		if block_actions:
			f.atk = false
			f.fire = false
			f.use = false
	last_input = f
	if walking:
		# during a passage walk-out / walk-in Bloob just walks (aim kept, actions dropped)
		var a := InputFrame.new()
		a.move = world.auto_walk_dir()
		a.aim = f.aim
		return a
	return f


func tick(inp: InputFrame) -> void:
	aim = inp.aim
	var wpn := GameState.weapon_data()
	melee.weapon = GameState.weapon
	max_mana = GameState.mana_max
	if mana > max_mana:
		mana = max_mana
	if dead:
		return
	if inp.dodge:
		dodge_buffer = Tuning.DODGE_BUFFER
	if inp.atk:
		melee.atk_buffer = Tuning.ATTACK_BUFFER
	if inp.jump:
		jump_buffer = Tuning.JUMP_BUFFER
	var s := world.time.player_scale
	if s == 0.0:
		return   # frozen in global hitstop (input stays buffered)
	if melee.self_freeze > 0:
		melee.self_freeze -= 1   # Bloob stalls for a beat when a hit connects
		return

	if dodge_cd > 0: dodge_cd -= 1
	if invuln > 0: invuln -= 1
	if buff > 0: buff -= 1
	if fire_cd > 0: fire_cd -= 1
	if perfect_cd > 0: perfect_cd -= 1
	if dodge_buffer > 0: dodge_buffer -= 1
	if melee.atk_buffer > 0: melee.atk_buffer -= 1
	if jump_buffer > 0: jump_buffer -= 1
	if melee.combo_cd > 0: melee.combo_cd -= 1
	if rally_t > 0: rally_t -= 1
	if guard_t > 0: guard_t -= 1
	if drink_t > 0: drink_t -= 1
	if busy_t > 0:
		busy_t -= 1
		if busy_t == 0:
			cast_skill = -1
	if no_mana_t > 0: no_mana_t -= 1
	if skill_cd[0] > 0: skill_cd[0] -= 1
	if skill_cd[1] > 0: skill_cd[1] -= 1
	if world.dev.no_cooldowns:
		skill_cd[0] = 0
		skill_cd[1] = 0
		dodge_cd = mini(dodge_cd, 8)
	if mana < max_mana:
		mana = minf(max_mana, mana + Tuning.MANA_REGEN * s)
	if heal_left > 0.0:
		var hh := minf(heal_left, heal_rate)
		hp = minf(max_hp, hp + hh)
		heal_left -= hh

	var mv := inp.move
	if mv.x != 0.0 and mv.y != 0.0:
		mv *= 0.70710678
	if mv != Vector2.ZERO:
		last_move = mv

	var map := world.map
	var g0 := map.ground_at(position.x, position.y)
	var grounded := z <= g0 + 0.5 and vz <= 0.0
	if grounded:
		coyote = Tuning.COYOTE_TICKS
		air_swings = 0
	elif coyote > 0:
		coyote -= 1

	# after a dive slam Bloob needs a moment to pull itself together
	var lagging := land_lag > 0
	if lagging:
		land_lag -= 1
	var phase := melee.swing_phase()

	# ---- flask (F): drink on the ground, heals over time ----
	if inp.heal and grounded and not lagging and not busy() and not diving and dodge_t == 0 and phase != 2:
		if GameState.flask > 0 and hp < max_hp:
			if not world.dev.infinite_flask:
				GameState.flask -= 1
				GameState.changed.emit()
			melee.cancel()
			drink_t = Tuning.FLASK_LOCK
			heal_left += max_hp * GameState.flask_heal
			heal_rate = max_hp * GameState.flask_heal / Tuning.FLASK_TICKS
			drinks += 1
			Events.push(Ev.DRINK, position.x, position.y, GameState.flask, 0, z)

	# ---- skills (Q / E) from the current job ----
	for slot in 2:
		var pressed := inp.sk1 if slot == 0 else inp.sk2
		if not pressed or skill_cd[slot] > 0 or lagging or busy() or diving or dodge_t > 0 or phase == 2:
			continue
		var skill: SkillData = GameState.job_data().skills[slot]
		var cost := 0 if world.dev.no_cooldowns else skill.mana
		if mana < cost:
			if no_mana_t == 0:
				Events.push(Ev.NO_MANA, position.x, position.y, slot, cost, z)
			no_mana_t = 30
			continue
		melee.cancel()
		var lock := Skills.cast(world, skill)
		if lock < 0:
			continue
		mana -= cost
		busy_t = lock
		cast_skill = skill.id
		casts += 1
		skill_cd[slot] = roundi(skill.cooldown * GameState.cd_mul)

	if not lagging and not busy():
		# ---- dive slam: dodge while airborne and high enough ----
		if not grounded and not diving and dodge_buffer > 0 and z - g0 >= Tuning.DIVE_MIN_HEIGHT and phase != 2:
			diving = true
			dodge_buffer = 0
			melee.cancel()
			vz = -Tuning.DIVE_SPEED
			Events.push(Ev.DIVE_START, position.x, position.y, 0, 0, z)
		# ---- dodge (ground only; cancels a swing's windup or follow-through, never the hit) ----
		if grounded and dodge_t == 0 and dodge_buffer > 0 and dodge_cd == 0 and phase != 2:
			melee.cancel()
			var d := mv
			if d == Vector2.ZERO:
				d = (aim - position)
				d = d / d.length() if d.length() > 0.0 else Vector2.RIGHT
			dodge_dir = d
			dodge_t = Tuning.DODGE_TICKS
			dodge_elapsed = 0
			dodge_cd = Tuning.DODGE_CD
			dodge_buffer = 0
			perfect_done = false
			Events.push(Ev.DODGE, position.x, position.y, d.x, d.y, z)
		# ---- jump (buffered, with coyote time; cancels a swing's windup or follow-through) ----
		if jump_buffer > 0 and (grounded or coyote > 0) and dodge_t == 0 and not diving and phase != 2:
			vz = Tuning.JUMP_VELOCITY
			jump_buffer = 0
			coyote = 0
			air_swings = 0
			melee.cancel()
			peak_z = z
			jumps += 1
			grounded = false
			Events.push(Ev.JUMP, position.x, position.y, 0, 0, z)

	# ---- melee: ground combo, or air swipes while airborne ----
	var lunge := 0.0
	if dodge_t == 0 and not diving and not lagging and not busy():
		lunge = melee.tick(grounded)

	# ---- velocity ----
	var spd := GameState.speed_mul * (_skill_param(SkillData.Id.RALLY, "speed", 1.2) if rally_t > 0 else 1.0) * wpn.move_mul
	if dodge_t > 0:
		var k := 0.55 + 0.45 * (float(dodge_t) / Tuning.DODGE_TICKS)
		vel = dodge_dir * Tuning.DODGE_SPEED * k
		dodge_t -= 1
		dodge_elapsed += 1
	elif lagging or busy_t > 0:
		vel = Vector2.ZERO
	elif drink_t > 0:
		vel = mv * Tuning.SPEED * 0.35
	elif diving:
		vel = mv * Tuning.SPEED * 0.15
	elif melee.swinging():
		vel = mv * Tuning.SPEED * wpn.swing_move_mul + melee.atk_dir * lunge
	elif not grounded:
		vel = mv * Tuning.SPEED * Tuning.AIR_MOVE_MUL * spd
	else:
		vel = mv * Tuning.SPEED * spd

	# move against the terrain: stairs climb, cliffs block (unless you're high enough), the
	# edge of the island always holds
	move_body(vel * s)

	# ---- height: jumps, air hang, dives, stairs, stepping off ledges ----
	var g := map.ground_at(position.x, position.y)
	if z > g + 0.5 or vz > 0.0:
		if diving:
			vz = -Tuning.DIVE_SPEED
		elif melee.swinging() and melee.atk_step == Tuning.AIR_STEP and melee.swing_phase() <= 2:
			vz -= Tuning.GRAVITY * 0.3 * s   # hang during an air swipe
		else:
			vz -= Tuning.GRAVITY * s
		z += vz * s
		peak_z = maxf(peak_z, z)
		if z <= g:
			var drop := peak_z - g
			z = g
			vz = 0.0
			if diving:
				diving = false
				land_lag = Tuning.DIVE_LAND_LAG
				_resolve_dive(drop)
			elif drop > 18.0:
				Events.push(Ev.PLAYER_LAND, position.x, position.y, drop, 0, g)
			peak_z = g
	else:
		# on the ground (stairs and ledge-tops snap up)
		z = g
		vz = 0.0
		peak_z = g
		if diving:
			diving = false
			land_lag = Tuning.DIVE_LAND_LAG
			_resolve_dive(0.0)

	# ---- ranged: goo spit (not while swinging, rolling or diving) ----
	if inp.fire and fire_cd == 0 and not melee.swinging() and dodge_t == 0 and not diving and not lagging and not busy():
		var dir := aim - position
		dir = dir.normalized() if dir.length() > 0.0 else Vector2.RIGHT
		dir = dir.rotated(world.rng.rangef(-0.05, 0.05))
		var dmg := (1.5 if buff > 0 else 1.0) * out_mul() * Tuning.SPIT_DAMAGE
		world.projectiles.spawn(position + dir * 12.0, z + 16.0, dir * Tuning.BULLET_SPEED, Tuning.BULLET_LIFE, dmg, Projectiles.OWNER_PLAYER)
		Events.push(Ev.SHOT, position.x, position.y, dir.x, dir.y, z)
		fire_cd = Tuning.FIRE_EVERY_BUFF if buff > 0 else Tuning.FIRE_EVERY


## move by `delta` world units this tick against the terrain at the current height
func move_body(delta: Vector2) -> void:
	collision_mask = world.collision.mask_for(z, false)
	velocity = delta * Tuning.TICK_RATE
	move_and_slide()


## Dive slam lands: shockwave around Bloob, stronger the higher it came from.
func _resolve_dive(drop: float) -> void:
	var hgt := clampf(drop, 0.0, 96.0)
	var radius := (Tuning.DIVE_RADIUS + hgt * 0.42) * GameState.dive_mul
	var dmg := (Tuning.DIVE_DAMAGE + minf(4.0, hgt / 24.0)) * (Tuning.PERFECT_DAMAGE_MUL if buff > 0 else 1.0) * out_mul()
	var hits := CombatRules.aoe_hit(world, position, z, {
		radius = radius, damage = dmg, knock = Tuning.DIVE_KNOCK, knock_up = Tuning.DIVE_KNOCK_UP, stagger = Tuning.DIVE_STAGGER,
		freeze = 5, breaks_poise = hgt > 40.0, step = 5,
	})
	dives += 1
	melee.melee_hits += hits
	melee.self_freeze = 4
	world.time.request_hitstop(6 if hgt > 40.0 else 4, Tuning.Prio.HIT)
	Events.push(Ev.DIVE_SLAM, position.x, position.y, radius, hits, z)


## returns true if damage was applied
func hurt(dmg: float, from: Vector2) -> bool:
	if dead or invulnerable():
		return false
	hp -= dmg * 0.5 if guard_t > 0 else dmg
	drink_t = 0   # getting hit spills the flask (the heal already started keeps going)
	invuln = Tuning.HURT_IFRAMES
	var d := position - from
	d = d.normalized() if d.length() > 0.0 else Vector2.ZERO
	Events.push(Ev.PLAYER_HURT, position.x, position.y, d.x, d.y, z)
	if hp <= 0.0:
		hp = 0.0
		dead = true
		world.time.request_hitstop(24, Tuning.Prio.BOSS)
		Events.push(Ev.PLAYER_DEATH, position.x, position.y, 0, 0, z)
		died.emit()
	else:
		world.time.request_hitstop(4, Tuning.Prio.HURT)
	return true


## An attack met the perfect window: freeze, slow-mo, shockwave, squads reel.
func perfect(by_enemy: Enemy) -> void:
	perfect_done = true
	perfect_cd = Tuning.PERFECT_COOLDOWN
	perfects += 1
	buff = Tuning.PERFECT_SLOWMO + Tuning.PERFECT_HITSTOP
	invuln = maxi(invuln, 20)
	world.time.request_hitstop(Tuning.PERFECT_HITSTOP, Tuning.Prio.PERFECT)
	world.time.request_slowmo(Tuning.PERFECT_SLOWMO, Tuning.PERFECT_SLOWMO_SCALE)
	Events.push(Ev.PERFECT_DODGE, position.x, position.y, 0, 0, z)
	var brain := world.mode.brain
	var staggered := {}
	for e: Enemy in world.enemies:
		var d := e.position - position
		var d2 := d.length_squared()
		if d2 < Tuning.SHOCKWAVE_R * Tuning.SHOCKWAVE_R:
			var n := d.normalized() if d2 > 0.0 else Vector2.RIGHT
			e.knock += n * (3.0 if e.is_brute() else 8.0)
			if e.state == Enemy.St.COMMIT or e.state == Enemy.St.LUNGE:
				e.state = Enemy.St.STAGGER
				e.timer = 30
		# brain layer: a squad that got read falls apart for a moment
		if brain > 0 and e.squad >= 0 and d2 < Tuning.SQUAD_STAGGER_R * Tuning.SQUAD_STAGGER_R:
			var sq: Dictionary = world.squads[e.squad]
			if sq.state != Squads.STAGGER:
				sq.state = Squads.STAGGER
				sq.timer = Tuning.STAGGER_TICKS
				staggered[e.squad] = true
				Events.push(Ev.SQUAD_STAGGER, e.position.x, e.position.y, e.squad, 0, e.z)
	# the brute you slipped past is wide open
	if by_enemy != null and is_instance_valid(by_enemy) and by_enemy.alive and (by_enemy.is_brute() or by_enemy.state == Enemy.St.LUNGE):
		by_enemy.state = Enemy.St.RECOVER
		by_enemy.timer = Tuning.BRUTE_RECOVER * 2
		by_enemy.leap = false
	# squad stagger applies to every member
	if brain > 0:
		for e: Enemy in world.enemies:
			if e.squad >= 0 and staggered.has(e.squad) and e.state != Enemy.St.RECOVER:
				e.state = Enemy.St.STAGGER
				e.timer = Tuning.STAGGER_TICKS
