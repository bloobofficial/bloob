class_name TerrainView
extends Node2D
## Draws a room's terrain in pixel art (prototype: render/renderer.ts buildTerrain +
## render/scenery.ts; tiles from effects/art/world_art.gd).
##
## 2D depth: ground-level cells (floor, paths, water, the scenery skirt) are drawn here,
## underneath everything, in chunks of CHUNK x CHUNK cells (each its own canvas item, so the
## chunks off screen are culled). Raised cells (stairs, plateaus, walls) become occluder nodes
## - one per run of equal-height cells in a row - placed in the y-sorted Actors layer at the
## run's north edge, so anything behind them is covered and anything in front is not. Trees and
## bushes are y-sorted sprites too, and go see-through when they stand between Bloob and the
## camera. Only south faces are drawn: with the camera looking north, east/west faces are
## edge-on and north faces point away.
##
## Depth cues: cliff faces with a lip of grass over the edge, darkening as they fall, and
## island undersides that sink into the dusk; ambient occlusion where the ground meets a wall;
## soft shadows under every tree; foreshortened ground against square-on faces.

const UNDERSIDE := -260.0   ## island cliffs into the void go this deep
const SIDE_LIGHT := 0.78    ## south face brightness
const CHUNK := 16


## one drawing layer: a ground chunk, or the tree shadows
class Layer:
	extends Node2D
	var view: TerrainView
	var rect := Rect2i()
	var shadows := false

	func _draw() -> void:
		if shadows:
			view.draw_shadows(self)
		else:
			view.draw_chunk(self, rect)


var map: RoomMap
var theme: ThemeData
var tiles := {}
var _layers: Array[Node] = []
var _occluders: Array[Node] = []
var _trees: Array[Node2D] = []
var _tree_pos := PackedVector2Array()
var _tree_bush: Array[bool] = []
var _tree_size := PackedFloat32Array()
var _faded: Array[Sprite2D] = []


func _ready() -> void:
	Art.baked.connect(refresh_trees)


func build(m: RoomMap, th: ThemeData, actors: Node2D) -> void:
	map = m
	theme = th
	tiles = WorldArt.tiles_for(th)
	for n in _occluders:
		n.queue_free()
	for n in _trees:
		n.queue_free()
	for n in _layers:
		n.queue_free()
	_occluders.clear()
	_trees.clear()
	_layers.clear()
	_tree_pos.clear()
	_tree_bush.clear()
	_tree_size.clear()
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
				if is_raised(l):
					hh = l.h
			if hh != run_h or hh == Tuning.VOID_H:
				if run.size() > 0:
					_add_occluder(actors, run, cy)
				run = []
				run_h = hh
			if hh != Tuning.VOID_H:
				run.append(cx)
	# ground chunks, then the shadow layer over them
	for cy0 in range(-S, map.h + S, CHUNK):
		for cx0 in range(-S, map.w + S, CHUNK):
			var lay := Layer.new()
			lay.view = self
			lay.rect = Rect2i(cx0, cy0, mini(CHUNK, map.w + S - cx0), mini(CHUNK, map.h + S - cy0))
			add_child(lay)
			_layers.append(lay)
	_build_trees(actors)
	var sh := Layer.new()
	sh.view = self
	sh.shadows = true
	add_child(sh)
	_layers.append(sh)


func _add_occluder(actors: Node2D, cells: Array, cy: int) -> void:
	var occ := TerrainOccluder.new()
	occ.view = self
	occ.cells = cells
	occ.cy = cy
	occ.position = Vector2(0, cy * Tuning.CELL + 1.0)
	actors.add_child(occ)
	_occluders.append(occ)


## the flat colour of a cell's top (the minimap and anything that wants a swatch)
func top_color(l: Dictionary, _cx: int, _cy: int) -> Color:
	var hh: int = l.h
	var st: int = l.get("style", 46)
	if st == 119:
		return tiles.wood
	if st == 115:
		return tiles.stone
	if st == 114:
		return tiles.rug
	if l.door or l.mat == RoomMap.Mat.PATH:
		return tiles.dirt
	if l.mat == RoomMap.Mat.STONE:
		return tiles.rock
	if l.mat == RoomMap.Mat.TREE or l.mat == RoomMap.Mat.BUSH:
		return tiles.forest
	if l.mat == RoomMap.Mat.WATER:
		return tiles.water
	if hh > 0 and hh < Tuning.LEVEL_H:
		return tiles.rock
	return tiles.grass.lightened(0.08 if hh >= Tuning.LEVEL_H else 0.0)


