class_name EncounterDef
extends Resource
## A reusable fight for a room in a run (data/encounters). The run rolls one per combat room;
## enemies are named by kind id (data/enemies). The hub world keeps using EncounterData and
## the director instead. Difficulty comes from which behaviours share the room, not numbers:
## normal fights are 2-4 enemies, sometimes in two small waves.

@export var id := ""
@export var kind := "combat"          ## combat, elite, boss
@export var tier := 1                 ## 1 early rooms, 2 later rooms, 3 elite / boss
## each wave is a list of enemy kind ids; the next wave comes when the last one is down
@export var waves: Array[PackedStringArray] = []
## up to `extra` more enemies from this pool may join the first wave
@export var extra_pool := PackedStringArray()
@export var extra := 0
@export var champions := 0            ## this many of the first wave are champions (elites)
@export var essence := Vector2i(10, 16)   ## Essence spilled when the room is cleared


func size() -> int:
	var n := 0
	for w in waves:
		n += w.size()
	return n
