class_name PlayerMelee
extends Node
## Bloob's weapon combo (prototype: sim/player.ts, the melee half + sweepSwing).
## Every weapon is data (WeaponData / SwingData). The hitbox is the blade's path: arcs test
## the slice of angle swept this tick, thrusts a lane out to the current tip, smashes land on
## the last active tick (impact circle + handle lane), rings sweep all the way round.
## Each enemy is hit at most once per swing.

var player: Player
var weapon := 0
var atk_step := 0        ## 0 none, 1..n combo step, AIR_STEP = air swing
var atk_t := -1          ## ticks into the current swing, -1 = not swinging
var atk_buffer := 0
var combo_window := 0
var combo_cd := 0
var atk_dir := Vector2.RIGHT
var self_freeze := 0
var swings := 0
var melee_hits := 0
var last_swing_hits := 0
var _hit_list: Array[Enemy] = []
var _connected := false


func reset() -> void:
	atk_step = 0
	atk_t = -1
	atk_buffer = 0
	combo_window = 0
	combo_cd = 0
	atk_dir = Vector2.RIGHT
	self_freeze = 0
	swings = 0
	melee_hits = 0
	last_swing_hits = 0
	_hit_list.clear()


## drop any swing in progress (dodge, jump, flask, skills, weapon swap)
func cancel() -> void:
	atk_step = 0
	atk_t = -1
	combo_window = 0


func swinging() -> bool:
	return atk_step > 0 and atk_t >= 0


func weapon_data() -> WeaponData:
	return Content.weapons[clampi(weapon, 0, Content.weapons.size() - 1)]


func current_swing() -> SwingData:
	return weapon_data().swing(atk_step)


## 0 none, 1 windup, 2 active, 3 recover
func swing_phase() -> int:
	if not swinging():
		return 0
	var sw := current_swing()
	if atk_t < sw.windup:
		return 1
	if atk_t < sw.windup + sw.active:
		return 2
	return 3


func _start(step: int) -> void:
	atk_step = step
	atk_t = 0
	atk_buffer = 0
	combo_window = 0
	var a := player.aim - player.position
	atk_dir = a / a.length() if a.length() >= 0.001 else player.last_move
	swings += 1
	_hit_list.clear()
	_connected = false
	last_swing_hits = 0


## One tick of the combo. Returns the lunge speed for this tick.
func tick(grounded: bool) -> float:
	var wpn := weapon_data()
	var combo_len := wpn.combo.size()
	var lunge := 0.0
	if swinging():
		atk_t += 1
		var sw := current_swing()
		var total := sw.total_ticks()
		if atk_t == sw.windup:
			Events.push(Ev.SWING, player.position.x, player.position.y, atk_dir.angle(), Ev.pack_swing(weapon, atk_step), player.z)
		if atk_t >= sw.windup and atk_t < sw.windup + sw.active:
			lunge = sw.lunge
			_sweep(sw, atk_t - sw.windup)
		var air := atk_step == Tuning.AIR_STEP
		var chain_at := sw.windup + sw.active + sw.chain_from
		if not air and grounded and atk_step < combo_len and atk_buffer > 0 and atk_t >= chain_at:
			_start(atk_step + 1)
		elif air and not grounded and atk_buffer > 0 and atk_t >= total and player.air_swings < Tuning.MAX_AIR_SWINGS:
			_start(Tuning.AIR_STEP)
			player.air_swings += 1
		elif atk_t >= total:
			if air:
				atk_step = 0
			elif atk_step >= combo_len:
				atk_step = 0
				combo_cd = wpn.combo_end_cd
			else:
				combo_window = wpn.combo_window
			atk_t = -1
	else:
		if combo_window > 0:
			combo_window -= 1
			if combo_window == 0:
				atk_step = 0   # chain dropped
		if atk_buffer > 0 and combo_cd == 0:
			if not grounded:
				if player.air_swings < Tuning.MAX_AIR_SWINGS:
					_start(Tuning.AIR_STEP)
					player.air_swings += 1
			else:
				_start(atk_step + 1 if atk_step > 0 and atk_step < combo_len else 1)
	return lunge


