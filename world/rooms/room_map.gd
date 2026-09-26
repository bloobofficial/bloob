class_name RoomMap
extends RefCounted
## A room's height field (prototype: sim/map.ts). Every cell has a ground height or VOID
## (off the island). Rules: step up at most STEP_UP per cell, drop any amount, and only
## knockback can carry something into the void.
##
## Layout legend (one character = one 32-unit cell; ragged rows are padded with void):
##   ' ' void        '.' floor       ',' path        '#' stone wall / pillar
##   'T' trees       't' bushes      '~' water       'o' boulder
##        '1' plateau (48)   '2' high plateau (96)
##   'a' 'b' 'c' stairs 12/24/36     'd' 'e' 'f' stairs 60/72/84
##   '@' player start   '*' '&' '%' monster spawn on floor / plateau / high plateau
##   'A'..'D' passage cells (A north, B east, C south, D west)
##   'S' Shrine  'H' Well  'W' weapon rack  'P' local  'L' notice board  'X' cache  'R' reward spot

enum Mat { GROUND, STONE, TREE, BUSH, PATH, WATER, PROP, ROCK }

const MARKERS := "SHWPLXR"
const HEIGHTS := {
	".": 0, ",": 0, "*": 0, "@": 0, "1": 48, "&": 48, "2": 96, "%": 96,
	"a": 12, "b": 24, "c": 36, "d": 60, "e": 72, "f": 84,
}
## cells of scenery drawn around every room (prototype: render/scenery.ts SKIRT)
const SKIRT := 12

var w := 0            ## size in cells
var h := 0
var px_w := 0.0       ## size in world units
var px_h := 0.0
var height := PackedInt32Array()
## 1 = raised wall / pillar; 2 = solid at ground height (trees, bushes, water, stations)
var wall := PackedByteArray()
var mat := PackedByteArray()
var door := PackedByteArray()   ## door letter code per cell (0 = none)
## generated maps: which area each cell belongs to (area index + 1, 0 = none) and its floor
## style ('.' natural, 'w' wood, 's' stone, 'r' rug, 'h' hidden trail), as char codes
var zone := PackedByteArray()
var style := PackedByteArray()
var spawns: Array[Vector3] = []
var start := Vector3.ZERO
## [{id, cells, cx, cy, in_x, in_y}] sorted by id
var doors: Array[Dictionary] = []
## stations, locals and reward spots in reading order: [{ch, x, y, z, cell}]
var markers: Array[Dictionary] = []