func _is_path(cx: int, cy: int) -> bool:
	var l := map.look_cell(cx, cy)
	return l.h != Tuning.VOID_H and (l.door or l.mat == RoomMap.Mat.PATH)


func _is_rug(cx: int, cy: int) -> bool:
	return map.look_cell(cx, cy).get("style", 46) == 114


func _pick(name: String, cx: int, cy: int) -> Rect2:
	var list: Array = tiles.r[name]
	return list[int(RoomMap.hash2(cx * 3 + 1, cy * 5 + 2) * list.size()) % list.size()]


## which tile a cell's top shows
func _top_tile(l: Dictionary, cx: int, cy: int) -> Rect2:
	var st: int = l.get("style", 46)
	var hh: int = l.h
	if l.wall == 1:
		return _pick("wood_top" if st == 119 else ("pillar_top" if st == 115 else "rock_top"), cx, cy)
	if l.mat == RoomMap.Mat.TREE or l.mat == RoomMap.Mat.BUSH:
		return _pick("forest", cx, cy)
	if l.mat == RoomMap.Mat.WATER:
		return _pick("water", cx, cy)
	if l.mat == RoomMap.Mat.ROCK:
		return tiles.r.grass[int(RoomMap.hash2(cx + 9, cy + 13) * 6) % 6]
	if st == 119:
		return _pick("wood", cx, cy)
	if st == 115:
		return _pick("stone", cx, cy)
	if st == 114:
		var rm := (0 if _is_rug(cx, cy - 1) else 1) | (0 if _is_rug(cx + 1, cy) else 2) | (0 if _is_rug(cx, cy + 1) else 4) | (0 if _is_rug(cx - 1, cy) else 8)
		return tiles.r["rug%d" % rm][0]
	if l.door or l.mat == RoomMap.Mat.PATH:
		var mask := (0 if _is_path(cx, cy - 1) else 1) | (0 if _is_path(cx + 1, cy) else 2) | (0 if _is_path(cx, cy + 1) else 4) | (0 if _is_path(cx - 1, cy) else 8)
		return _pick("path%d" % mask, cx, cy)
	if hh > 0 and hh < Tuning.LEVEL_H:
		return _pick("stairs", cx, cy)
	if st == 104:
		return _pick("trail", cx, cy)
	# grass: now and then a patch of flowers
	var list: Array = tiles.r.grass
	var r := RoomMap.hash2(cx * 7 + 11, cy * 3 + 5)
	if r > 0.9:
		return list[6 + int(r * 100) % 2]
	return list[int(RoomMap.hash2(cx + 9, cy + 13) * 6) % 6]


## the tile of a cell's south face, and whether it's the top segment (which may have a lip)
func _face_tile(l: Dictionary, cx: int, cy: int, first: bool) -> Rect2:
	var st: int = l.get("style", 46)
	if l.wall == 1:
		return _pick("wood_face" if st == 119 else ("pillar_face" if st == 115 else "rock_face"), cx, cy)
	if st == 119 or st == 115 or st == 114:
		return _pick("wood_lip", cx, cy)
	if first and l.mat != RoomMap.Mat.WATER and not l.door and l.mat != RoomMap.Mat.PATH:
		return _pick("cliff_lip", cx, cy)
	return _pick("cliff", cx, cy + (0 if first else 7))


func _tint(l: Dictionary, cx: int, cy: int) -> Color:
	var hh: int = l.h
	var k := 1.0 + (RoomMap.hash2(cx + 31, cy + 17) - 0.5) * 0.06
	if hh >= Tuning.LEVEL_H * 2:
		k *= 1.16
	elif hh >= Tuning.LEVEL_H:
		k *= 1.09
	if l.out > 0:
		k *= maxf(0.35, 1.0 - l.out * 0.055)   # scenery outside the layout fades into the dusk
	return Color(k, k, k)


