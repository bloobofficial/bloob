class_name TierData
extends Resource
## Map difficulty tier (prototype: content/difficulty.ts TIERS).

@export var name := ""
@export var hp_mul := 1.0
@export var dmg_mul := 1.0
@export var atk_rate := 1.0        ## > 1 = shorter cooldowns between attacks
@export var speed_mul := 1.0
@export var squads := false
@export var elite_chance := 0.02
@export var two_affix_chance := 0.1
@export var max_alive := 3
