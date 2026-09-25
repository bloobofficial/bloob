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
