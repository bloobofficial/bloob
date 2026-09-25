class_name Ev
extends RefCounted
## Gameplay event types (prototype: core/events.ts). Gameplay code emits them through the
## Events autoload; effects, audio and the HUD listen. Gameplay never reads them back.
## Arguments follow the prototype: (x, y, a, b, z).

const SHOT := 1
const HIT := 2            ## a, b = hit direction
const KILL := 3           ## a = kind, b = radius
const PLAYER_HURT := 4    ## a, b = direction
const PERFECT_DODGE := 5
const DODGE := 6          ## a, b = direction
const TELL := 7           ## b = 1 heavy
const LUNGE := 8          ## a, b = direction
const SQUAD_COMMIT := 9
const SQUAD_STAGGER := 10
const PLAYER_DEATH := 11
const SWING := 12         ## a = angle, b = weapon * 16 + step
const MELEE_HIT := 13     ## a = knock angle, b = weapon * 16 + step
const WALL_SPLAT := 14    ## a = impact speed, b = radius
const ROOM_ENTER := 15    ## a = room index
const ROOM_CLEARED := 16
const RING_OUT := 17      ## a = kind
const LAND := 18          ## a = drop height, b = radius
const DOORS_SEALED := 19
const JUMP := 20
const PLAYER_LAND := 21   ## a = drop height
const DIVE_START := 22
const DIVE_SLAM := 23     ## a = radius, b = enemies hit
const PICKUP := 24        ## a = type (resource, 4 = heal orb), b = amount
const LEVEL_UP := 25      ## a = new level
const DRINK := 26
const SKILL_CAST := 27    ## a = skill id
const BLAST := 28         ## a = radius, b = owner (0 enemy, 1 Bloob, 2 hex)
const HAZARD_ARM := 29
const ENEMY_SHOT := 30
const TECH_BOUGHT := 31   ## a = tech index
const JOB_CHANGED := 32   ## a = job index
const LOOT := 33
const CHAMPION := 34      ## a = affix bits
const STATION_OPEN := 35  ## a = 1 Shrine, 2 notice board
const WELL_USED := 36
const TALK := 37          ## a = local index, b = conversation count
const WEAPON_EQUIP := 38  ## a = weapon index
const WEAPON_FOUND := 39  ## a = weapon index, b = 1 bought, 0 found, 2 duplicate
const DENIED := 40        ## a = 1 can't afford, 2 already equipped; b = weapon index
const ITEM_APPEAR := 41   ## a = weapon index
const ROOM_EXIT := 42
const NO_MANA := 43       ## a = skill slot, b = cost


static func pack_swing(w: int, step: int) -> int:
	return w * 16 + step


static func unpack_swing(b: float) -> Vector2i:
	var v := roundi(b)
	return Vector2i(v / 16, v % 16)