## draw one cell's top and south face onto `ci`, in world space shifted by `-origin`
func draw_cell(ci: CanvasItem, cx: int, cy: int, origin: Vector2) -> void:
	var l := map.look_cell(cx, cy)
	var hh: int = l.h
	if hh == Tuning.VOID_H:
		return
	var C := float(Tuning.CELL)
	var x0 := cx * C - origin.x
	var y0 := cy * C - origin.y
	var y1 := y0 + C
	var top := View.lift(hh)
	var tex: Texture2D = tiles.tex
	var tint := _tint(l, cx, cy)
	ci.draw_texture_rect_region(tex, Rect2(x0, y0 + top, C, C), _top_tile(l, cx, cy), tint)
	if hh > 0 and is_raised(l):
		# a lit rim along the front edge of raised ground
		ci.draw_rect(Rect2(x0, y1 + top - 2.0, C, 2.0), Color(1, 1, 0.9, 0.12))
	var nh: int = map.look_cell(cx, cy + 1).h
	if nh != Tuning.VOID_H and nh >= hh:
		return
	var bottom := float(nh)
	if nh == Tuning.VOID_H:
		# island undersides: ragged, deep, sinking into the dusk
		bottom = UNDERSIDE * (0.7 + RoomMap.hash2(cx * 13 + 1, 77) * 0.45)
	var y_top := y1 + top
	var yb := y1 + View.lift(bottom)
	var seg := C / View.ground_k
	var y := y_top
	var first := true
	var fade := maxf(0.35, 1.0 - l.out * 0.055) if l.out > 0 else 1.0
	var face_tint := Color(SIDE_LIGHT * fade, SIDE_LIGHT * fade, SIDE_LIGHT * fade)
	while y < yb - 0.5:
		var hs := minf(seg, yb - y)
		var reg := _face_tile(l, cx, cy, first)
		if hs < seg:
			reg.size.y *= hs / seg
		ci.draw_texture_rect_region(tex, Rect2(x0, y, C, hs), reg, face_tint)
		y += hs
		first = false
	# darker as it falls; a drop into the void fades out into the dusk
	var clear := Color(0, 0, 0, 0)
	if nh != Tuning.VOID_H:
		var bot := Color(0, 0, 0, 0.3)
		ci.draw_polygon(PackedVector2Array([Vector2(x0, y_top), Vector2(x0 + C, y_top), Vector2(x0 + C, yb), Vector2(x0, yb)]),
			PackedColorArray([clear, clear, bot, bot]))
		return
	var fog: Color = theme.fog
	var y_mid := y_top + (yb - y_top) * 0.4
	var mid := Color(fog, 0.5)
	var bot2 := Color(fog, 1.0)
	ci.draw_polygon(PackedVector2Array([Vector2(x0, y_top), Vector2(x0 + C, y_top), Vector2(x0 + C, y_mid), Vector2(x0, y_mid)]),
		PackedColorArray([clear, clear, mid, mid]))
	ci.draw_polygon(PackedVector2Array([Vector2(x0, y_mid), Vector2(x0 + C, y_mid), Vector2(x0 + C, yb), Vector2(x0, yb)]),
		PackedColorArray([mid, mid, bot2, bot2]))


func is_raised(l: Dictionary) -> bool:
	return l.h != Tuning.VOID_H and l.h > 0 and l.mat != RoomMap.Mat.TREE and l.mat != RoomMap.Mat.BUSH and l.mat != RoomMap.Mat.WATER


func _solid_above(cx: int, cy: int, hh: int) -> bool:
	var l := map.look_cell(cx, cy)
	return l.h != Tuning.VOID_H and (l.h > hh + 8 or l.wall == 1)


func draw_chunk(ci: CanvasItem, r: Rect2i) -> void:
	if map == null:
		return
	var C := float(Tuning.CELL)
	for cy in range(r.position.y, r.end.y):
		for cx in range(r.position.x, r.end.x):
			var l := map.look_cell(cx, cy)
			if l.h == Tuning.VOID_H or is_raised(l):
				continue
			draw_cell(ci, cx, cy, Vector2.ZERO)
			if l.mat == RoomMap.Mat.WATER:
				continue
			# ambient occlusion where the ground meets a wall or a ledge
			var hh: int = l.h
			var x0 := cx * C
			var y0 := cy * C + View.lift(hh)
			if _solid_above(cx, cy - 1, hh):
				ci.draw_polygon(PackedVector2Array([Vector2(x0, y0), Vector2(x0 + C, y0), Vector2(x0 + C, y0 + 12), Vector2(x0, y0 + 12)]),
					PackedColorArray([Color(0, 0, 0, 0.34), Color(0, 0, 0, 0.34), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))
			if _solid_above(cx - 1, cy, hh):
				ci.draw_polygon(PackedVector2Array([Vector2(x0, y0), Vector2(x0 + 9, y0), Vector2(x0 + 9, y0 + C), Vector2(x0, y0 + C)]),
					PackedColorArray([Color(0, 0, 0, 0.26), Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.26)]))
			if _solid_above(cx + 1, cy, hh):
				ci.draw_polygon(PackedVector2Array([Vector2(x0 + C - 9, y0), Vector2(x0 + C, y0), Vector2(x0 + C, y0 + C), Vector2(x0 + C - 9, y0 + C)]),
					PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.26), Color(0, 0, 0, 0.26), Color(0, 0, 0, 0)]))


