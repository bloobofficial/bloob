class_name Skills
extends RefCounted
## Job skills (Q / E) and the Warden's totems (prototype: sim/skills.ts).
## Tuning numbers live in each SkillData's params (data/skills/*.tres).


## Cast a skill. Returns the busy (cast lock) ticks, or -1 if it couldn't be cast.
static func cast(world: World, skill: SkillData) -> int:
	var p := world.player
	var mul := p.out_mul()
	var a := p.aim - p.position
	var al := maxf(a.length(), 1.0)
	var ax := a / al
	Events.push(Ev.SKILL_CAST, p.position.x, p.position.y, skill.id, 0, p.z)
	match skill.id:
		SkillData.Id.QUAKE:
			CombatRules.aoe_hit(world, p.position, p.z, {
				radius = skill.p("radius"), damage = skill.p("damage") * mul, knock = skill.p("knock"), knock_up = skill.p("knock_up"),
				stagger = skill.p("stagger"), freeze = 5, breaks_poise = true, step = 5,
			})
			Events.push(Ev.BLAST, p.position.x, p.position.y, skill.p("radius"), 1, p.z)
			world.time.request_hitstop(4, Tuning.Prio.HIT)
			return 14
		SkillData.Id.RALLY:
			p.rally_t = int(skill.p("ticks"))
			p.hp = minf(p.max_hp, p.hp + p.max_hp * skill.p("heal"))
			return 10
		SkillData.Id.TOTEM:
			var at := p.position + ax * 20.0
			var tz := float(world.map.ground_at(at.x, at.y))
			if tz < -1000.0:
				at = p.position
				tz = p.z
			world.plant_totem(at, tz, ax.angle(), int(skill.p("life")), int(skill.p("max")))
			return 12
		SkillData.Id.BULWARK:
			var r := skill.p("radius")
			for e: Enemy in world.enemies:
				var dv := e.position - p.position
				if dv.length_squared() > r * r or absf(e.z - p.z) > 36.0:
					continue
				var n := dv.normalized() if dv.length() > 0.0 else Vector2.RIGHT
				e.knock = n * skill.p("knock") * e.knock_mul * (0.3 if e.is_brute() else 1.0)
				e.state = Enemy.St.STAGGER
				e.timer = int(skill.p("stun"))
				e.leap = false
				e.flash = 4
			p.guard_t = int(skill.p("guard_ticks"))
			Events.push(Ev.BLAST, p.position.x, p.position.y, r, 1, p.z)
			return 14
		SkillData.Id.BLINK:
			# walk the path in small steps so a blink can't pass through walls or off the island
			var origin := p.position
			var oz := p.z
			var steps := 10
			var pos := p.position
			for k in steps:
				var res := world.map.move_circle(pos.x, pos.y, ax.x * skill.p("range") / steps, ax.y * skill.p("range") / steps, Player.R, p.z, false)
				pos = res[0]
			p.global_position = pos
			p.reset_physics_interpolation()
			p.invuln = maxi(p.invuln, int(skill.p("iframes")))
			world.arm_hazard(origin, oz, skill.p("radius"), int(skill.p("fuse")), skill.p("damage"), 1)
			return 4
		SkillData.Id.HEX:
			var reach := minf(260.0, al)
			var c := p.position + ax * reach
			var r := skill.p("radius")
			for e: Enemy in world.enemies:
				if e.position.distance_squared_to(c) > r * r:
					continue
				e.hex_t = int(skill.p("ticks"))
				e.flash = 3
			Events.push(Ev.BLAST, c.x, c.y, r, 2, world.map.ground_at(c.x, c.y))
			return 14
	return -1
