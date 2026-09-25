extends SceneTree
## One-time migration tool: writes the prototype's content tables (mayhem-engine v0.9
## src/content/*.ts) as Godot resources under res://data. Run with:
##   godot --headless -s res://tools/port_content.gd
## After it has run, the .tres files are the source of truth (edit them in the Inspector).

const OUT := "res://data/"


func _initialize() -> void:
	for d in ["weapons", "enemies", "attacks", "skills", "jobs", "techs", "rooms", "themes", "modes", "tiers"]:
		DirAccess.make_dir_recursive_absolute(OUT + d)
	var modes := _modes()
	var tiers := _tiers()
	var attacks := _attacks()
	_enemies(attacks)
	_weapons()
	var skills := _skills()
	_jobs(skills)
	_techs()
	var themes := _themes()
	_rooms(themes, modes)
	print("content written")
	quit(0)


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, OUT + path)
	if err != OK:
		push_error("save failed %s: %d" % [path, err])


# ---------------- swings & weapons (content/combat.ts, content/weapons.ts) ----------------

func _sw(d: Dictionary) -> SwingData:
	var s := SwingData.new()
	# base values shared by every weapon swing in the prototype's `base` object
	s.freeze_enemy = 3
	s.freeze_self = 2
	s.hitstop = 0
	s.knock_up = 0.0
	s.brute_knock_mul = 0.15
	s.breaks_poise = false
	for k in d:
		if k == "vis":
			var v: Array = d[k]
			s.has_vis = true
			s.vis_from = v[0]
			s.vis_to = v[1]
			s.vis_lift = v[2] if v.size() > 2 else 0.0
			s.vis_thrust = v[3] if v.size() > 3 else 0.0
		else:
			s.set(k, d[k])
	return s


func _weapon(id: String, name: String, blurb: String, combo: Array, air: SwingData, move_mul: float, swing_move_mul: float,
		window: int, end_cd: int, cost: Array, sprite: String, held: bool, scale: float, grip: float, rest: float,
		rim: Color, trail: Color, glow: Color, heavy_glow: Color, traits: String) -> WeaponData:
	var w := WeaponData.new()
	w.id = id; w.name = name; w.blurb = blurb
	var typed: Array[SwingData] = []
	for s in combo:
		typed.append(s)
	w.combo = typed
	w.air = air
	w.move_mul = move_mul; w.swing_move_mul = swing_move_mul
	w.combo_window = window; w.combo_end_cd = end_cd
	w.cost = PackedInt32Array(cost)
	w.sprite = sprite; w.held = held; w.art_scale = scale; w.grip = grip; w.rest = rest
	w.fx_rim = rim; w.fx_trail = trail; w.fx_glow = glow; w.fx_heavy_glow = heavy_glow
	w.traits = traits
	return w


