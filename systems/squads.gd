class_name Squads
extends RefCounted
## Squad brain (prototype: sim/squads.ts): GATHER (pin the front, flankers take the sides)
## -> COMMIT (all in) -> back to GATHER. A perfect dodge knocks a squad into STAGGER.
## world.squads holds one Dictionary per squad: {alive, state, timer, members, front}.

const GATHER := 0
const COMMIT := 1
const STAGGER := 2


static func new_squad() -> Dictionary:
	return {alive = false, state = GATHER, timer = 0, members = 0, front = 0.0}


static func update(world: World) -> void:
	if world.squad_count() == 0 or world.time.frozen():
		return
	var p := world.player
	# census every 8 ticks: front-line centroid + flank readiness
	var census := world.tick_n % 8 == 0
	var sum := {}
	var flank_alive := {}
	var flank_arrived := {}
	if census:
		for e: Enemy in world.enemies:
			if e.squad < 0:
				continue
			if e.role == Enemy.Role.FLANK:
				flank_alive[e.squad] = flank_alive.get(e.squad, 0) + 1
				if e.arrived:
					flank_arrived[e.squad] = flank_arrived.get(e.squad, 0) + 1
			else:
				var acc: Array = sum.get(e.squad, [Vector2.ZERO, 0])
				sum[e.squad] = [acc[0] + e.position, acc[1] + 1]
	for s in world.squads.size():
		var sq: Dictionary = world.squads[s]
		if not sq.alive:
			continue
		if census and sum.has(s):
			var c: Vector2 = sum[s][0] / float(sum[s][1])
			sq.front = (c - p.position).angle()
		match sq.state:
			GATHER:
				sq.timer += 1
				var ready: bool = census and (flank_alive.get(s, 0) == 0 or flank_arrived.get(s, 0) >= flank_alive.get(s, 0)) and sq.timer > 90
				if ready or sq.timer > 480:
					set_state(world, s, COMMIT)
			COMMIT:
				sq.timer += 1
				if sq.timer > 300:
					set_state(world, s, GATHER)
			STAGGER:
				sq.timer -= 1
				if sq.timer <= 0:
					set_state(world, s, GATHER)


static func set_state(world: World, s: int, state: int) -> void:
	var sq: Dictionary = world.squads[s]
	sq.state = state
	sq.timer = 0
	var c := Vector2.ZERO
	var n := 0
	for e: Enemy in world.enemies:
		if e.squad != s:
			continue
		c += e.position
		n += 1
		if state == COMMIT:
			if e.is_brute():
				if e.state == Enemy.St.HOLD:
					e.state = Enemy.St.APPROACH
			else:
				e.state = Enemy.St.COMMIT
				e.timer = 1 << 20
		elif state == GATHER:
			e.arrived = false
			if e.state == Enemy.St.COMMIT or e.state == Enemy.St.STAGGER:
				e.state = Enemy.St.APPROACH
	if state == COMMIT and n > 0:
		c /= n
		Events.push(Ev.SQUAD_COMMIT, c.x, c.y, s, 0, world.map.ground_at(c.x, c.y))


static func member_died(world: World, e: Enemy) -> void:
	if e.squad < 0 or e.squad >= world.squads.size():
		return
	var sq: Dictionary = world.squads[e.squad]
	sq.members -= 1
	world.squad_total_members -= 1
	if sq.members <= 0:
		sq.alive = false