func _sweep(sw: SwingData, k: int) -> void:
	var shape := sw.shape()
	if shape == SwingData.Shape.SMASH and k != sw.active - 1:
		return
	var world := player.world
	var p := player.position
	var ax := atk_dir
	var aim_a := ax.angle()
	var a0 := sw.sweep_at(k)
	var a1 := sw.sweep_at(k + 1)
	var lo := minf(a0, a1)
	var hi := maxf(a0, a1)
	var reach := sw.tip_at(k + 1) if shape == SwingData.Shape.THRUST else sw.range
	var half_w := (sw.width if sw.width > 0.0 else 12.0) * 0.5
	var impact := sw.impact
	var ic := p + ax * maxf(0.0, sw.range - impact)
	var dmg_mul := (Tuning.PERFECT_DAMAGE_MUL if player.buff > 0 else 1.0) * player.out_mul()
	var tag := Ev.pack_swing(weapon, atk_step)
	var hits := 0
	for e: Enemy in world.enemies.duplicate():
		if not e.alive or absf(e.z - player.z) > Tuning.MELEE_Z_REACH:
			continue
		if _hit_list.has(e):
			continue
		var dv := e.position - p
		var d := maxf(dv.length(), 0.001)
		var r := e.radius
		var along := dv.dot(ax)
		var perp := absf(dv.x * ax.y - dv.y * ax.x)
		var inside := false
		if shape == SwingData.Shape.THRUST:
			inside = along >= -r and along <= reach + r and perp <= half_w + r
		elif shape == SwingData.Shape.SMASH:
			inside = (along >= -r and along <= sw.range + r and perp <= half_w + r) or e.position.distance_to(ic) <= impact + r
		else:
			if d > reach + r:
				continue
			# the enemy's angular size at this distance, plus a little for the blade's thickness
			var pad := (asin(r / d) if d > r else PI) + 0.06
			var rel := wrapf(dv.angle() - aim_a, -PI, PI)
			inside = (rel >= lo - pad and rel <= hi + pad) or (rel + TAU >= lo - pad and rel + TAU <= hi + pad) \
				or (rel - TAU >= lo - pad and rel - TAU <= hi + pad)
		if not inside:
			continue
		_hit_list.append(e)
		hits += 1
		var n := dv / d
		var brute := e.is_brute()
		e.flash = 6
		e.freeze = maxi(e.freeze, sw.freeze_enemy)
		# knock mostly away from Bloob, a bit along the swing
		var kd := (n * 0.6 + ax * 0.4)
		kd = kd.normalized() if kd.length() > 0.0 else n
		var force := sw.knock * (sw.brute_knock_mul if brute else 1.0) * e.knock_mul
		e.knock = kd * force
		e.vel *= 0.2
		if sw.knock_up > 0.0 and not brute:
			e.vz = maxf(e.vz, sw.knock_up * e.knock_mul)   # finishers pop them up
		if not brute:
			if e.state != Enemy.St.STAGGER or e.timer < sw.stagger:
				e.state = Enemy.St.STAGGER
				e.timer = sw.stagger
		elif sw.breaks_poise and e.state == Enemy.St.WINDUP:
			# the finisher interrupts a brute's telegraph
			e.state = Enemy.St.STAGGER
			e.timer = 45
			e.cd = Tuning.BRUTE_RECOVER
		Events.push(Ev.MELEE_HIT, e.position.x, e.position.y, kd.angle(), tag, e.z)
		CombatRules.damage_enemy(world, e, sw.damage * dmg_mul)
	if hits > 0:
		player.gain_mana(Tuning.MANA_PER_HIT * hits)
		if not _connected:
			# the first connection of a swing: the stall, the freeze, the air hang
			_connected = true
			self_freeze = sw.freeze_self
			if atk_step == Tuning.AIR_STEP:
				player.vz = maxf(player.vz, Tuning.AIR_HIT_HANG)   # juggling keeps Bloob up
			if sw.hitstop > 0:
				world.time.request_hitstop(sw.hitstop, Tuning.Prio.HIT)
		melee_hits += hits
		last_swing_hits += hits
