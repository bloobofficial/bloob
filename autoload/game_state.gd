extends Node
## The run: everything that persists between rooms (prototype: sim/profile.ts + the room
## memory in sim/sim.ts). Derived stats are recomputed from the owned techs, level and job,
## so there is one source of truth. The prototype has no save file; neither does this.

signal changed

var res := PackedInt32Array([0, 0, 0, 0])
var techs := PackedByteArray()
var xp := 0
var level := 1
var job := 0
var flask := Tuning.FLASK_CHARGES
var rooms_cleared := 0
var weapon := 0                          ## equipped weapon index
var weapons := PackedByteArray()         ## owned weapons this run
var kills := 0
var talks := 0
var run_ticks := 0
## per room index: {visited, cleared, defeated, taken (bit per marker slot)}
var room_states: Array[Dictionary] = []
# the run loop
var essence := 0                         ## run currency: spent in shops, lost when the run ends
var essence_total := 0                   ## collected this run (the summary)
var passives := PackedStringArray()      ## passive ids owned this run (may repeat: they stack)
var weapons_used := PackedStringArray()  ## weapon names held this run, in order
var haste_t := 0                         ## Bloodrush: ticks of bonus speed left

# derived (recompute())
var max_hp := Tuning.BASE_HP
var mana_max := Tuning.MANA_BASE
var dmg_mul := 1.0
var speed_mul := 1.0
var flask_max := Tuning.FLASK_CHARGES
var flask_heal := Tuning.FLASK_HEAL
var magnet := Tuning.PICKUP_MAGNET
var cd_mul := 1.0
var dive_mul := 1.0
# from passives
var melee_mul := 1.0
var finisher_mul := 1.0
var reach_mul := 1.0
var atk_speed := 1.0
var mana_regen_mul := 1.0
var dodge_cd_mul := 1.0
var dmg_taken_mul := 1.0
var kill_mana := 0.0
var kill_haste := 0
var essence_mul := 1.0


func _ready() -> void:
	reset()


## Forget the run. `room_list` = the rooms this run can visit (the hub world by default).
func reset(room_list: Array = []) -> void:
	res = PackedInt32Array([0, 0, 0, 0])
	techs = PackedByteArray()
	techs.resize(Content.techs.size())
	xp = 0
	level = 1
	job = 0
	rooms_cleared = 0
	weapon = 0
	weapons = PackedByteArray()
	weapons.resize(Content.weapons.size())
	weapons[0] = 1   # Goo Paws
	kills = 0
	talks = 0
	run_ticks = 0
	essence = 0
	essence_total = 0
	passives = PackedStringArray()
	weapons_used = PackedStringArray()
	haste_t = 0
	room_states.clear()
	for r in (room_list if not room_list.is_empty() else Content.rooms):
		room_states.append({visited = false, cleared = false, defeated = 0, taken = 0})
	recompute()
	flask = flask_max
	changed.emit()


func has(id: String) -> bool:
	var i := Content.tech_index(id)
	return i >= 0 and techs[i] == 1


func job_data() -> JobData:
	return Content.jobs[clampi(job, 0, Content.jobs.size() - 1)]


func job_unlocked(j: int) -> bool:
	if j < 0 or j >= Content.jobs.size():
		return false
	var def := Content.jobs[j]
	return def.unlock == "" or has(def.unlock)


## why a tech can't be bought right now ("" = it can)
func tech_blocker(i: int) -> String:
	if i < 0 or i >= Content.techs.size():
		return "unknown"
	var t := Content.techs[i]
	if techs[i]:
		return "owned"
	for r in t.req:
		if not has(r):
			var ti := Content.tech_index(r)
			return "needs " + (Content.techs[ti].name if ti >= 0 else r)
	for k in Tuning.RES_COUNT:
		if res[k] < t.cost[k]:
			return "not enough"
	return ""


func can_afford(cost: PackedInt32Array) -> bool:
	for k in Tuning.RES_COUNT:
		if res[k] < cost[k]:
			return false
	return true


func spend(cost: PackedInt32Array) -> void:
	for k in Tuning.RES_COUNT:
		res[k] -= cost[k]
	changed.emit()