func _weapons() -> void:
	var crimson := [Color(0.91, 0.12, 0.24), Color(0.95, 0.4, 0.45), Color(1, 0.25, 0.35), Color(1, 0.3, 0.3)]
	var paws := _weapon("paws", "Goo Paws", "Bloob's own claws. Swipe, Backswipe, Slam.", [
		_sw({name = "Swipe", windup = 3, active = 3, recover = 10, chain_from = 4, range = 46.0, arc = 1.0, damage = 1.5, knock = 3.6, stagger = 10, lunge = 2.4,
			vis = [-1.05, 0.95, 0.3]}),
		_sw({name = "Backswipe", windup = 3, active = 3, recover = 11, chain_from = 4, range = 50.0, arc = 1.1, damage = 1.5, knock = 4.6, stagger = 12, lunge = 2.6,
			vis = [1.15, -1.0, 0.3]}),
		_sw({name = "Slam", windup = 8, active = 4, recover = 20, chain_from = 99, range = 66.0, arc = 1.75, damage = 3.5, knock = 14.0, stagger = 36, lunge = 4.2,
			freeze_enemy = 6, freeze_self = 4, hitstop = 4, knock_up = 4.2, brute_knock_mul = 0.35, breaks_poise = true, impact = 38.0, vis = [0.0, 0.0, 1.0]}),
	], _sw({name = "Air Swipe", windup = 2, active = 3, recover = 7, chain_from = 99, range = 50.0, arc = 1.25, damage = 1.5, knock = 4.2, stagger = 16, lunge = 1.2,
			knock_up = 3.2, vis = [-1.25, 1.2, 0.4]}),
		1.0, Tuning.SWING_MOVE_MUL, Tuning.COMBO_WINDOW, Tuning.COMBO_END_COOLDOWN, [0, 0, 0, 0],
		"weapon.paws", false, 0.3, 0.1, 0.0, crimson[0], crimson[1], crimson[2], crimson[3], "3 hits · balanced · finisher launches")
	# v0.9 treats the Paws Slam as the finisher by index (w == 0 && step == 3); here it is data
	paws.combo[2].heavy = true
	_save(paws, "weapons/paws.tres")

	var sword := _weapon("sword", "Thorn Sword", "Quick cuts with a long reach, ending in a thrust.", [
		_sw({name = "Cut", windup = 3, active = 3, recover = 9, chain_from = 3, range = 58.0, arc = 1.05, damage = 1.8, knock = 3.2, stagger = 12, lunge = 2.6,
			vis = [-1.35, 1.1, 0.35]}),
		_sw({name = "Reverse Cut", windup = 3, active = 3, recover = 9, chain_from = 3, range = 58.0, arc = 1.05, damage = 1.8, knock = 3.8, stagger = 12, lunge = 2.6,
			vis = [1.3, -1.1, 0.35]}),
		_sw({name = "Thorn Thrust", windup = 6, active = 4, recover = 16, chain_from = 99, range = 78.0, arc = 0.3, width = 20.0, damage = 3.0, knock = 11.0, stagger = 30,
			lunge = 5.5, freeze_enemy = 5, freeze_self = 3, hitstop = 3, knock_up = 1.5, brute_knock_mul = 0.3, breaks_poise = true, heavy = true, pose = 2,
			vis = [0.0, 0.0, 0.1, 22.0]}),
	], _sw({name = "Air Cut", windup = 2, active = 3, recover = 7, chain_from = 99, range = 56.0, arc = 1.25, damage = 1.6, knock = 4.0, stagger = 16, lunge = 1.2,
			knock_up = 3.2, vis = [-1.4, 1.2, 0.5]}),
		1.0, 0.32, 16, 8, [40, 4, 0, 0], "weapon.sword", true, 0.5, 0.19, 0.5,
		crimson[0], crimson[1], crimson[2], crimson[3], "3 hits · fast · good reach · thrust finisher")
	_save(sword, "weapons/sword.tres")

	var spear := _weapon("spear", "Bone Spear", "Keeps them at a distance. Jab, jab, sweep, impale.", [
		_sw({name = "Jab", windup = 4, active = 3, recover = 8, chain_from = 3, range = 88.0, arc = 0.3, width = 16.0, damage = 1.3, knock = 3.0, stagger = 10, lunge = 1.5,
			vis = [0.0, 0.0, 0.0, 26.0]}),
		_sw({name = "Jab", windup = 4, active = 3, recover = 8, chain_from = 3, range = 88.0, arc = 0.3, width = 16.0, damage = 1.3, knock = 3.0, stagger = 10, lunge = 1.5,
			pose = 1, vis = [0.05, 0.05, 0.0, 26.0]}),
		_sw({name = "Sweep", windup = 5, active = 4, recover = 10, chain_from = 4, range = 80.0, arc = 1.4, damage = 1.6, knock = 5.0, stagger = 14, lunge = 1.0,
			pose = 0, vis = [-1.6, 1.5, 0.1]}),
		_sw({name = "Impaler", windup = 9, active = 4, recover = 20, chain_from = 99, range = 102.0, arc = 0.28, width = 20.0, damage = 2.6, knock = 13.0, stagger = 34,
			lunge = 7.5, freeze_enemy = 5, freeze_self = 3, hitstop = 3, knock_up = 1.0, brute_knock_mul = 0.35, breaks_poise = true, heavy = true, pose = 2,
			vis = [0.0, 0.0, 0.0, 36.0]}),
	], _sw({name = "Air Jab", windup = 3, active = 3, recover = 8, chain_from = 99, range = 84.0, arc = 0.35, width = 18.0, damage = 1.6, knock = 4.0, stagger = 14,
			lunge = 1.0, knock_up = 2.4, vis = [0.0, 0.0, 0.0, 26.0]}),
		0.96, 0.28, 16, 10, [60, 0, 6, 0], "weapon.spear", true, 0.78, 0.3, 0.25,
		Color(1, 0.6, 0.16), Color(1, 0.8, 0.5), Color(1, 0.75, 0.35), Color(1, 0.65, 0.3), "4 hits · longest reach · thrusts")
	_save(spear, "weapons/spear.tres")

	var hammer := _weapon("hammer", "Grave Hammer", "Slow. Honest. Crush, then shake the ground around you.", [
		_sw({name = "Crush", windup = 10, active = 4, recover = 14, chain_from = 5, range = 62.0, arc = 1.2, damage = 2.8, knock = 8.0, stagger = 26, lunge = 2.0,
			freeze_enemy = 5, freeze_self = 4, hitstop = 2, knock_up = 2.5, brute_knock_mul = 0.4, breaks_poise = true, pose = 2, impact = 28.0,
			vis = [0.0, 0.0, 1.0]}),
		_sw({name = "Graveshaker", windup = 16, active = 4, recover = 24, chain_from = 99, range = 82.0, arc = PI, damage = 4.4, knock = 16.0, stagger = 44,
			lunge = 0.0, freeze_enemy = 7, freeze_self = 5, hitstop = 6, knock_up = 5.0, brute_knock_mul = 0.6, breaks_poise = true, heavy = true, pose = 2,
			vis = [-PI, PI, 0.2]}),
	], _sw({name = "Meteor", windup = 4, active = 3, recover = 10, chain_from = 99, range = 60.0, arc = 1.3, damage = 2.4, knock = 7.0, stagger = 24, lunge = 0.6,
			knock_up = 1.0, freeze_enemy = 4, hitstop = 2, breaks_poise = true, pose = 2, impact = 30.0, vis = [0.0, 0.0, 1.0]}),
		0.88, 0.15, 18, 14, [90, 10, 0, 1], "weapon.hammer", true, 0.58, 0.16, 0.55,
		Color(0.6, 0.34, 1), Color(0.75, 0.62, 1), Color(0.7, 0.5, 1), Color(0.8, 0.45, 1), "2 hits · slow · huge knockback · ring finisher")
	_save(hammer, "weapons/hammer.tres")

	var bite := {name = "Bite", windup = 2, active = 2, recover = 5, chain_from = 2, range = 44.0, arc = 0.95, damage = 1.1, knock = 1.6, stagger = 8, lunge = 2.2,
		freeze_enemy = 2, freeze_self = 1}
	var b0 := bite.duplicate(); b0.pose = 0; b0.vis = [-1.1, 0.9, 0.2]
	var b1 := bite.duplicate(); b1.pose = 1; b1.vis = [1.1, -0.9, 0.2]
	var daggers := _weapon("daggers", "Twin Fangs", "Five fast bites. Stay close, stay moving.", [
		_sw(b0), _sw(b1), _sw(b0), _sw(b1),
		_sw({name = "Crossbite", windup = 4, active = 3, recover = 14, chain_from = 99, range = 50.0, arc = 1.3, damage = 2.2, knock = 6.0, stagger = 22, lunge = 4.0,
			hitstop = 2, freeze_enemy = 4, knock_up = 1.5, heavy = true, pose = 2, vis = [-1.4, 1.4, 0.3]}),
	], _sw({name = "Fang Flurry", windup = 1, active = 3, recover = 5, chain_from = 99, range = 46.0, arc = 1.2, damage = 1.2, knock = 3.0, stagger = 12, lunge = 1.4,
			knock_up = 3.0, vis = [-1.2, 1.2, 0.4]}),
		1.12, 0.4, 14, 6, [70, 0, 8, 0], "weapon.daggers", true, 0.36, 0.21, 0.6,
		Color(1, 0.28, 0.68), Color(1, 0.6, 0.85), Color(1, 0.4, 0.75), Color(1, 0.35, 0.7), "5 hits · fastest · short reach · run faster")
	_save(daggers, "weapons/daggers.tres")


# ---------------- enemies & attacks ----------------

func _attacks() -> Dictionary:
	var K := AttackData.Kind
	var rows := [
		["gore", "Gore Dash", K.DASH, 190, 26, 16, 34, [150, 260], 12, 6.5, 0, 0, 0.0, false, 0.8],
		["spit", "Spit", K.SHOOT, 280, 22, 1, 24, [140, 240], 8, 4.6, 0, 1, 0.0, false, 0.8],
		["spray", "Spray", K.SHOOT, 240, 28, 1, 30, [200, 320], 7, 4.2, 0, 3, 0.32, false, 0.8],
		["stab", "Stab Dash", K.DASH, 120, 16, 10, 26, [120, 200], 9, 7.0, 0, 0, 0.0, false, 0.8],
		["swoop", "Swoop", K.DASH, 210, 22, 20, 30, [160, 260], 9, 6.0, 0, 0, 0.0, false, 0.8],
		["pounce", "Pounce", K.LEAP, 240, 30, 26, 40, [220, 340], 14, 0.0, 40, 0, 0.0, false, 0.8],
		["lunge", "Lunge", K.DASH, 270, 42, 16, 50, [110, 170], 22, 8.5, 0, 0, 0.0, true, 0.8],
		["quake", "Ground Slam", K.SLAM, 110, 46, 1, 56, [150, 230], 20, 0.0, 88, 0, 0.0, true, 0.8],
		["butt", "Headbutt", K.STRIKE, 46, 24, 3, 34, [120, 200], 9, 2.0, 0, 0, 0.0, false, 0.6],
		["lash", "Lash", K.STRIKE, 56, 20, 3, 30, [110, 190], 7, 1.5, 0, 0, 0.0, false, 0.9],
		["slash", "Slash", K.STRIKE, 46, 16, 3, 28, [100, 170], 7, 2.6, 0, 0, 0.0, false, 0.75],
		["peck", "Peck", K.STRIKE, 44, 18, 3, 30, [110, 180], 7, 2.0, 0, 0, 0.0, false, 0.7],
		["rend", "Rend", K.STRIKE, 52, 22, 3, 34, [130, 210], 11, 2.0, 0, 0, 0.0, false, 0.85],
		["smash", "Smash", K.STRIKE, 74, 36, 4, 50, [120, 200], 18, 1.5, 0, 0, 0.0, true, 1.1],
	]
	var out := {}
	for r in rows:
		var a := AttackData.new()
		a.id = r[0]; a.name = r[1]; a.kind = r[2]; a.range = r[3]; a.windup = r[4]; a.active = r[5]; a.recover = r[6]
		a.cooldown = Vector2i(r[7][0], r[7][1]); a.damage = r[8]; a.speed = r[9]; a.radius = r[10]; a.shots = r[11]
		a.spread = r[12]; a.heavy = r[13]; a.arc = r[14]
		_save(a, "attacks/%s.tres" % a.id)
		out[a.id] = load(OUT + "attacks/%s.tres" % a.id)
	return out


