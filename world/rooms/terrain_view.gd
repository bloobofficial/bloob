class_name TerrainView
extends Node2D
## Draws a room's terrain (prototype: render/renderer.ts buildTerrain + render/scenery.ts).
##
## 2D depth: ground-level cells (floor, paths, water, the scenery skirt) are drawn once here,
## underneath everything. Raised cells (stairs, plateaus, walls) become occluder nodes - one per
## run of equal-height cells in a row - placed in the y-sorted Actors layer at the run's north
## edge, so anything behind them is covered and anything in front is not. Trees and bushes are
## y-sorted sprites too, and go see-through when they stand between Bloob and the camera.
## Only south faces are drawn: with the camera looking north, east/west faces are edge-on and
## north faces point away (the prototype's slight perspective showed a sliver of them).

const UNDERSIDE := -260.0   ## island cliffs into the void go this deep
const SIDE_LIGHT := 0.78    ## south face brightness

var map: RoomMap
var theme: ThemeData
var _occluders: Array[Node] = []
var _trees: Array[Node2D] = []
var _tree_pos := PackedVector2Array()
var _tree_bush: Array[bool] = []
var _faded: Array[Sprite2D] = []


func _ready() -> void:
	Art.baked.connect(refresh_trees)


func build(m: RoomMap, th: ThemeData, actors: Node2D) -> void:
	map = m
	theme = th
	for n in _occluders:
		n.queue_free()
	for n in _trees:
		n.queue_free()
	_occluders.clear()
	_trees.clear()
	_tree_pos.clear()
	_tree_bush.clear()
	_faded.clear()
	var S := RoomMap.SKIRT
	# occluders: runs of raised cells per row
	for cy in range(-S, map.h + S):
		var run: Array = []
		var run_h := Tuning.VOID_H
		for cx in range(-S, map.w + S + 1):
			var hh := Tuning.VOID_H
			if cx < map.w + S:
				var l := map.look_cell(cx, cy)
				if l.h != Tuning.VOID_H and l.h > 0 and l.mat != RoomMap.Mat.TREE and l.mat != RoomMap.Mat.BUSH and l.mat != RoomMap.Mat.WATER:
					hh = l.h
			if hh != run_h or hh == Tuning.VOID_H:
				if run.size() > 0:
					_add_occluder(actors, run, cy)
				run = []
				run_h = hh
			if hh != Tuning.VOID_H:
				run.append(cx)
	_build_trees(actors)
	queue_redraw()


func _add_occluder(actors: Node2D, cells: Array, cy: int) -> void:
	var occ := TerrainOccluder.new()
	occ.view = self
	occ.cells = cells
	occ.cy = cy
	occ.position = Vector2(0, cy * Tuning.CELL + 1.0)
	actors.add_child(occ)
	_occluders.append(occ)


## the colour of a cell's top (prototype: topColor)
func top_color(l: Dictionary, cx: int, cy: int) -> Color:
	var n := RoomMap.hash2(cx, cy) * 0.05 - 0.025
	var checker := 0.012 if (cx + cy) & 1 else -0.012
	var hh: int = l.h
	var c: Color
	if l.door or l.mat == RoomMap.Mat.PATH:
		c = theme.path
	elif l.mat == RoomMap.Mat.STONE:
		c = theme.wall
	elif l.mat == RoomMap.Mat.TREE or l.mat == RoomMap.Mat.BUSH:
		c = theme.foliage
	elif l.mat == RoomMap.Mat.WATER:
		c = theme.water
	elif hh >= Tuning.LEVEL_H * 2:
		c = theme.high
	elif hh >= Tuning.LEVEL_H:
		c = theme.plateau
	elif hh > 0:
		c = theme.stairs
	else:
		c = theme.floor
	# scenery outside the layout fades into the dusk
	var k := maxf(0.35, 1.0 - l.out * 0.055) if l.out > 0 else 1.0
	var wet := 0.5 if l.mat == RoomMap.Mat.WATER else 1.0
	return Color((c.r + n * wet + checker * wet) * k, (c.g + n * wet + checker * wet) * k, (c.b + n * 0.8 * wet + checker * wet) * k)


## draw one cell's top and south face onto `ci`, in world space shifted by `-origin`
func draw_cell(ci: CanvasItem, cx: int, cy: int, origin: Vector2) -> void:
	var l := map.look_cell(cx, cy)
	var hh: int = l.h
	if hh == Tuning.VOID_H:
		return
	var C := float(Tuning.CELL)
	var x0 := cx * C - origin.x
	var x1 := x0 + C
	var y0 := cy * C - origin.y
	var y1 := y0 + C
	var top := View.lift(hh)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(x0, y0 + top), Vector2(x1, y0 + top), Vector2(x1, y1 + top), Vector2(x0, y1 + top)]), top_color(l, cx, cy))
	var nh: int = map.look_cell(cx, cy + 1).h
	if nh != Tuning.VOID_H and nh >= hh:
		return
	var bottom := UNDERSIDE if nh == Tuning.VOID_H else float(nh)
	var fade := maxf(0.35, 1.0 - l.out * 0.055) if l.out > 0 else 1.0
	var sc: Color = theme.wall_side if l.mat == RoomMap.Mat.STONE else theme.cliff
	var top_c := Color(sc.r * SIDE_LIGHT * fade, sc.g * SIDE_LIGHT * fade, sc.b * SIDE_LIGHT * fade)
	var kb := 0.25 if nh == Tuning.VOID_H else 0.7
	var bot_c := Color(sc.r * SIDE_LIGHT * kb * fade, sc.g * SIDE_LIGHT * kb * fade, sc.b * SIDE_LIGHT * kb * fade)
	var yb := y1 + View.lift(bottom)
	ci.draw_polygon(PackedVector2Array([Vector2(x0, y1 + top), Vector2(x1, y1 + top), Vector2(x1, yb), Vector2(x0, yb)]),
		PackedColorArray([top_c, top_c, bot_c, bot_c]))