func load_room(def: RoomData) -> void:
	var rows := def.layout
	h = mini(Tuning.GRID_H, rows.size())
	w = 0
	for r in rows:
		w = maxi(w, r.length())
	w = mini(Tuning.GRID_W, w)
	px_w = w * Tuning.CELL
	px_h = h * Tuning.CELL
	var n := w * h
	height = PackedInt32Array(); height.resize(n); height.fill(Tuning.VOID_H)
	wall = PackedByteArray(); wall.resize(n)
	mat = PackedByteArray(); mat.resize(n)
	door = PackedByteArray(); door.resize(n)
	zone = PackedByteArray(); zone.resize(n)
	style = PackedByteArray(); style.resize(n); style.fill(46)
	for y in mini(h, def.zones.size()):
		var zr: String = def.zones[y]
		var sr: String = def.styles[y] if y < def.styles.size() else ""
		for x in mini(w, zr.length()):
			var zc := zr.unicode_at(x)
			if zc != 32:
				zone[y * w + x] = zc - 47
			if x < sr.length():
				style[y * w + x] = sr.unicode_at(x)
	spawns.clear()
	doors.clear()
	markers.clear()
	var door_cells := {}
	var sx := px_w / 2.0
	var sy := px_h / 2.0
	var has_start := false
	for y in h:
		var row := rows[y]
		for x in w:
			var ch := row[x] if x < row.length() else " "
			if ch == " ":
				continue
			var c := y * w + x
			var wx := (x + 0.5) * Tuning.CELL
			var wy := (y + 0.5) * Tuning.CELL
			if ch >= "A" and ch <= "D":
				height[c] = 0
				door[c] = ch.unicode_at(0)
				if not door_cells.has(ch):
					door_cells[ch] = []
				door_cells[ch].append(c)
				continue
			if ch == "#":
				wall[c] = 1
				mat[c] = Mat.STONE
				height[c] = 0   # raised below, once the ground around it is known
				continue
			if ch == "T" or ch == "t" or ch == "~" or ch == "o":
				wall[c] = 2
				mat[c] = Mat.TREE if ch == "T" else (Mat.BUSH if ch == "t" else (Mat.ROCK if ch == "o" else Mat.WATER))
				height[c] = -10 if ch == "~" else 0
				continue
			if MARKERS.contains(ch):
				# stations and locals are solid props; 'R' is a floor spot
				if ch != "R":
					wall[c] = 2
					mat[c] = Mat.PROP
				height[c] = 0
				markers.append({ch = ch, x = wx, y = wy, z = 0.0, cell = c})
				continue
			height[c] = HEIGHTS.get(ch, 0)
			if ch == ",":
				mat[c] = Mat.PATH
			if ch == "*" or ch == "&" or ch == "%":
				spawns.append(Vector3(wx, wy, height[c]))
			if ch == "@":
				sx = wx
				sy = wy
				has_start = true
	# walls stand WALL_H above the highest walkable ground next to them; ground-level solids
	# (trees, water, stations) settle onto that ground (water a little below it)
	var base := PackedInt32Array(); base.resize(n)
	for y in h:
		for x in w:
			var c := y * w + x
			if not wall[c]:
				continue
			var b := 0
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var nc := ny * w + nx
					if not wall[nc] and height[nc] != Tuning.VOID_H:
						b = maxi(b, height[nc])
			base[c] = b
	for c in n:
		if wall[c] == 1:
			height[c] = base[c] + Tuning.WALL_H
		elif wall[c] == 2:
			height[c] = base[c] + (-10 if mat[c] == Mat.WATER else 0)
	for m in markers:
		if m.ch != "R":
			height[m.cell] = base[m.cell]
		m.z = float(height[m.cell])
	start = Vector3(sx, sy, 0)
	var mid_x := px_w / 2.0
	var mid_y := px_h / 2.0
	var ids := door_cells.keys()
	ids.sort()
	for id in ids:
		var cells: Array = door_cells[id]
		var cx := 0.0
		var cy := 0.0
		for c in cells:
			cx += (c % w + 0.5) * Tuning.CELL
			cy += (c / w + 0.5) * Tuning.CELL
		cx /= cells.size()
		cy /= cells.size()
		# arrival point: step inward from the door toward the room's middle until on plain floor
		var dx := mid_x - cx
		var dy := mid_y - cy
		if absf(dx) > absf(dy):
			dx = signf(dx); dy = 0.0
		else:
			dy = signf(dy); dx = 0.0
		var ix := cx
		var iy := cy
		for k in 12:
			ix += dx * Tuning.CELL * 0.5
			iy += dy * Tuning.CELL * 0.5
			if door_at(ix, iy) == 0 and walkable(ix, iy) and k >= 3:
				break
		doors.append({id = id, cells = cells, cx = cx, cy = cy, in_x = ix, in_y = iy})
	if not has_start:
		if doors.size() > 0:
			start = Vector3(doors[0].in_x, doors[0].in_y, 0)
		else:
			var oc := nearest_open(px_w / 2.0, px_h / 2.0)
			start = Vector3((oc.x + 0.5) * Tuning.CELL, (oc.y + 0.5) * Tuning.CELL, 0)
	start.z = ground_at(start.x, start.y)


func in_grid(cx: int, cy: int) -> bool:
	return cx >= 0 and cy >= 0 and cx < w and cy < h


func cell_of(x: float, y: float) -> int:
	var cx := floori(x / Tuning.CELL)
	var cy := floori(y / Tuning.CELL)
	if cx < 0 or cy < 0 or cx >= w or cy >= h:
		return -1
	return cy * w + cx


## ground height at a point, or VOID_H
func ground_at(x: float, y: float) -> int:
	var c := cell_of(x, y)
	return Tuning.VOID_H if c < 0 else height[c]


func walkable(x: float, y: float) -> bool:
	var c := cell_of(x, y)
	return c >= 0 and height[c] != Tuning.VOID_H and not wall[c]


func door_at(x: float, y: float) -> int:
	var c := cell_of(x, y)
	return 0 if c < 0 else door[c]


## the generated area a point lies in (index into RoomData.areas), or -1
func area_at(x: float, y: float) -> int:
	var c := cell_of(x, y)
	return -1 if c < 0 else zone[c] - 1


func door_info(id: String) -> Dictionary:
	for d in doors:
		if d.id == id:
			return d
	return {}


## can a circle standing at height z put its center at (x, y)? (4 corners, like the prototype)
func can_stand(x: float, y: float, r: float, z: float, allow_void: bool) -> bool:
	var k := r * 0.8
	return _ok_corner(x - k, y - k, z, allow_void) and _ok_corner(x + k, y - k, z, allow_void) \
		and _ok_corner(x - k, y + k, z, allow_void) and _ok_corner(x + k, y + k, z, allow_void)


func _ok_corner(x: float, y: float, z: float, allow_void: bool) -> bool:
	var c := cell_of(x, y)
	if c >= 0 and wall[c] == 2:
		return false
	var g := ground_at(x, y)
	if g == Tuning.VOID_H:
		return allow_void
	return g - z <= Tuning.STEP_UP


## 0 = open, 1 = island edge, 2 = solid (wall / cliff face / ground-level solid)
func blocks(cx: int, cy: int, z: float, allow_void: bool) -> int:
	if not in_grid(cx, cy):
		return 0 if allow_void else 1
	var c := cy * w + cx
	if wall[c] == 2:
		return 2
	var hh := height[c]
	if hh == Tuning.VOID_H:
		return 0 if allow_void else 1
	return 2 if hh - z > Tuning.STEP_UP else 0


