class_name PassiveData
extends Resource
## A passive upgrade ("skill" in the run's UI) picked at an altar or bought in a shop
## (data/passives). Each one adds `amount` to one stat; GameState.recompute() folds every
## owned passive into Bloob's derived stats, so there's one source of truth.
##
## Stats: melee_dmg, finisher_dmg, reach, atk_speed (fractions, 0.15 = +15%), mana_regen,
## dodge_cd, dmg_taken (negative = less), max_hp (flat), kill_mana (flat per kill),
## kill_haste (ticks of +25% speed per kill), essence (fraction).

@export var id := ""
@export var name := ""
@export var desc := ""
@export var stat := ""
@export var amount := 0.0
@export var color := Color(0.85, 0.75, 1.0)
