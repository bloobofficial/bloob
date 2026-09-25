class_name JobData
extends Resource
## A job: stat multipliers and two skills (prototype: content/progression.ts JOBS).

@export var id := ""
@export var name := ""
@export_multiline var blurb := ""
@export var hp_mul := 1.0
@export var speed_mul := 1.0
@export var dmg_mul := 1.0
@export var mana_mul := 1.0
@export var skills: Array[SkillData] = []
@export var unlock := ""          ## tech id that unlocks it ("" = always)