func add_res(t: int, n: int) -> void:
	if t >= 0 and t < Tuning.RES_COUNT:
		res[t] += n
		changed.emit()


func buy(i: int) -> bool:
	if tech_blocker(i) != "":
		return false
	var t := Content.techs[i]
	for k in Tuning.RES_COUNT:
		res[k] -= t.cost[k]
	techs[i] = 1
	var flask_before := flask_max
	recompute()
	flask += flask_max - flask_before   # a new charge comes filled
	changed.emit()
	return true


## returns how many levels were gained
func add_xp(amount: int) -> int:
	if level >= Tuning.MAX_LEVEL:
		return 0
	xp += amount
	var gained := 0
	while level < Tuning.MAX_LEVEL and xp >= Tuning.xp_to_next(level):
		xp -= Tuning.xp_to_next(level)
		level += 1
		gained += 1
	if level >= Tuning.MAX_LEVEL:
		xp = 0
	if gained > 0:
		recompute()
	changed.emit()
	return gained


func recompute() -> void:
	var jd := job_data()
	var hp := Tuning.BASE_HP + (level - 1) * Tuning.LEVEL_HP
	if has("vigor1"):
		hp += 20
	if has("vigor2"):
		hp += 30
	max_hp = roundi(hp * jd.hp_mul)
	mana_max = roundi((Tuning.MANA_BASE + (level - 1) * Tuning.MANA_PER_LEVEL + (25 if has("mana1") else 0)) * jd.mana_mul)
	var dmg := (1.0 + (level - 1) * Tuning.LEVEL_DMG) * jd.dmg_mul
	if has("claws1"):
		dmg *= 1.15
	if has("claws2"):
		dmg *= 1.2
	dmg_mul = dmg
	speed_mul = jd.speed_mul
	flask_max = Tuning.FLASK_CHARGES + (1 if has("flask1") else 0) + (1 if has("flask2") else 0)
	flask_heal = 0.5 if has("flask2") else Tuning.FLASK_HEAL
	magnet = Tuning.PICKUP_MAGNET * (2.0 if has("magnet1") else 1.0)
	cd_mul = 0.8 if has("skills1") else 1.0
	dive_mul = 1.25 if has("slam1") else 1.0
	# passives: each adds its amount to one stat
	var m := {}
	for id in passives:
		var pd := Content.passive(id)
		if pd:
			m[pd.stat] = m.get(pd.stat, 0.0) + pd.amount
	max_hp += roundi(m.get("max_hp", 0.0))
	melee_mul = 1.0 + m.get("melee_dmg", 0.0)
	finisher_mul = 1.0 + m.get("finisher_dmg", 0.0)
	reach_mul = 1.0 + m.get("reach", 0.0)
	atk_speed = 1.0 + m.get("atk_speed", 0.0)
	mana_regen_mul = 1.0 + m.get("mana_regen", 0.0)
	dodge_cd_mul = maxf(0.3, 1.0 + m.get("dodge_cd", 0.0))
	dmg_taken_mul = maxf(0.3, 1.0 + m.get("dmg_taken", 0.0))
	kill_mana = m.get("kill_mana", 0.0)
	kill_haste = roundi(m.get("kill_haste", 0.0))
	essence_mul = 1.0 + m.get("essence", 0.0)


## gain a passive (altar / shop); returns the max HP it added so the caller can heal that much
func add_passive(id: String) -> int:
	var before := max_hp
	passives.append(id)
	recompute()
	changed.emit()
	return max_hp - before


func passive_count(id: String) -> int:
	return passives.count(id)


func add_essence(n: int) -> void:
	var got := roundi(n * essence_mul)
	essence += got
	essence_total += got
	changed.emit()


func spend_essence(n: int) -> bool:
	if essence < n:
		return false
	essence -= n
	changed.emit()
	return true


func weapon_data() -> WeaponData:
	return Content.weapons[clampi(weapon, 0, Content.weapons.size() - 1)]


## loot that never became an orb (pickup cap, fell off the island): straight into the pockets
func bank(type: int, amount: int) -> void:
	if type == Tuning.PICKUP_ESSENCE:
		add_essence(amount)
	elif type >= 0 and type < Tuning.RES_COUNT:
		add_res(type, amount)
