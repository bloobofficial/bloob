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


func _ready() -> void:
	reset()


func reset() -> void:
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
	room_states.clear()
	for r in Content.rooms:
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


func weapon_data() -> WeaponData:
	return Content.weapons[clampi(weapon, 0, Content.weapons.size() - 1)]
