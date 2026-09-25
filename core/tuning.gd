class_name Tuning
extends RefCounted
## Every gameplay constant from the prototype, in the prototype's units:
## ticks (60 per second), world units (1 unit = 1 px on the ground plane), units per tick.
## Sources: core/config.ts, content/combat.ts, sim/player.ts, content/progression.ts,
## content/difficulty.ts, sim/enemyAttacks.ts, sim/sim.ts. See MIGRATION.md for conversions.

# ---------------- engine ----------------
const TICK_RATE := 60
const CELL := 32                   ## grid cell size
const GRID_W := 80                 ## max room width in cells
const GRID_H := 50
const LEVEL_H := 48                ## one plateau level
const STEP_UP := 20                ## max climb per cell (stairs are 12-unit steps)
const VOID_H := -32768             ## no ground: off the island
const WALL_H := 60                 ## walls stand this far above the ground around them
const GRAVITY := 0.55              ## units per tick^2
const FALL_OUT_Z := -260.0         ## below this over the void: ring-out
const FALL_STUN_H := 40.0          ## landing after a drop this big stuns enemies
## Godot port: enemy cap (the prototype allows 4096; the 2,000-enemy stress preset is scaled down)
const MAX_ENEMIES := 300
const MAX_BULLETS := 1500
const MAX_PICKUPS := 768
const MAX_TOTEMS := 8

# ---------------- player (sim/player.ts) ----------------
const PLAYER_R := 11.0             ## Bloob's collision footprint
const SPEED := 3.3
const DODGE_TICKS := 16
const DODGE_SPEED := 8.0
const DODGE_IFRAMES := 13
const PERFECT_WINDOW := 7          ## first N ticks of a dodge
const DODGE_CD := 34
const DODGE_BUFFER := 8
const FIRE_EVERY := 5
const FIRE_EVERY_BUFF := 2
const BULLET_SPEED := 12.0
const BULLET_LIFE := 55
const SPIT_DAMAGE := 0.35
const HURT_IFRAMES := 45
const BASE_HP := 100
const PERFECT_HITSTOP := 7
const PERFECT_SLOWMO := 80
const PERFECT_SLOWMO_SCALE := 0.3
const PERFECT_COOLDOWN := 50
const SHOCKWAVE_R := 140.0
const SQUAD_STAGGER_R := 330.0
const STAGGER_TICKS := 70

# ---------------- combat (content/combat.ts) ----------------
const AIR_STEP := 8                ## atkStep value that means "air swipe"
const MAX_AIR_SWINGS := 3
const AIR_HIT_HANG := 3.2
const JUMP_VELOCITY := 8.0         ## apex ~53: one plateau level up, never two
const JUMP_BUFFER := 6
const COYOTE_TICKS := 5
const AIR_MOVE_MUL := 0.95
const DIVE_SPEED := 11.0
const DIVE_RADIUS := 62.0
const DIVE_DAMAGE := 2.0
const DIVE_KNOCK := 7.0
const DIVE_KNOCK_UP := 5.0
const DIVE_STAGGER := 30
const DIVE_LAND_LAG := 10
const DIVE_MIN_HEIGHT := 14.0
const COMBO_WINDOW := 16
const COMBO_END_COOLDOWN := 8
const ATTACK_BUFFER := 10
const SWING_MOVE_MUL := 0.3
const PERFECT_DAMAGE_MUL := 1.5
const WALL_SPLAT_SPEED := 4.5
const WALL_SPLAT_DAMAGE := 1.5
const WALL_SPLAT_STUN := 40
## ground swings reach enemies within this height difference (v0.9 rule: 36)
const MELEE_Z_REACH := 36.0

# ---------------- enemies ----------------
const BRUTE_RECOVER := 50
const AIM_LOCK := 0.6              ## aimed attacks track until this share of the windup is left
const ENEMY_SHOT_LIFE := 110
const AI_THINK_MIN := 96
const AI_THINK_MAX := 640
const AI_LOD_NEAR := 520.0
const ANCHOR_R := 210.0
const MIN_SPAWN_DIST := 300.0

# ---------------- world (sim/sim.ts) ----------------
const USE_RANGE := 62.0
const REWARD_RANGE := 44.0
const DUPLICATE_SHARDS := 2
const EXIT_TICKS := 18
const ENTER_TICKS := 12