func _enemies(atk: Dictionary) -> void:
	# name, color, radius, hp, speed, routes, weaveAmp, weaveFreq, chargeDist, chargeMul, orbitR, orbitTicks, holdDist, holdTicks, contact,
	# attacks [[id, w]], loot [ichor lo, hi, extra, extraChance, shard, heal], xp, art [id, scale, hover]
	var rows := [
		["Charger", Color(1.0, 0.55, 0.25), 9, 13, 1.55, [1, 0, 0, 0], 0.0, 0.0, 170, 1.8, 0, [0, 0], 0, [0, 0], 8,
			[["butt", 5], ["gore", 5]], [4, 6, 1, 0.55, 0.02, 0.22], 4, ["charger", 0.46, 0]],
		["Weaver", Color(0.78, 0.9, 0.35), 7, 12, 1.8, [3, 1, 1, 0], 0.95, 0.11, 0, 1.0, 0, [0, 0], 0, [0, 0], 6,
			[["spit", 5], ["spray", 3], ["lash", 2]], [4, 6, 2, 0.55, 0.02, 0.22], 4, ["weaver", 0.44, 0]],
		["Flanker", Color(0.3, 0.85, 0.95), 7, 12, 2.05, [0, 2, 2, 1], 0.15, 0.05, 120, 1.4, 0, [0, 0], 0, [0, 0], 6,
			[["stab", 6], ["slash", 4]], [4, 6, 2, 0.6, 0.02, 0.22], 4, ["flanker", 0.42, 0]],
		["Circler", Color(0.7, 0.5, 1.0), 8, 12, 1.85, [2, 1, 1, 0], 0.0, 0.0, 0, 1.5, 150, [100, 220], 0, [0, 0], 8,
			[["swoop", 5], ["spit", 3], ["peck", 2]], [4, 7, 2, 0.6, 0.03, 0.25], 6, ["circler", 0.44, 12]],
		["Stalker", Color(1.0, 0.45, 0.7), 8, 15, 1.6, [2, 1, 1, 0], 0.0, 0.0, 0, 1.9, 0, [0, 0], 230, [180, 420], 10,
			[["pounce", 6], ["gore", 2], ["rend", 2]], [5, 8, 1, 0.65, 0.04, 0.28], 6, ["stalker", 0.56, 0]],
		["Brute", Color(0.95, 0.22, 0.22), 19, 36, 0.95, [1, 0, 0, 0], 0.0, 0.0, 0, 1.0, 0, [0, 0], 0, [0, 0], 22,
			[["lunge", 5], ["quake", 3], ["smash", 4]], [12, 18, 1, 1.0, 0.35, 0.7], 30, ["brute", 0.98, 0]],
	]
	for i in rows.size():
		var r: Array = rows[i]
		var e := EnemyKindData.new()
		e.kind_index = i
		e.name = r[0]; e.color = r[1]; e.radius = r[2]; e.hp = r[3]; e.speed = r[4]
		e.routes = PackedFloat32Array(r[5]); e.weave_amp = r[6]; e.weave_freq = r[7]
		e.charge_dist = r[8]; e.charge_mul = r[9]; e.orbit_radius = r[10]; e.orbit_ticks = Vector2i(r[11][0], r[11][1])
		e.hold_dist = r[12]; e.hold_ticks = Vector2i(r[13][0], r[13][1]); e.contact_damage = r[14]
		var list: Array[AttackData] = []
		var weights := PackedFloat32Array()
		for pair in r[15]:
			list.append(atk[pair[0]])
			weights.append(pair[1])
		e.attacks = list
		e.attack_weights = weights
		var L: Array = r[16]
		e.loot_ichor = Vector2i(L[0], L[1]); e.loot_extra = L[2]; e.loot_extra_chance = L[3]; e.loot_shard_chance = L[4]; e.loot_heal_chance = L[5]
		e.kill_xp = r[17]
		e.id = r[18][0]; e.sprite_scale = r[18][1]; e.hover = r[18][2]; e.anchor = 0.06
		_save(e, "enemies/%s.tres" % e.id)


# ---------------- skills, jobs, techs (content/progression.ts) ----------------

func _skills() -> Array:
	var S := SkillData.Id
	var rows := [
		[S.QUAKE, "Quake", "Shockwave around Bloob: damage, knock back and pop up.", 240, 20, {radius = 92.0, damage = 3.0, knock = 9.0, knock_up = 5.0, stagger = 40.0}],
		[S.RALLY, "Rally", "+40% damage and +20% speed for 5 s, heal 10%.", 600, 30, {ticks = 300.0, dmg = 1.4, speed = 1.2, heal = 0.1}],
		[S.TOTEM, "Totem", "Plant a goo totem that shoots the nearest enemy for 12 s.", 420, 25, {life = 720.0, every = 14.0, range = 280.0, damage = 1.2, max = 2.0}],
		[S.BULWARK, "Bulwark", "Stun everything close and take half damage for 1.5 s.", 480, 25, {radius = 110.0, stun = 60.0, knock = 6.0, guard_ticks = 90.0, guard_mul = 0.5}],
		[S.BLINK, "Blink", "Teleport toward the aim; your old spot explodes.", 180, 15, {range = 150.0, iframes = 12.0, fuse = 30.0, radius = 70.0, damage = 3.0}],
		[S.HEX, "Hex", "Curse enemies near the aim: +50% damage taken, slowed.", 480, 20, {radius = 120.0, ticks = 300.0, dmg_taken = 1.5, slow = 0.6}],
	]
	var out := []
	for r in rows:
		var s := SkillData.new()
		s.id = r[0]; s.name = r[1]; s.desc = r[2]; s.cooldown = r[3]; s.mana = r[4]; s.params = r[5]
		var path := "skills/%s.tres" % s.name.to_lower()
		_save(s, path)
		out.append(load(OUT + path))
	return out


