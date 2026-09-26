class_name RoomData
extends Resource
## One area of the world (prototype: content/rooms.ts RoomDef). The layout is ASCII, one
## character per 32-unit cell; see world/rooms/room_map.gd for the legend.

@export var id := ""
@export var name := ""
## hub, shop, social, rest, explore, training, combat, elite, dev
@export var kind := "combat"
@export_multiline var blurb := ""
@export var on_map := true
@export var map_pos := Vector2i.ZERO
@export var theme: ThemeData
@export var layout := PackedStringArray()
## door letter -> [room id, arrival door letter ("" = start marker)]
@export var doors := {}
@export var encounter: EncounterData
@export var restore := false         ## entering fully restores Bloob
@export var stands := PackedStringArray()   ## weapon ids for the 'W' racks, reading order
@export var npcs: Array[NpcData] = []
@export var reward := ""             ## weapon id granted here


func is_safe() -> bool:
	return encounter == null

# ---- run rooms only (set by RunPlan on its runtime copies, never saved) ----
var entrance := ""                    ## the passage you arrive through ("" = start marker)
var layer := 0                        ## step of the run (0 = start)
var reward_kind := ""                 ## what clearing it gives: essence, weapon, heal
var drop_weapon := -1                 ## weapon lying at the reward spot / granted on clear
var waves: Array = []                 ## rolled fight: [[enemy kind index, ...], ...]
var champions := 0
var essence := Vector2i.ZERO          ## Essence spilled on clear
var choices := PackedStringArray()    ## altar: passive ids on offer
var offers: Array = []                ## shop: [{type, ref, price, sold}]
# ---- generated maps only (MapGen: one connected island of areas per run stage) ----
var map_no := 0                       ## which map of the run this is (0-based)
## the areas of the map: [{kind, name, cell: Vector2i (middle), rect: Rect2i, idx}]
var areas: Array = []
var zones := PackedStringArray()      ## per cell: area index as chr(48 + i), ' ' outside any area
var styles := PackedStringArray()     ## per cell floor style: '.' natural, 'w' wood, 's' stone, 'r' rug, 'h' hidden trail
var monsters: Array = []              ## [{kind, cell: Vector2i, champ}]: the map's monsters, asleep where they lie
var decor: Array = []                 ## [{type, cell: Vector2i}]: torches and braziers
