class_name EnemyKindData
extends Resource
## One monster kind: movement personality, attack pool, loot and art hookup
## (prototype: content/enemies.ts, content/attacks.ts KIND_ATTACKS, content/progression.ts LOOT,
## content/anims.ts CHARACTERS). Speeds are in world units per tick.

enum Route { DIRECT, LEFT, RIGHT, AROUND }

@export var id := ""
@export var name := ""
@export var kind_index := 0
@export var color := Color.WHITE
@export var radius := 9.0
@export var hp := 13.0
@export var speed := 1.55
## weights for [Direct, Left, Right, Around] when not in a squad
@export var routes := PackedFloat32Array([1, 0, 0, 0])
@export var weave_amp := 0.0
@export var weave_freq := 0.0
@export var charge_dist := 0.0
@export var charge_mul := 1.0
@export var orbit_radius := 0.0
@export var orbit_ticks := Vector2i.ZERO
@export var hold_dist := 0.0
@export var hold_ticks := Vector2i.ZERO
@export var contact_damage := 8.0
@export var attacks: Array[AttackData] = []
@export var attack_weights := PackedFloat32Array()
@export_group("Loot")
@export var loot_ichor := Vector2i(4, 6)
@export var loot_extra := 1           ## resource index of the secondary drop
@export var loot_extra_chance := 0.55
@export var loot_shard_chance := 0.02
@export var loot_heal_chance := 0.22
@export var kill_xp := 4
@export_group("Art")
@export var sprite_scale := 0.46      ## world units per atlas pixel (96 px cell)
@export var anchor := 0.06            ## feet line, fraction of the frame from the bottom
@export var hover := 0.0              ## float above the ground (flyers)
@export_group("Run")
@export var art := ""                 ## atlas id to draw it with ("" = its own id)
@export var keep_dist := 0.0          ## ranged: hold this far from Bloob, back off when rushed
@export var poise := false            ## brute-like: shrugs off knockback and stagger
@export var essence := 2              ## Essence dropped on death (runs)
@export var boss := false             ## attacks cycle through `attacks` in order


func art_id() -> String:
	return art if art != "" else id