func _jobs(skills: Array) -> void:
	var rows := [
		["brawler", "Brawler", "Close and heavy. Quake and Rally.", 1.0, 1.0, 1.0, 1.0, [0, 1], ""],
		["warden", "Warden", "Holds ground with totems. Tough, a bit slower.", 1.25, 0.92, 0.95, 0.9, [2, 3], "warden"],
		["trickster", "Trickster", "Fast and fragile. Blink and Hex.", 0.85, 1.12, 1.1, 1.25, [4, 5], "trickster"],
	]
	for r in rows:
		var j := JobData.new()
		j.id = r[0]; j.name = r[1]; j.blurb = r[2]; j.hp_mul = r[3]; j.speed_mul = r[4]; j.dmg_mul = r[5]; j.mana_mul = r[6]
		var list: Array[SkillData] = [skills[r[7][0]], skills[r[7][1]]]
		j.skills = list
		j.unlock = r[8]
		_save(j, "jobs/%s.tres" % j.id)


func _techs() -> void:
	var rows := [
		["vigor1", "Thick Goo", "+20 max HP", [30, 0, 0, 0], []],
		["flask1", "Deeper Flask", "+1 flask charge", [40, 5, 0, 0], []],
		["claws1", "Sharper Claws", "+15% damage", [50, 8, 0, 0], []],
		["magnet1", "Sticky Membrane", "Pickups fly to you from twice as far", [25, 0, 4, 0], []],
		["slam1", "Heavier Landing", "Dive slam radius +25%", [45, 6, 0, 0], []],
		["warden", "Way of the Warden", "Unlocks the Warden job", [60, 10, 6, 0], []],
		["trickster", "Way of the Trickster", "Unlocks the Trickster job", [60, 0, 12, 0], []],
		["skills1", "Quick Rituals", "Skills recharge 20% faster", [80, 0, 10, 1], []],
		["mana1", "Brimming Goo", "+25 max mana", [40, 0, 6, 0], []],
		["vigor2", "Dense Goo", "+30 max HP", [90, 14, 0, 1], ["vigor1"]],
		["claws2", "Relic Claws", "+20% damage", [120, 18, 0, 2], ["claws1"]],
		["flask2", "Bottomless Flask", "+1 flask charge, flasks heal 50%", [100, 8, 8, 1], ["flask1"]],
	]
	for i in rows.size():
		var r: Array = rows[i]
		var t := TechData.new()
		t.id = r[0]; t.name = r[1]; t.desc = r[2]; t.cost = PackedInt32Array(r[3]); t.req = PackedStringArray(r[4])
		_save(t, "techs/%02d_%s.tres" % [i, t.id])


# ---------------- difficulty & director presets ----------------

func _tiers() -> Array:
	var rows := [
		["Wary", 1.0, 0.9, 0.85, 0.95, false, 0.02, 0.1, 3],
		["Restless", 1.1, 1.0, 1.0, 1.0, true, 0.06, 0.25, 4],
		["Grim", 1.22, 1.1, 1.12, 1.04, true, 0.16, 0.4, 4],
		["Dire", 1.38, 1.22, 1.25, 1.08, true, 0.24, 0.55, 4],
		["Nightmare", 1.6, 1.36, 1.4, 1.12, true, 0.32, 0.7, 4],
	]
	var out := []
	for i in rows.size():
		var r: Array = rows[i]
		var t := TierData.new()
		t.name = r[0]; t.hp_mul = r[1]; t.dmg_mul = r[2]; t.atk_rate = r[3]; t.speed_mul = r[4]; t.squads = r[5]
		t.elite_chance = r[6]; t.two_affix_chance = r[7]; t.max_alive = r[8]
		_save(t, "tiers/tier%d.tres" % (i + 1))
		out.append(t)
	return out


func _modes() -> Dictionary:
	var rows := [
		["skirmish", "Skirmish", "About four at a time. Each one matters.", 2, 4, 0.12, 1, 40, [30, 25, 18, 12, 12, 3], 1, 1, 900, 1, 0, false, true, true, true, false],
		["zombie", "Zombie", "Big horde. Personality and crowd flow do the work.", 120, 1400, 14.0, 18, 12, [30, 30, 18, 12, 9, 1], 0, 0, 0, 0, 0, false, true, true, false, true],
		["tactical", "Tactical", "Few enemies, real squads. Pin, flank, commit.", 0, 0, 0.0, 0, 0, [0, 0, 0, 0, 0, 0], 2, 7, 420, 1, 0, false, true, true, false, true],
		["hybrid", "Hybrid", "A horde with smart squads mixed in.", 80, 600, 8.0, 12, 14, [30, 30, 18, 12, 9, 0], 1, 4, 600, 1, 0, false, true, true, false, true],
		["stress", "Stress", "Stress test: a big horde and bullet sprayers. God mode.", 2000, 2000, 0.0, 200, 2, [30, 30, 18, 12, 9, 1], 0, 0, 0, 0, 8, true, false, false, false, true],
		["calm", "Calm", "No encounter.", 0, 0, 0.0, 0, 0, [0, 0, 0, 0, 0, 0], 0, 0, 0, 0, 0, false, true, true, false, true],
	]
	var out := {}
	for r in rows:
		var m := ModeData.new()
		m.id = r[0]; m.label = r[1]; m.blurb = r[2]; m.horde_start = r[3]; m.horde_max = r[4]; m.horde_ramp_per_sec = r[5]
		m.spawn_burst = r[6]; m.spawn_every = r[7]; m.mix = PackedFloat32Array(r[8]); m.squads_start = r[9]; m.squads_max = r[10]
		m.squad_every = r[11]; m.brain = r[12]; m.emitters = r[13]; m.god_mode = r[14]; m.patterns = r[15]; m.loot = r[16]
		m.cap_all = r[17]; m.contact = r[18]
		_save(m, "modes/%s.tres" % m.id)
		out[m.id] = load(OUT + "modes/%s.tres" % m.id)
	return out


# ---------------- themes & rooms (content/rooms.ts) ----------------

func _c(a: Array) -> Color:
	return Color(a[0], a[1], a[2])