func is_raised(l: Dictionary) -> bool:
	return l.h != Tuning.VOID_H and l.h > 0 and l.mat != RoomMap.Mat.TREE and l.mat != RoomMap.Mat.BUSH and l.mat != RoomMap.Mat.WATER


func _draw() -> void:
	if map == null:
		return
	var S := RoomMap.SKIRT
	for cy in range(-S, map.h + S):
		for cx in range(-S, map.w + S):
			var l := map.look_cell(cx, cy)
			if l.h == Tuning.VOID_H or is_raised(l):
				continue
			draw_cell(self, cx, cy, Vector2.ZERO)


# ---------------- trees and bushes (prototype: render/scenery.ts buildTrees) ----------------

func _build_trees(actors: Node2D) -> void:
	var S := RoomMap.SKIRT
	var C := float(Tuning.CELL)
	for cy in range(-S, map.h + S):
		for cx in range(-S, map.w + S):
			var l := map.look_cell(cx, cy)
			if l.h == Tuning.VOID_H or (l.mat != RoomMap.Mat.TREE and l.mat != RoomMap.Mat.BUSH):
				continue
			var r := RoomMap.hash2(cx, cy)
			var bush: bool = l.mat == RoomMap.Mat.BUSH
			var out: int = l.out
			var density: float
			if bush:
				density = 0.55 if out == 0 else maxf(0.2, 0.5 - out * 0.04)
			else:
				density = 0.78 if out == 0 else (0.62 if out < 6 else 0.45)
			if r > density:
				continue
			var jx := (RoomMap.hash2(cx + 91, cy) - 0.5) * C * 0.7
			var jy := (RoomMap.hash2(cx, cy + 57) - 0.5) * C * 0.6
			var variant := 3 + floori(RoomMap.hash2(cx + 7, cy + 3) * 2) if bush else floori(RoomMap.hash2(cx + 3, cy + 11) * 3)
			var sc := (0.8 if bush else 0.85) + RoomMap.hash2(cx + 13, cy + 29) * 0.3
			var tree := Node2D.new()
			tree.position = Vector2((cx + 0.5) * C + jx, (cy + 0.5) * C + jy)
			var spr := Sprite2D.new()
			spr.texture = Art.frame("tree.%d" % variant)
			var size := (0.46 if bush else 1.0) * sc
			spr.position = Vector2(0, View.lift(l.h))
			spr.scale = Vector2(size, size * View.upright())
			spr.offset = Vector2(0, -(0.5 - 0.04) * 96.0)
			spr.flip_h = RoomMap.hash2(cx + 5, cy + 5) < 0.5
			# darker than the playfield, and darker still the further out into the wild
			var k2 := (0.58 if bush else 0.66) * maxf(0.42, 1.0 - out * 0.05)
			spr.modulate = Color(theme.tree.r * k2, theme.tree.g * k2, theme.tree.b * k2)
			tree.add_child(spr)
			tree.set_meta("bush", bush)
			tree.set_meta("variant", variant)
			tree.set_meta("z", float(l.h))
			actors.add_child(tree)
			_trees.append(tree)
			_tree_pos.append(tree.position)
			_tree_bush.append(bush)


## make foliage between Bloob and the camera see-through (only trees near him can be)
func update_scenery(player_pos: Vector2) -> void:
	for i in _faded.size():
		var spr: Sprite2D = _faded[i]
		spr.self_modulate.a = 1.0
	_faded.clear()
	for i in _tree_pos.size():
		if _tree_bush[i]:
			continue
		var tp := _tree_pos[i]
		var dy := tp.y - player_pos.y
		if dy <= -6.0 or dy >= 250.0 or absf(tp.x - player_pos.x) >= 80.0 + dy * 0.25:
			continue
		var spr := _trees[i].get_child(0) as Sprite2D
		spr.self_modulate.a = 0.5
		_faded.append(spr)


## after the art bakes, or the camera tilts: retexture and re-stand every tree
func refresh_trees() -> void:
	for tree in _trees:
		var spr := tree.get_child(0) as Sprite2D
		spr.texture = Art.frame("tree.%d" % tree.get_meta("variant"))
		spr.scale.y = spr.scale.x * View.upright()
		spr.position.y = View.lift(tree.get_meta("z"))


func redraw_all() -> void:
	queue_redraw()
	refresh_trees()
	for o in _occluders:
		o.queue_redraw()
