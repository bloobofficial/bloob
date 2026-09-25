extends Node
## Loads the game's content resources (res://data) once and keeps them in the prototype's index
## order, so systems can refer to weapons, enemy kinds, rooms and techs by index.

const WEAPON_ORDER := ["paws", "sword", "spear", "hammer", "daggers"]
const ENEMY_ORDER := ["charger", "weaver", "flanker", "circler", "stalker", "brute"]
const JOB_ORDER := ["brawler", "warden", "trickster"]
const START_ROOM := "sanctum"

var weapons: Array[WeaponData] = []
var enemies: Array[EnemyKindData] = []
var jobs: Array[JobData] = []
var skills: Array[SkillData] = []
var techs: Array[TechData] = []
var rooms: Array[RoomData] = []
var tiers: Array[TierData] = []
var modes := {}


func _init() -> void:
	for id in WEAPON_ORDER:
		weapons.append(load("res://data/weapons/%s.tres" % id))
	for id in ENEMY_ORDER:
		enemies.append(load("res://data/enemies/%s.tres" % id))
	for id in JOB_ORDER:
		jobs.append(load("res://data/jobs/%s.tres" % id))
	for id in ["quake", "rally", "totem", "bulwark", "blink", "hex"]:
		skills.append(load("res://data/skills/%s.tres" % id))
	for f in _sorted_files("res://data/techs"):
		techs.append(load(f))
	for f in _sorted_files("res://data/rooms"):
		var r: RoomData = load(f)
		# door keys are saved as StringNames; normalise to Strings for lookups
		var doors := {}
		for k in r.doors:
			doors[String(k)] = r.doors[k]
		r.doors = doors
		rooms.append(r)
	for i in 5:
		tiers.append(load("res://data/tiers/tier%d.tres" % (i + 1)))
	for f in _sorted_files("res://data/modes"):
		var m: ModeData = load(f)
		modes[m.id] = m


func _sorted_files(dir: String) -> Array:
	var out := []
	for f in ResourceLoader.list_directory(dir):
		if f.ends_with(".tres"):
			out.append(dir + "/" + f)
	out.sort()
	return out


func mode(id: String) -> ModeData:
	return modes.get(id, modes["calm"])


func weapon_index(id: String) -> int:
	for i in weapons.size():
		if weapons[i].id == id:
			return i
	return -1


func room_index(id: String) -> int:
	for i in rooms.size():
		if rooms[i].id == id:
			return i
	push_error("Unknown room: " + id)
	return 0


func tech_index(id: String) -> int:
	for i in techs.size():
		if techs[i].id == id:
			return i
	return -1


func tier_of(tier: int) -> TierData:
	return tiers[clampi(roundi(tier) - 1, 0, tiers.size() - 1)]