func _themes() -> Dictionary:
	var base := {
		floor = [0.22, 0.26, 0.24], plateau = [0.33, 0.34, 0.3], high = [0.4, 0.38, 0.33], stairs = [0.37, 0.33, 0.29], path = [0.34, 0.29, 0.2],
		wall = [0.27, 0.24, 0.31], wall_side = [0.2, 0.18, 0.25], cliff = [0.27, 0.22, 0.21],
		foliage = [0.1, 0.15, 0.11], water = [0.13, 0.24, 0.27], tree = [0.8, 0.95, 0.82], fog = [0.05, 0.045, 0.07],
	}
	var over := {
		base = {},
		sanctum = {floor = [0.26, 0.27, 0.22], plateau = [0.36, 0.34, 0.28], path = [0.42, 0.35, 0.25], foliage = [0.12, 0.16, 0.11], tree = [0.88, 0.96, 0.8], fog = [0.07, 0.055, 0.065]},
		forge = {floor = [0.26, 0.23, 0.21], path = [0.38, 0.3, 0.22], wall = [0.31, 0.25, 0.23], wall_side = [0.22, 0.16, 0.15], foliage = [0.13, 0.12, 0.1], tree = [0.9, 0.85, 0.75], fog = [0.07, 0.045, 0.04]},
		lounge = {floor = [0.25, 0.28, 0.24], path = [0.42, 0.36, 0.28], water = [0.17, 0.3, 0.36], tree = [0.8, 1.0, 0.86], fog = [0.05, 0.055, 0.075]},
		moss = {floor = [0.21, 0.27, 0.21], path = [0.36, 0.31, 0.23], foliage = [0.09, 0.15, 0.1], tree = [0.74, 0.95, 0.76], fog = [0.04, 0.05, 0.06]},
		mire = {floor = [0.2, 0.24, 0.19], path = [0.33, 0.3, 0.22], water = [0.1, 0.2, 0.19], foliage = [0.08, 0.13, 0.09], tree = [0.68, 0.85, 0.62], fog = [0.035, 0.055, 0.05]},
		way = {floor = [0.24, 0.26, 0.25], path = [0.4, 0.34, 0.26], tree = [0.82, 0.92, 0.9], fog = [0.05, 0.05, 0.07]},
		thorn = {floor = [0.24, 0.22, 0.2], path = [0.36, 0.28, 0.22], foliage = [0.13, 0.09, 0.09], tree = [0.98, 0.68, 0.66], fog = [0.06, 0.035, 0.045]},
		barrow = {floor = [0.23, 0.23, 0.25], plateau = [0.33, 0.32, 0.36], wall = [0.31, 0.29, 0.34], wall_side = [0.21, 0.2, 0.25], path = [0.32, 0.3, 0.3], foliage = [0.1, 0.11, 0.12], tree = [0.74, 0.78, 0.86], fog = [0.04, 0.04, 0.06]},
		overlook = {floor = [0.29, 0.27, 0.2], plateau = [0.36, 0.33, 0.25], high = [0.43, 0.39, 0.3], path = [0.44, 0.36, 0.24], foliage = [0.17, 0.12, 0.08], tree = [1.0, 0.8, 0.55], fog = [0.08, 0.06, 0.075]},
	}
	var out := {}
	for id in over:
		var d := base.duplicate()
		d.merge(over[id], true)
		var t := ThemeData.new()
		t.id = id
		for k in d:
			t.set(k, _c(d[k]))
		_save(t, "themes/%s.tres" % id)
		out[id] = load(OUT + "themes/%s.tres" % id)
	return out


func _enc(modes: Dictionary, preset: String, budget: int, max_alive: int, start_alive: int, ramp: float, squads: int, tier: int, mix: Array) -> EncounterData:
	var e := EncounterData.new()
	e.preset = modes[preset]
	e.budget = budget; e.max_alive = max_alive; e.start_alive = start_alive; e.ramp_per_sec = ramp; e.squads = squads; e.tier = tier
	e.mix = PackedFloat32Array(mix)
	return e


func _npc(name: String, tint: Array, lines: Array) -> NpcData:
	var n := NpcData.new()
	n.name = name; n.tint = _c(tint); n.lines = PackedStringArray(lines)
	return n


func _room(index: int, id: String, name: String, kind: String, pos, theme: ThemeData, blurb: String, layout: Array, doors: Dictionary,
		enc: EncounterData, extra: Dictionary = {}) -> void:
	var r := RoomData.new()
	r.id = id; r.name = name; r.kind = kind; r.blurb = blurb
	r.on_map = pos != null
	if pos != null:
		r.map_pos = Vector2i(pos[0], pos[1])
	r.theme = theme
	r.layout = PackedStringArray(layout)
	r.doors = doors
	r.encounter = enc
	r.restore = extra.get("restore", false)
	r.stands = PackedStringArray(extra.get("stands", []))
	var npcs: Array[NpcData] = []
	for n in extra.get("npcs", []):
		npcs.append(n)
	r.npcs = npcs
	r.reward = extra.get("reward", "")
	_save(r, "rooms/%02d_%s.tres" % [index, id])


func _proving_ground() -> Array:
	# The stress arena: 80 x 50 flat island with pillars, spawn ring, passage east.
	var W := 80
	var H := 50
	var g := []
	for y in H:
		var row := []
		row.resize(W)
		row.fill(".")
		g.append(row)
	var rects := [[18, 10, 2, 8], [60, 10, 2, 8], [18, 32, 2, 8], [60, 32, 2, 8], [29, 8, 7, 2], [44, 8, 7, 2], [29, 40, 7, 2], [44, 40, 7, 2],
		[9, 24, 2, 2], [69, 24, 2, 2], [39, 15, 2, 2], [39, 33, 2, 2], [28, 20, 2, 2], [50, 28, 2, 2], [50, 20, 2, 2], [28, 28, 2, 2]]
	for r in rects:
		for y in range(r[1], r[1] + r[3]):
			for x in range(r[0], r[0] + r[2]):
				g[y][x] = "#"
	for x in range(2, W - 2, 3):
		g[1][x] = "*"
		g[H - 2][x] = "*"
	for y in range(2, H - 2, 3):
		g[y][1] = "*"
	for y in range(23, 27):
		g[y][W - 1] = "A"
		g[y][W - 2] = "A"
	g[25][36] = "@"
	var out := []
	for row in g:
		out.append("".join(PackedStringArray(row)))
	return out


