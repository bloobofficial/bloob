class_name TechData
extends Resource
## A tech bought at a Shrine (prototype: content/progression.ts TECHS).

@export var id := ""
@export var name := ""
@export var desc := ""
## Ichor, Bone, Wisp, Relic Shard
@export var cost := PackedInt32Array([0, 0, 0, 0])
@export var req := PackedStringArray()
