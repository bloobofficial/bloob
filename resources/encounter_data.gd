class_name EncounterData
extends Resource
## A combat room's encounter (prototype: content/rooms.ts Encounter).

@export var preset: ModeData
@export var budget := 7            ## enemies to defeat to clear the room (0 = endless)
@export var max_alive := 0         ## concurrency cap (0 = the tier's default)
@export var start_alive := 2
@export var ramp_per_sec := 0.12
@export var squads := 0            ## max squads alive at once
@export var tier := 1              ## map difficulty tier + base monster level
## which monsters show up: [Charger, Weaver, Flanker, Circler, Stalker, Brute] (empty = preset mix)
@export var mix := PackedFloat32Array()
