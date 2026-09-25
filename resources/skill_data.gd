class_name SkillData
extends Resource
## A job skill (Q / E). Prototype: content/progression.ts SKILLS + the per-skill tuning tables
## (QUAKE, RALLY, TOTEM, BULWARK, BLINK, HEX), which live in `params`.

enum Id { QUAKE, RALLY, TOTEM, BULWARK, BLINK, HEX }

@export var id: Id = Id.QUAKE
@export var name := ""
@export_multiline var desc := ""
@export var cooldown := 240       ## ticks
@export var mana := 20
@export var params := {}


func p(key: String, fallback: float = 0.0) -> float:
	return float(params.get(key, fallback))