# ---------------- resources & loot (content/progression.ts) ----------------
enum Res { ICHOR, BONE, WISP, SHARD }
const RES_COUNT := 4
const PICKUP_HEAL := 4             ## pickup type for health orbs
const RES_NAMES := ["Ichor", "Bone", "Wisp", "Relic Shard"]
const RES_COLORS := [Color(0.98, 0.78, 0.32), Color(0.93, 0.9, 0.8), Color(0.55, 0.85, 1.0), Color(1.0, 0.42, 0.62)]
const RES_DESC := [
	"Common goo every monster leaks. Spent on almost everything.",
	"Hard bits from chargers, stalkers and brutes.",
	"Faint light from weavers, flankers and circlers.",
	"Rare. Champions, brutes and chests. Buys the best techs.",
]
const CHAMPION_LOOT_MUL := 3
const CHAMPION_SHARD_CHANCE := 0.5
const CHAMPION_HEAL_CHANCE := 0.6
const CLEAR_CHEST_ICHOR := Vector2i(26, 40)
const CLEAR_CHEST_BONE := Vector2i(3, 6)
const CLEAR_CHEST_WISP := Vector2i(3, 6)
const CLEAR_CHEST_SHARD := Vector2i(1, 1)
const CACHE_LOOT := [Vector2i(20, 30), Vector2i(3, 5), Vector2i(3, 5), Vector2i(0, 1)]
const PICKUP_LIFE := 60 * 30
const PICKUP_MAGNET := 70.0
const PICKUP_COLLECT := 14.0

# ---------------- healing ----------------
const HEAL_ORB := 12.0
const FLASK_CHARGES := 2
const FLASK_HEAL := 0.35
const FLASK_TICKS := 30
const FLASK_LOCK := 20
const CLEAR_HEAL := 0.15
const LEVEL_HEAL := 0.25

# ---------------- levels ----------------
const MAX_LEVEL := 30
const LEVEL_HP := 6
const LEVEL_DMG := 0.03
const ENEMY_HP_PER_LVL := 0.08
const ENEMY_DMG_PER_LVL := 0.1
const ENEMY_XP_PER_LVL := 0.1

# ---------------- mana ----------------
const MANA_BASE := 60
const MANA_PER_LEVEL := 3
const MANA_REGEN := 4.0 / 60.0     ## per tick
const MANA_PER_HIT := 2.5
const LEVEL_MANA := 0.25

# ---------------- champions / affixes ----------------
enum Affix { SWIFT = 1, ARMORED = 2, FRENZIED = 4, VOLATILE = 8, VAMPIRIC = 16, GIANT = 32 }
const AFFIX_BITS := [1, 2, 4, 8, 16, 32]
const AFFIX_NAMES := ["Swift", "Armored", "Frenzied", "Volatile", "Vampiric", "Giant"]
const AFFIX_COLORS := [Color(0.5, 1, 0.7), Color(0.75, 0.8, 0.95), Color(1, 0.6, 0.2), Color(1, 0.3, 0.2), Color(0.85, 0.2, 0.5), Color(0.95, 0.85, 0.4)]
const CHAMPION_BASE_CHANCE := 0.04
const CHAMPION_PER_LVL := 0.01
const CHAMPION_MAX_CHANCE := 0.15
const CHAMPION_HP_MUL := 2.2
const ROLL_SIZE := Vector2(0.9, 1.15)
const ROLL_HP := Vector2(0.9, 1.1)
const VOLATILE_FUSE := 36
const VOLATILE_RADIUS := 56.0
const VOLATILE_DAMAGE := 14.0
const ELITE_PER_LEVEL := 0.01
const ELITE_MAX := 0.45

# ---------------- global run difficulty (content/difficulty.ts RUN) ----------------
const RUN_HP_MUL := 1.0
const RUN_DMG_MUL := 1.0
const RUN_ATK_RATE := 1.0
const RUN_SPEED_MUL := 1.0

# ---------------- time controller (core/time.ts) ----------------
enum Prio { HIT = 1, HURT = 2, ELITE_KILL = 3, PERFECT = 4, BOSS = 5 }
const HITSTOP_BUDGET_MAX := 18.0
const HITSTOP_BUDGET_REFILL := 0.2


static func xp_to_next(level: int) -> int:
	return roundi(10.0 + 8.0 * pow(level, 1.35))


static func res_color(t: int) -> Color:
	if t == PICKUP_HEAL:
		return Color(0.45, 1, 0.5)
	return RES_COLORS[clampi(t, 0, 3)]


static func cost_text(cost: PackedInt32Array) -> String:
	var parts := PackedStringArray()
	for k in cost.size():
		if cost[k] > 0:
			parts.append("%d %s" % [cost[k], RES_NAMES[k]])
	return " · ".join(parts) if parts.size() > 0 else "free"


static func affix_names(bits: int) -> String:
	var parts := PackedStringArray()
	for k in AFFIX_BITS.size():
		if bits & AFFIX_BITS[k]:
			parts.append(AFFIX_NAMES[k])
	return " ".join(parts)


static func first_affix_color(bits: int) -> Color:
	for k in AFFIX_BITS.size():
		if bits & AFFIX_BITS[k]:
			return AFFIX_COLORS[k]
	return Color.WHITE