## soft shadows under the trees and bushes, cast a little toward the south east
func draw_shadows(ci: CanvasItem) -> void:
	var disc := Draw25.disc()
	for i in _tree_pos.size():
		var p := _tree_pos[i]
		var s := _tree_size[i]
		if s <= 0.0:
			continue
		var z: float = _trees[i].get_meta("z")
		var at := Vector2(p.x + 5.0 * s, p.y + 3.0 + View.lift(z))
		var rx := (15.0 if _tree_bush[i] else 30.0) * s
		var ry := (10.0 if _tree_bush[i] else 20.0) * s
		ci.draw_texture_rect(disc, Rect2(at.x - rx, at.y - ry, rx * 2.0, ry * 2.0), false, Color(0, 0, 0, 0.3))


# ---------------- trees and bushes (prototype: render/scenery.ts buildTrees) ----------------

func _build_trees(actors: Node2D) -> void:
	var S := RoomMap.SKIRT
	var C := float(Tuning.CELL)
	var tint: Color = theme.tree.lerp(Color.WHITE, 0.45)
	for cy in range(-S, map.h + S):
		for cx in range(-S, map.w + S):
			var l := map.look_cell(cx, cy)
			if l.h == Tuning.VOID_H:
				continue
			if l.mat == RoomMap.Mat.ROCK:
				_add_rock(actors, cx, cy, float(l.h))
				continue
			if l.mat != RoomMap.Mat.TREE and l.mat != RoomMap.Mat.BUSH:
				continue
			var r := RoomMap.hash2(cx, cy)
			var bush: bool = l.mat == RoomMap.Mat.BUSH
			var out: int = l.out
			var density: float
			if bush:
				density = 0.7 if out == 0 else maxf(0.2, 0.5 - out * 0.04)
			else:
				density = 0.8 if out == 0 else (0.62 if out < 6 else 0.45)
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
			var size := (0.62 if bush else 1.0) * sc
			spr.position = Vector2(0, View.lift(l.h))
			spr.scale = Vector2(size, size * View.upright())
			spr.offset = Vector2(0, -(0.5 - 0.04) * 96.0)
			spr.flip_h = RoomMap.hash2(cx + 5, cy + 5) < 0.5
			# the further out into the wild, the darker
			var k2 := maxf(0.42, 1.0 - out * 0.05) * (0.92 if bush else 1.0)
			spr.modulate = Color(tint.r * k2, tint.g * k2, tint.b * k2)
			tree.add_child(spr)
			tree.set_meta("bush", bush)
			tree.set_meta("variant", variant)
			tree.set_meta("z", float(l.h))
			actors.add_child(tree)
			_trees.append(tree)
			_tree_pos.append(tree.position)
			_tree_bush.append(bush)
			_tree_size.append(sc * (0.62 if bush else 1.0) if out == 0 else 0.0)


## a boulder (solid, like a bush for the see-through rule: it's low enough not to need it)
func _add_rock(actors: Node2D, cx: int, cy: int, z: float) -> void:
	var C := float(Tuning.CELL)
	var node := Node2D.new()
	node.position = Vector2((cx + 0.5) * C + (RoomMap.hash2(cx + 3, cy) - 0.5) * 6.0, (cy + 0.5) * C + 6.0)
	var spr := Sprite2D.new()
	var variant := floori(RoomMap.hash2(cx + 1, cy + 2) * 2)
	spr.texture = Art.frame("rock.%d" % variant)
	var sc := 0.62 + RoomMap.hash2(cx + 4, cy + 8) * 0.18
	spr.position = Vector2(0, View.lift(z))
	spr.scale = Vector2(sc, sc * View.upright())
	spr.offset = Vector2(0, -(0.5 - 0.04) * 96.0)
	spr.flip_h = RoomMap.hash2(cx + 2, cy + 6) < 0.5
	var tint: Color = theme.tree.lerp(Color.WHITE, 0.7)
	spr.modulate = tint
	node.add_child(spr)
	node.set_meta("bush", true)
	node.set_meta("variant", -1 - variant)
	node.set_meta("z", z)
	actors.add_child(node)
	_trees.append(node)
	_tree_pos.append(node.position)
	_tree_bush.append(true)
	_tree_size.append(sc * 0.8)


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
		var v: int = tree.get_meta("variant")
		spr.texture = Art.frame("tree.%d" % v if v >= 0 else "rock.%d" % (-1 - v))
		spr.scale.y = spr.scale.x * View.upright()
		spr.position.y = View.lift(tree.get_meta("z"))


func redraw_all() -> void:
	for n in _layers:
		n.queue_redraw()
	refresh_trees()
	for o in _occluders:
		o.queue_redraw()