## Circle-vs-cell movement with sliding (prototype: RoomMap.moveCircle). Bodies use Godot
## physics; this is kept for path checks (Blink walks its path in steps with it).
## Returns [new_position: Vector2, hit: bool, hit_solid: bool].
func move_circle(x: float, y: float, dx: float, dy: float, r: float, z: float, allow_void: bool) -> Array:
	var length := sqrt(dx * dx + dy * dy)
	var steps := maxi(1, ceili(length / maxf(2.0, r * 0.9)))
	var sx := dx / steps
	var sy := dy / steps
	var px := x
	var py := y
	var hit := false
	var solid := false
	var C := float(Tuning.CELL)
	for k in steps:
		px += sx
		py += sy
		for pass_i in 3:
			var pushed := false
			for cy in range(floori((py - r) / C), floori((py + r) / C) + 1):
				for cx in range(floori((px - r) / C), floori((px + r) / C) + 1):
					var b := blocks(cx, cy, z, allow_void)
					if b == 0:
						continue
					var x0 := cx * C
					var x1 := x0 + C
					var y0 := cy * C
					var y1 := y0 + C
					var qx := clampf(px, x0, x1)
					var qy := clampf(py, y0, y1)
					var ox := px - qx
					var oy := py - qy
					var d2 := ox * ox + oy * oy
					if d2 >= r * r:
						continue
					if d2 > 1e-9:
						var d := sqrt(d2)
						var push := r - d + 0.01
						px += ox / d * push
						py += oy / d * push
					else:
						var l := px - x0
						var rr := x1 - px
						var u := py - y0
						var dn := y1 - py
						var m := minf(minf(l, rr), minf(u, dn))
						if m == l:
							px = x0 - r - 0.01
						elif m == rr:
							px = x1 + r + 0.01
						elif m == u:
							py = y0 - r - 0.01
						else:
							py = y1 + r + 0.01
					pushed = true
					hit = true
					if b == 2:
						solid = true
			if not pushed:
				break
	return [Vector2(px, py), hit, solid]


## a projectile at height z hits terrain here
func blocks_shot(x: float, y: float, z: float) -> bool:
	var c := cell_of(x, y)
	if c < 0:
		return false
	var m := mat[c]
	if m == Mat.TREE or m == Mat.PROP or m == Mat.ROCK:
		return true
	var hh := height[c]
	return hh != Tuning.VOID_H and hh > z


## nearest walkable cell to (x, y)
func nearest_open(x: float, y: float) -> Vector2i:
	var cx0 := clampi(floori(x / Tuning.CELL), 0, maxi(0, w - 1))
	var cy0 := clampi(floori(y / Tuning.CELL), 0, maxi(0, h - 1))
	if _open(cx0, cy0):
		return Vector2i(cx0, cy0)
	for ring in range(1, 12):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dy) != ring:
					continue
				if _open(cx0 + dx, cy0 + dy):
					return Vector2i(cx0 + dx, cy0 + dy)
	return Vector2i(cx0, cy0)


func _open(cx: int, cy: int) -> bool:
	if not in_grid(cx, cy):
		return false
	var c := cy * w + cx
	return height[c] != Tuning.VOID_H and not wall[c]


## What a cell looks like, inside the layout or out in the scenery skirt
## (prototype: render/scenery.ts lookCell). Returns {h, mat, door, wall, out}.
func look_cell(cx: int, cy: int) -> Dictionary:
	var sx := clampi(cx, 0, w - 1)
	var sy := clampi(cy, 0, h - 1)
	var out := maxi(maxi(sx - cx, cx - sx), maxi(sy - cy, cy - sy))
	var c := sy * w + sx
	var hh := height[c]
	if out == 0:
		return {h = hh, mat = mat[c], door = door[c] != 0, wall = wall[c], out = 0, style = style[c]}
	if hh == Tuning.VOID_H:
		return {h = Tuning.VOID_H, mat = Mat.GROUND, door = false, wall = 0, out = out, style = 46}
	if door[c] != 0:
		# the passage continues as a path into the distance
		return {h = hh, mat = Mat.PATH, door = true, wall = 0, out = out, style = 46}
	if wall[c] == 1:
		return {h = hh, mat = Mat.STONE, door = false, wall = 1, out = out, style = 46}
	# open floor reaching the edge of a layout is an island's rim: the world falls away there
	if wall[c] == 0:
		return {h = Tuning.VOID_H, mat = Mat.GROUND, door = false, wall = 0, out = out, style = 46}
	# trees, bushes and water become wild ground: bushes toward the camera (south), forest elsewhere
	return {h = hh + 10 if mat[c] == Mat.WATER else hh, mat = Mat.BUSH if cy >= h else Mat.TREE, door = false, wall = 2, out = out, style = 46}


static func hash2(x: int, y: int) -> float:
	var hv := (x * 374761393 + y * 668265263) & 0xFFFFFFFF
	hv = ((hv ^ (hv >> 13)) * 1274126177) & 0xFFFFFFFF
	return float((hv ^ (hv >> 16)) & 0xFFFFFFFF) / 4294967296.0
