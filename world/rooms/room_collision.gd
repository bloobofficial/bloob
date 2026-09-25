class_name RoomCollision
extends Node2D
## Builds the room's terrain collision for Godot physics from the height field.
##
## The prototype's rule (sim/map.ts `blocks`): a cell blocks a body whose feet are at height z
## if it is a ground-level solid (tree, bush, water, prop), or void (unless the body is being
## knocked around), or more than STEP_UP above z (walls, cliff faces).
## Here every cell goes on one physics layer:
##   layer 1  = ground-level solids (always blocks)
##   layer 2  = void + the space outside the layout (blocks walking, not knockback)
##   layer 3+ = one layer per distinct terrain height
## Each body sets its collision mask from its height every tick (mask_for), so stairs climb,
## cliffs block, you can jump onto a ledge, and only a knock carries anything off the island.

const LAYER_SOLID := 1
const LAYER_VOID := 2
const FIRST_HEIGHT_LAYER := 3
const LAST_HEIGHT_LAYER := 18
const LAYER_PLAYER := 20
const LAYER_ENEMY := 21

## height value -> physics layer number
var height_layers := {}


func build(map: RoomMap) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	height_layers.clear()
	var heights := []
	for c in map.w * map.h:
		var hh: int = map.height[c]
		if hh != Tuning.VOID_H and map.wall[c] != 2 and not heights.has(hh):
			heights.append(hh)
	heights.sort()
	for i in heights.size():
		height_layers[heights[i]] = mini(FIRST_HEIGHT_LAYER + i, LAST_HEIGHT_LAYER)
	# classify cells: -1 = open-for-everyone never happens; every cell gets a layer
	var classes := {}   # layer -> Array of cell rows runs
	var C := float(Tuning.CELL)
	for y in map.h:
		var run_layer := -1
		var run_start := 0
		for x in map.w + 1:
			var layer := -1
			if x < map.w:
				var c := y * map.w + x
				if map.wall[c] == 2:
					layer = LAYER_SOLID
				elif map.height[c] == Tuning.VOID_H:
					layer = LAYER_VOID
				else:
					layer = height_layers[map.height[c]]
			if layer != run_layer:
				if run_layer >= 0:
					if not classes.has(run_layer):
						classes[run_layer] = []
					classes[run_layer].append(Rect2(run_start * C, y * C, (x - run_start) * C, C))
				run_layer = layer
				run_start = x
	# the space outside the layout counts as void
	var pad := 256.0
	if not classes.has(LAYER_VOID):
		classes[LAYER_VOID] = []
	classes[LAYER_VOID].append(Rect2(-pad, -pad, map.px_w + pad * 2, pad))
	classes[LAYER_VOID].append(Rect2(-pad, map.px_h, map.px_w + pad * 2, pad))
	classes[LAYER_VOID].append(Rect2(-pad, 0, pad, map.px_h))
	classes[LAYER_VOID].append(Rect2(map.px_w, 0, pad, map.px_h))
	for layer in classes:
		var body := StaticBody2D.new()
		body.name = "Layer%d" % layer
		body.collision_layer = 1 << (layer - 1)
		body.collision_mask = 0
		body.set_meta("terrain_layer", layer)
		for rect in classes[layer]:
			var shape := RectangleShape2D.new()
			shape.size = rect.size
			var cs := CollisionShape2D.new()
			cs.shape = shape
			cs.position = rect.get_center()
			body.add_child(cs)
		add_child(body)


## the collision mask for a body whose feet are at height z
func mask_for(z: float, allow_void: bool) -> int:
	var m := 1 << (LAYER_SOLID - 1)
	if not allow_void:
		m |= 1 << (LAYER_VOID - 1)
	for hh in height_layers:
		if hh - z > Tuning.STEP_UP:
			m |= 1 << (height_layers[hh] - 1)
	return m


## what a slide collision hit: 2 = solid (wall / cliff / tree), 1 = island edge, 0 = other
static func hit_kind(collision: KinematicCollision2D) -> int:
	var col := collision.get_collider()
	if col == null or not col.has_meta("terrain_layer"):
		return 0
	return 1 if int(col.get_meta("terrain_layer")) == LAYER_VOID else 2
