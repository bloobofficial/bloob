class_name ModeData
extends Resource
## Director preset (prototype: content/modes.ts). The same director with different dials.

@export var id := ""
@export var label := ""
@export var blurb := ""
@export var horde_start := 0
@export var horde_max := 0
@export var horde_ramp_per_sec := 0.0
@export var spawn_burst := 0
@export var spawn_every := 0
## weights for [Charger, Weaver, Flanker, Circler, Stalker, Brute]
@export var mix := PackedFloat32Array([0, 0, 0, 0, 0, 0])
@export var squads_start := 0
@export var squads_max := 0
@export var squad_every := 0
@export var brain := 0             ## 1 = squads stagger on a perfect dodge
@export var emitters := 0          ## stress-test bullet sprayers
@export var god_mode := false
@export var patterns := true       ## monsters roll attack patterns, champions and affixes
@export var loot := true
@export var cap_all := false       ## the room's cap counts every monster; squads spawn first
@export var contact := true        ## false = no damage just for touching