func _rooms(th: Dictionary, modes: Dictionary) -> void:
	_room(0, "sanctum", "Sanctum", "hub", [1, 3], th.sanctum,
		"Home. The Shrine, the Keeper, a well. Forge west, Lounge east, trouble north.", [
		"TTTTTTTTTTTTTTTTTTTTAAAATTTTTTTTTTTTTTTTTTTT",
		"TTTTTTTTTTTTTTTTTTTT,,,,TTTTTTTTTTTTTTTTTTTT",
		"TTTTTTTTTTTTTTTTTTTT,,,,TTTTTTTTTTTTTTTTTTTT",
		"TTT.TTT....TTT.T.T..,,,,.TT.TTTTT.TT..TTTTTT",
		"TTTT................,,,,..................TT",
		"TTTT..........,,,,,,,,,,,,,,,,,..........TTT",
		"TTTT..........,,,,,,,,,,,,,,,,,..........TTT",
		"TTTT..........,,.1111111111..,,..........TTT",
		"TTTT.....##...,,.1111S11111..,,..##......TTT",
		"TTTT.....##...,,.1111111P11..,,..##.......TT",
		"TTTT..........,,.1111111111..,,...........TT",
		"TTT...........,,.1111111111..,,..........TTT",
		"TTTT..........,,....cccc.....,,..........TTT",
		"D,,,,.........,,....bbbb.....,,........,,,,B",
		"D,,,,,,,,,,,,,,,....aaaa.....,,,,,,,,,,,,,,B",
		"D,,,,,,,,,,,,,,,.............,,,,,,,,,,,,,,B",
		"D,,,,.........,,.............,,........,,,,B",
		"TTT....TTT....,,,,,,,,,,,,,,,,,...TTT....TTT",
		"TTT...TTTTT...,,,,,,,,,,,,,,,,,..TTTTT...TTT",
		"TTTT...ttt...........,,...........ttt.....TT",
		"TTT..................,@...H..............TTT",
		"TTTT.....##..........,,..........##.......TT",
		"TTTT.....##..........,,..........##......TTT",
		"TTTT.................,,..................TTT",
		"TTTT.................,,..................TTT",
		"TTT..................,,..................TTT",
		"TTTT................,,,,.................TTT",
		"TTT.................,,,,.................TTT",
		"TTT.tttttttt.ttt.t..,,,,tt...t..tttt.ttttTTT",
		"TTTTttttttttttttttttCCCCtttttttttttttttttTTT",
	], {A = ["hollow", "C"], B = ["lounge", "D"], C = ["yard", "A"], D = ["forge", "B"]}, null, {
		restore = true,
		npcs = [_npc("Keeper Moss", [0.72, 0.95, 0.7], [
			"The Shrine takes what you gather and gives back something sharper.",
			"Passages seal when the wild ones come. Clear them and the way opens.",
			"Forge to the west, Lounge to the east. The Hollow is north, and it bites.",
			"Come home when you're hurt. The Sanctum always mends you.",
		])],
	})

	_room(1, "hollow", "The Hollow", "combat", [1, 2], th.moss,
		"A mossy clearing with two sinkholes. Something sharp waits for whoever clears it.", [
		"TTTTTTTTTTTTTTTTTTTTTTTTAAAATTTTTTTTTTTTTTTTTTTTTTTT",
		"TTTTTTTTTTTTTTTTTTTTTTTT,,,,TTTTTTTTTTTTTTTTTTTTTTTT",
		"TTTTTTTTTTTTTTTTTTTTTTTT,,,,TTTTTTTTTTTTTTTTTTTTTTTT",
		"TTTT...TTTT.TTTTTTT.TTTT,,,,T..TTTTTTTT.TTTTT..TT.TT",
		"TTTT..............*.....,,,,.....*...............TTT",
		"TTT...*.............T....,,.......................TT",
		"TTTT...............TTT...,,...................*...TT",
		"TTT.......##........t....,,.............##.......TTT",
		"TTTT......##.............,,.............##.......TTT",
		"TTTT................##...,,.......................TT",
		"TTTT................##...,,......................TTT",
		"TTT......................,,......................TTT",
		"TTTT.........   .........,,........    ..........TTT",
		"TTTT.......      ........,R........      ........TTT",
		"TTTT......        .......,,......        ......,,,,B",
		"TTTT.......       .......,,,,,,,,        ,,,,,,,,,,B",
		"TTTT.......       .......,,,,,,,,,        ,,,,,,,,,B",
		"TTTT.......       .......,,.......       ......,,,,B",
		"TTT.......... . .........,,........ .. ..........TTT",
		"TTT......................,,......................TTT",
		"TTT..*...................,,......................TTT",
		"TTTT.....................,,...##..................TT",
		"TTTT.....................,,...##..............*...TT",
		"TTTT......##.............,,.............##.......TTT",
		"TTT.......##......*......,,....T..*.....##.......TTT",
		"TTTT.....................,,...TTT................TTT",
		"TTT......................@,....t.................TTT",
		"TTTT.....................,,.......................TT",
		"TTTT....................,,,,......................TT",
		"TTT.....................,,,,.....................TTT",
		"TTT.ttt..t.ttt.ttt..tttt,,,,.ttttt..tt.ttt..ttttt.TT",
		"TTTTttttttttttttttttttttCCCCttttttttttttttttttttttTT",
	], {C = ["sanctum", "A"], A = ["wayshrine", "C"], B = ["mire", "D"]},
		_enc(modes, "skirmish", 7, 0, 2, 0.12, 0, 1, [35, 30, 20, 10, 5, 0]), {reward = "sword"})

	_room(2, "ridge", "The Ridge", "combat", [2, 1], th.base, "High ground over the abyss. Squads hunt here.", [
		"  222222222222222222                          ",
		" 22222222222222222222222                      ",
		" 2222222##222222222222222                     ",
		" 222%222##2222222222222222                    ",
		" 2222222222222222222222fed11111111111111      ",
		" 2222222222222222222222fed111111111111111     ",
		" 222222222222222%222222fed1111111&1111111     ",
		" 2222222222222222222222 111111111111111111    ",
		"  22222222222222222222  111111##11111111111   ",
		"   2222222222222222222  111111##11111111111   ",
		"    ...............     111111111111111&111   ",
		"   .................    11111111111111111111  ",
		"  ....*..............   cccccc11111111111111  ",
		" .......................bbbbbb11111111111111  ",
		"DD......................aaaaaa..........1111  ",
		"DD...........................................  ",
		"DD.....##.........................*.........  ",
		" ..........................................   ",
		"  ....................*..................     ",
		"     ................CCCC...............      ",
		"                     CCCC                     ",
	], {D = ["wayshrine", "B"], C = ["mire", "A"]},
		_enc(modes, "skirmish", 8, 0, 1, 0.12, 1, 2, [25, 15, 25, 10, 20, 5]))

	_room(3, "proving", "Proving Ground", "dev", null, th.base,
		"Stress test: a big horde and bullet sprayers. Dev only (key 4).", _proving_ground(),
		{A = ["sanctum", ""]}, _enc(modes, "stress", 0, Tuning.MAX_ENEMIES, Tuning.MAX_ENEMIES, 0.0, 0, 1, []))

	_room(4, "yard", "Old Yard", "training", [1, 4], th.base,
		"The old sanctum, floating on its own. A quiet place to practise jumps and dives.", [
		"              AAAA              ",
		"            ..AAAA..            ",
		"         ..............         ",
		"       ..................       ",
		"     ......................     ",
		"    ........................    ",
		"   .......111111111.........    ",
		"  ........111111111...........  ",
		"..........1111##111.............",
		"..........1111##111.............",
		"  ........111111111...........  ",
		"   .......111111111.........    ",
		"   ..........ccc............    ",
		"   ..........bbb............    ",
		"    .........aaa...........     ",
		"     ...........@..........     ",
		"       ..................       ",
		"         ..............         ",
		"            ........            ",
	], {A = ["sanctum", "C"]}, null)

	_room(5, "forge", "The Forge", "shop", [0, 3], th.forge, "Weapon racks. Buy a weapon once, swap to it here any time.", [
		"##################################",
		"##################################",
		"##################################",
		"###............................###",
		"###............................###",
		"###...W....W....W....W....W.....##",
		"####...........................###",
		"###...,,,,,,,,,,,,,,,,,,,,,.....##",
		"###.............,,.............###",
		"######...........,.............###",
		"######......P...,,..............##",
		"####............,,...........,,,,B",
		"####............,,,,,,,,,,,,,,,,,B",
		"####............,,,,,,,,,,@,,,,,,B",
		"####.........................,,,,B",
		"###.##..........................##",
		"######.........................###",
		"####...........................###",
		"###............................###",
		"###.............................##",
		"####............................##",
		"####...........................###",
		"####tttttt.t..ttt...tt.t....tt.###",
		"###ttttttttttttttttttttttttttttt##",
	], {B = ["sanctum", "D"]}, null, {
		stands = ["paws", "sword", "spear", "hammer", "daggers"],
		npcs = [_npc("Smith Ember", [1.0, 0.72, 0.5], [
			"Walk up to a rack and press T. Buy once, swap back for free.",
			"The spear keeps trouble at arm's length. Its arm, not yours.",
			"Hammer's slow. Hammer's honest. Hammer ends conversations.",
			"Twin Fangs want you close and moving. Don't stand still with them.",
		])],
	})

	_room(6, "lounge", "The Lounge", "social", [2, 3], th.lounge, "Friends, a pond, and the board that keeps your tally.", [
		"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
		"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
		"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
		"TTT.TTTTTT.TTTTTTT....T.T..T.T.TTT",
		"TTT............................TTT",
		"TTT............................TTT",
		"TTTT.......L...................TTT",
		"TTT..................~.~.......TTT",
		"TTT..................~~~~~~....TTT",
		"TTT................~~~~~~~~.....TT",
		"D,,,,..............~~~~~~~~~...TTT",
		"D,,,,,,,,,,,,,,,....~~~~~~~~...TTT",
		"D,,,,,,@,,,,,,,,....~~~~~~~....TTT",
		"D,,,,.........,P.......~~......TTT",
		"TTTT..........,,...............TTT",
		"TTT...........,,..........P.....TT",
		"TTT...........,,,,,,,,,,,,......TT",
		"TTTT...TTT....,,,,,,,,,,,,.....TTT",
		"TTTT...TTT..................X...TT",
		"TTTT...ttt......................TT",
		"TTTT...........................TTT",
		"TTT............................TTT",
		"TTT.ttttt.ttt.t.tt..tttt.tttt.t.TT",
		"TTTTtttttttttttttttttttttttttttTTT",
	], {D = ["sanctum", "B"]}, null, {
		npcs = [
			_npc("Pip", [0.6, 0.8, 1.0], [
				"The board by the trees keeps count of everything you do out there.",
				"Heard someone left a spear up at the Overlook. Past the Wayshrine, north.",
				"The Mire's got a pair of fangs in it. Nasty little things. The fangs, I mean.",
			]),
			_npc("Old Gloop", [0.82, 0.62, 1.0], [
				"When I was your size the Barrow was just a hill with opinions.",
				"Champions glow. Glowing things hit harder. That's science.",
				"Clear a place once and it stays quiet. Mostly.",
			]),
		],
	})

	_room(7, "wayshrine", "Wayshrine", "rest", [1, 1], th.way,
		"A crossroads with a Shrine and a well. Thornwood west, Ridge east, Overlook north.", [
		"TTTTTTTTTTTTTTTTTAAAATTTTTTTTTTTTTTTTT",
		"TTTTTTTTTTTTTTTTT,,,,TTTTTTTTTTTTTTTTT",
		"TTTTTTTTTTTTTTTTT,,,,TTTTTTTTTTTTTTTTT",
		"TTT..TTT...TTTTT.,,,,TTTTTT.TTT..T.TTT",
		"TTTT.............,,,,..............TTT",
		"TTT...##..........,,..........##....TT",
		"TTTT..##..........,,..........##...TTT",
		"TTTT..............,,................TT",
		"TTT........S......,,......H........TTT",
		"TTTT..............,,................TT",
		"TTTT..............,,................TT",
		"TTTT..............,,...............TTT",
		"D,,,,.............,,.............,,,,B",
		"D,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,B",
		"D,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,B",
		"D,,,,.............,,.............,,,,B",
		"TTTT..............,,...............TTT",
		"TTTT..............,@................TT",
		"TTTT..............,,................TT",
		"TTTT......TTT.....,,.....P.........TTT",
		"TTT......TTTTT....,,................TT",
		"TTTT..##..ttt.....,,..........##...TTT",
		"TTTT..##..........,,..........##....TT",
		"TTTT..............,,...............TTT",
		"TTTT.............,,,,..............TTT",
		"TTTT.............,,,,..............TTT",
		"TTTTtt.t..tt..ttt,,,,t.ttt.tttt..tt.TT",
		"TTTTtttttttttttttCCCCttttttttttttttTTT",
	], {C = ["hollow", "A"], A = ["overlook", "C"], B = ["ridge", "D"], D = ["thornwood", "B"]}, null, {
		npcs = [_npc("Wayfarer Lune", [1.0, 0.9, 0.55], [
			"Crossroads. Thornwood west, the Ridge east, the Overlook north.",
			"The well mends you. Drink before you go on.",
			"The Barrow is past the Thornwood. Bring something heavier than claws.",
		])],
	})

	_room(8, "mire", "The Mire", "combat", [2, 2], th.mire, "Pools and causeways. Spitters love the water's edge.", [
		"TTTTTTTTTTTTTTTTTTTTTTTTAAAATTTTTTTTTTTTTTTTTTTTTTTT",
		"TTTTTTTTTTTTTTTTTTTTTTTT,,,,TTTTTTTTTTTTTTTTTTTTTTTT",
		"TTTTTTTTTTTTTTTTTTTTTTTT,,,,TTTTTTTTTTTTTTTTTTTTTTTT",
		"TTTT...T.T.TT.TT.T.TTTT.,,,,TTTTTT.TT.T.TTTT..TTT.TT",
		"TTTT................*...,,,,...............T......TT",
		"TTTT.....................,,...*...........TTT....TTT",
		"TTTT........~~~~~.~......,,................t......TT",
		"TTT.......~~~~~~~~~......,,.........~~~~~.........TT",
		"TTT......~~~~~~~~~~......,,........~~~~~~~~......TTT",
		"TTT......~~~~~~~~~~......,,.......~~~~~~~~~.......TT",
		"TTTT.......~~~~~~~.......,,........~~~~~~~~......TTT",
		"TTTT...................,,,,..........~~~.........TTT",
		"TTT.....T.............,,,,...................*...TTT",
		"TTTT...TTT...........,,,..........................TT",
		"D,,,,...t............,,..~~~.....................TTT",
		"D,,,,,@,,,,,,,,,,,,,,,,.~~~~~....R........,,,,...TTT",
		"D,,,,,,,,,,,,,,,,,,,,,,..~~~.........,,,,,,,,,...TTT",
		"D,,,,................,,..........,,,,,,,*,,......TTT",
		"TTTT........*........,,,,,,,,,,,,,,,,,............TT",
		"TTTT..................,,,,,,,,,,,,...............TTT",
		"TTTT............................~~~~~~~~.......*.TTT",
		"TTT..........~~~~..............~~~~~~~~~~~~......TTT",
		"TTTT......~~~~~~~~~~...........~~~~~~~~~~~~......TTT",
		"TTTT.....~~~~~~~~~~~~..........~~~~~~~~~~~.......TTT",
		"TTT.......~~~~~~~~~~............~.~~~~~~.........TTT",
		"TTTT.........~~~~.~.....*...................T.....TT",
		"TTTT...T...................................TTT....TT",
		"TTTT..TTT....................*..............t....TTT",
		"TTTT...t..........................................TT",
		"TTT...............................................TT",
		"TTTTt.t..t.tt..ttttt.tt..tt..t....t..tttt...ttt.tTTT",
		"TTTTtttttttttttttttttttttttttttttttttttttttttttttTTT",
	], {D = ["hollow", "B"], A = ["ridge", "C"]},
		_enc(modes, "skirmish", 8, 0, 3, 0.12, 0, 2, [15, 35, 10, 30, 10, 0]), {reward = "daggers"})

	_room(9, "thornwood", "Thornwood", "combat", [0, 1], th.thorn,
		"Tight lanes between thorn thickets. Flankers and stalkers hunt in packs.", [
		"TTTTTTTTTTTTTTTTTTTTTTTTAAAATTTTTTTTTTTTTTTTTTTTTTTT",
		"TTTTTTTTTTTTTTTTTTTTTTTT,,,,TTTTTTTTTTTTTTTTTTTTTTTT",
		"TTTTTTTTTTTTTTTTTTTTTTTT,,,,TTTTTTTTTTTTTTTTTTTTTTTT",
		"TTTTTTTTTTTTTTTTTTTTTTTT,,,,TTTTTTTTTTTTTTTTTTTTTTTT",
		"TTTTTT.TTTTTTT.T.T..TT..,,,,TT.TTT.TTT.TT..T..TTTTTT",
		"TTTTT.T.......T...T.*...,,,,T..T....T....T*.....TTTT",
		"TTTTT..*.................,,....................TTTTT",
		"TTTTT....................,,......T.T.............TTT",
		"TTTTT........TTT.......ttt,....TTTTT...........T.TTT",
		"TTTTT.....TTTTTT.........,,,...TTTTTTT.........TTTTT",
		"TTTT......TTTTTTT.........,,...ttttttt.....ttt..TTTT",
		"TTTT.T......tttt..........,,......tt.............TTT",
		"TTTTT........tt...........,,.....................TTT",
		"TTTTTT....................,,,...................TTTT",
		"TTTTTT*..................TTT,,,...............,,,,,B",
		"TTTT.....................TTT,,,,,,,,,,,,,,,,,,,,,,,B",
		"TTTT.T...................ttt..,,,,,,,,,,,,,,@,,,,,,B",
		"TTTTT.........................................,,,,,B",
		"TTTTTT...........................*..............TTTT",
		"TTTTT...TTT.......TTT.................TT.T......TTTT",
		"TTTT.T..TTT......TTTTTT.............TTTTTTT......TTT",
		"TTTT....ttt......TTTTTT.............TTTTTTT.....TTTT",
		"TTTT.............ttttt...............tttttt.....TTTT",
		"TTTTT.............t..................t.ttt.....TTTTT",
		"TTTTT..........................................TTTTT",
		"TTTTT........................ttt................TTTT",
		"TTTTT......*.ttt............*.................*.TTTT",
		"TTTTTT..........................................TTTT",
		"TTTT............................................TTTT",
		"TTTTT...........................................TTTT",
		"TTTTTtt.t..ttttt.tttt..ttt..tttt.tttttttt..t.ttt.TTT",
		"TTTTTTttttttttttttttttttttttttttttttttttttttttttTTTT",
	], {B = ["wayshrine", "D"], A = ["barrow", "C"]},
		_enc(modes, "skirmish", 8, 0, 1, 0.12, 1, 2, [10, 10, 35, 10, 35, 0]))

	_room(10, "barrow", "The Barrow", "elite", [0, 0], th.barrow,
		"An old burial dais. Brutes and champions. Something heavy rests on top.", [
		"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
		"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
		"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
		"TTTT.TTT.TTT..TTTTTT.TT..T.T.T.T..T.TTTT..TTTT",
		"TTTT.......................................TTT",
		"TTTT.*..................................*..TTT",
		"TTT............##111111111111##............TTT",
		"TTTT...........##111111111111##.............TT",
		"TTTT..###......111&111R11111111......###...TTT",
		"TTT...#........1111111111111111........#...TTT",
		"TTTT..#........111111111111&111........#....TT",
		"TTTT..#........##111111111111##........#...TTT",
		"TTTT...........##111111111111##.............TT",
		"TTTT.................cccc................,,,,B",
		"TTTT.................bbbb,,,,,,,,,,,,,,,,,,,,B",
		"TTT..................aaaa,,,,,,,,,,,,,,,,,,,,B",
		"TTT...................,,.................,,,,B",
		"TTTT.........*........,,........*...........TT",
		"TTTT..................,,....................TT",
		"TTTT..................,,...................TTT",
		"TTTT....####..........,,..........####.....TTT",
		"TTT...................,,....................TT",
		"TTT...................,,...................TTT",
		"TTT...................,,...................TTT",
		"TTTT.*................,,................*..TTT",
		"TTT...................@,...................TTT",
		"TTT..................,,,,..................TTT",
		"TTT..................,,,,..................TTT",
		"TTT.t.t.t.t..t.tttttt,,,,t.ttttt..t..t.tttt.TT",
		"TTTTtttttttttttttttttCCCCttttttttttttttttttTTT",
	], {C = ["thornwood", "A"], B = ["overlook", "D"]},
		_enc(modes, "skirmish", 7, 0, 1, 0.1, 1, 3, [30, 0, 10, 10, 20, 30]), {reward = "hammer"})

	_room(11, "overlook", "The Overlook", "explore", [1, 0], th.overlook,
		"A lookout over the abyss. Climb to the top; someone left something there.", [
		"",
		"",
		"",
		" TT..  . ...  22222222222222.. . . .....",
		"TTTT..........222222R2222222...........TTT",
		"TTTT..........22222222222222...........TTT",
		"TTTT..........22222222222222............TT",
		"TTT...........22222222222222...........TTT",
		"TTTT..........22222222222222...........TTT",
		"TTT.....11111111111ffff11111111111......TT",
		"TTTT....11111111111eeee11111111111.....TTT",
		"TTT.....11111111111dddd11111111111.....TTT",
		"TTTT....1111111111111111111111X111......TT",
		"TTT.....11111111111111111111111111.....TTT",
		"TTT.....11111111111111111111111111.....TTT",
		"TTTT....11111111111111111111111111......TT",
		"D,,,,...11111111111111111111111111.....TTT",
		"D,,,,,,,...........cccc................TTT",
		"D,,,,,,,,,,,,......bbbb................TTT",
		"D,,,,..,,,,,,,,,,..aaaa.................TT",
		"TTTT........,,,,,,,,,,..........TTT....TTT",
		"TTTT............,,,,,,.........TTTTT....TT",
		"TTTT................,,..........ttt....TTT",
		"TTTT................,,.................TTT",
		"TTTT................@,..................TT",
		"TTT.................,,..................TT",
		"TTTT...............,,,,................TTT",
		"TTTT...............,,,,................TTT",
		"TTTTtt...tttt.tttt.,,,,ttt..tttttttt.ttTTT",
		"TTTTtttttttttttttttCCCCtttttttttttttttttTT",
	], {C = ["wayshrine", "A"], D = ["barrow", "B"]}, null, {reward = "spear"})
