class_name WeaponData
extends Resource
## A weapon: its ground combo, air swing, movement feel, art and Forge price
## (prototype: content/weapons.ts). Adding a weapon = a new .tres in data/weapons + an entry
## in data/weapons/order, plus a drawing in autoload/art.gd named like `sprite`.

@export var id := ""
@export var name := ""
@export_multiline var blurb := ""
@export var combo: Array[SwingData] = []
@export var air: SwingData
@export var move_mul := 1.0          ## run speed while holding it
@export var swing_move_mul := 0.3    ## steering while swinging
@export var combo_window := 16       ## ticks after a swing to press the next hit
@export var combo_end_cd := 8        ## pause after the finisher
@export var attack_speed := 1.0      ## > 1 = every swing's windup and follow-through is shorter
@export var mana_cost := 0.0         ## mana per swing that throws a bolt (see SwingData.bolt_damage)
## Forge price: Ichor, Bone, Wisp, Relic Shard
@export var cost := PackedInt32Array([0, 0, 0, 0])
@export var sprite := ""             ## atlas frame name (icon, rack, pickup, held)
@export var held := false            ## drawn in Bloob's hand (false = bare claws)
@export var art_scale := 0.3         ## world units per atlas pixel (96 px cell)
@export var grip := 0.1              ## where the hand holds it (fraction of height from bottom)
@export var rest := 0.0              ## screen tilt when not swinging (radians)
@export var fx_rim := Color(0.91, 0.12, 0.24)
@export var fx_trail := Color(0.95, 0.4, 0.45)
@export var fx_glow := Color(1, 0.25, 0.35)
@export var fx_heavy_glow := Color(1, 0.3, 0.3)
@export var traits := ""


func swing(step: int) -> SwingData:
	if step == Tuning.AIR_STEP:
		return air
	return combo[clampi(step - 1, 0, combo.size() - 1)]


## Bloob drawing to use for a swing (0..2)
func pose_of(step: int) -> int:
	var sw := swing(step)
	return sw.pose if sw.pose >= 0 else clampi(step - 1, 0, 2)


func combo_damage() -> float:
	var s := 0.0
	for sw in combo:
		s += sw.damage
	return s


func reach() -> float:
	var r := 0.0
	for sw in combo:
		r = maxf(r, sw.range)
	return r
