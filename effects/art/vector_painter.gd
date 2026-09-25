class_name VectorPainter
extends Node2D
## Paints the prototype's placeholder vector art (render/art.ts): monsters, the totem, station
## props and trees, as ink-outlined shapes, into 96 x 96 cells. art.gd renders this node once
## in a SubViewport at boot and slices the result into textures, like the prototype's atlas.
## Replace any frame with real art later by keeping its name.

const CELL := 96
const GAP := 4
const COLS := 10
const INK := Color("#17131d")
const LW := 3.5

var cells: Array = []    ## [[name, Callable(cell_index)]]
var _xf := Transform2D.IDENTITY
var _stack: Array[Transform2D] = []
var _paths: Array = []   ## Array of PackedVector2Array
var _cur := PackedVector2Array()
var _closed: Array = []


func cell_origin(i: int) -> Vector2:
	return Vector2((i % COLS) * (CELL + GAP) + GAP / 2.0, (i / COLS) * (CELL + GAP) + GAP / 2.0)


func atlas_size() -> Vector2i:
	var rows := ceili(float(cells.size()) / COLS)
	return Vector2i(COLS * (CELL + GAP), rows * (CELL + GAP))


func _draw() -> void:
	for i in cells.size():
		_xf = Transform2D(0.0, cell_origin(i))
		_stack.clear()
		cells[i][1].call()


# ---------------- a tiny canvas-like pen ----------------

func save() -> void:
	_stack.append(_xf)


func restore() -> void:
	_xf = _stack.pop_back()


func shift(x: float, y: float) -> void:
	_xf = _xf * Transform2D(0.0, Vector2(x, y))


func turn(a: float) -> void:
	_xf = _xf * Transform2D(a, Vector2.ZERO)


func scale_by(sx: float, sy: float) -> void:
	_xf = _xf * Transform2D(0.0, Vector2(sx, sy), 0.0, Vector2.ZERO)


func begin() -> void:
	_paths.clear()
	_closed.clear()
	_cur = PackedVector2Array()


func _flush(closed: bool) -> void:
	if _cur.size() > 0:
		_paths.append(_cur)
		_closed.append(closed)
	_cur = PackedVector2Array()


func move_to(x: float, y: float) -> void:
	_flush(false)
	_cur.append(_xf * Vector2(x, y))


func line_to(x: float, y: float) -> void:
	_cur.append(_xf * Vector2(x, y))


func quad_to(cx: float, cy: float, x: float, y: float) -> void:
	var p0 := _xf.affine_inverse() * _cur[_cur.size() - 1] if _cur.size() > 0 else Vector2(cx, cy)
	for i in range(1, 11):
		var t := i / 10.0
		var q := p0.lerp(Vector2(cx, cy), t).lerp(Vector2(cx, cy).lerp(Vector2(x, y), t), t)
		_cur.append(_xf * q)


func close() -> void:
	_flush(true)


func ellipse(x: float, y: float, rx: float, ry: float, rot: float = 0.0) -> void:
	begin()
	var n := 28
	for i in n:
		var a := TAU * i / n
		var v := Vector2(cos(a) * maxf(0.5, rx), sin(a) * maxf(0.5, ry)).rotated(rot) + Vector2(x, y)
		_cur.append(_xf * v)
	_flush(true)


func round_rect(x: float, y: float, w: float, h: float, r: float) -> void:
	begin()
	r = minf(r, minf(w, h) / 2.0)
	var corners := [[x + w - r, y + r, -PI / 2], [x + w - r, y + h - r, 0.0], [x + r, y + h - r, PI / 2], [x + r, y + r, PI]]
	for c in corners:
		for i in 5:
			var a: float = c[2] + (PI / 2) * i / 4.0
			_cur.append(_xf * Vector2(c[0] + cos(a) * r, c[1] + sin(a) * r))
	_flush(true)


func rect_path(x: float, y: float, w: float, h: float) -> void:
	begin()
	for v in [Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]:
		_cur.append(_xf * v)
	_flush(true)


func fill(col: Color) -> void:
	_flush(true)
	for i in _paths.size():
		var pts: PackedVector2Array = _paths[i]
		if pts.size() >= 3 and Geometry2D.triangulate_polygon(pts).size() > 0:
			draw_colored_polygon(pts, col)


func stroke(col: Color, width: float) -> void:
	_flush(false)
	for i in _paths.size():
		var pts: PackedVector2Array = _paths[i]
		if pts.size() < 2:
			continue
		var line := pts.duplicate()
		if _closed[i]:
			line.append(pts[0])
		draw_polyline(line, col, width, true)
		if width >= 4.0:
			for v in line:
				draw_circle(v, width / 2.0, col)


## fill, then an ink outline (the prototype's `ink`)
func ink(fill_col: Color, lw: float = LW) -> void:
	fill(fill_col)
	stroke(INK, lw)


func shade(c: Color, k: float) -> Color:
	return Color(minf(1.0, c.r * k), minf(1.0, c.g * k), minf(1.0, c.b * k))


func line(pts: Array, col: Color, width: float) -> void:
	begin()
	move_to(pts[0].x, pts[0].y)
	for i in range(1, pts.size()):
		line_to(pts[i].x, pts[i].y)
	stroke(col, width)


func cross(x0: float, y0: float, x1: float, y1: float, width: float = 2.5) -> void:
	begin()
	move_to(x0, y0); line_to(x1, y1)
	move_to(x1, y0); line_to(x0, y1)
	stroke(INK, width)


# ---------------- monsters ----------------

func draw_charger(pose: String, i: int) -> void:
	var col := Color("#e0803a")
	var bob := sin(i / 4.0 * TAU) * 2.0 if pose == "walk" else 0.0
	var lean: float = {windup = 0.25, attack = -0.05, hurt = -0.2}.get(pose, 0.0)
	var stretch := 1.18 if pose == "attack" else (0.9 if pose == "hurt" else 1.0)
	var by := 64.0 + bob + (4.0 if pose == "windup" else 0.0)
	var leg_ph := i / 4.0 * TAU
	for lp in [[30, 0.0], [40, PI], [56, PI], [66, 0.0]]:
		var off := sin(leg_ph + lp[1]) * 4.0 if pose == "walk" else 0.0
		round_rect(lp[0] + off - 4, by + 8, 8, 18 - (4 if pose == "windup" else 0), 3)
		ink(shade(col, 0.7), 3)
	save()
	shift(48, by)
	turn(lean)
	scale_by(stretch, 1.0 / stretch)
	ellipse(0, 0, 30, 19); ink(col)
	begin(); move_to(-22, -12); line_to(-14, -22); line_to(-6, -15); line_to(2, -23); line_to(10, -15); stroke(shade(col, 0.75), 3)
	ellipse(26, 2, 13, 12); ink(shade(col, 1.08))
	ellipse(36, 6, 6, 5); ink(Color("#f1b28a"), 3)
	begin(); move_to(20, -8); quad_to(24, -24, 36, -22); quad_to(28, -16, 28, -6); ink(Color("#efe6d2"), 3)
	if pose == "hurt":
		cross(24, -4, 30, 2)
	else:
		ellipse(27, -1, 3, 3.2); fill(Color.WHITE)
		ellipse(28, -1, 1.6, 1.8); fill(INK)
		line([Vector2(22, -6), Vector2(31, -3)], INK, 2.5)
	restore()
	if pose == "windup":
		for dr in [[-30, 4], [-38, 3]]:
			ellipse(48 + dr[0], 86, dr[1], dr[1] * 0.7); ink(Color("#b9ab95"), 2)


func draw_weaver(pose: String, i: int) -> void:
	var col := Color("#b9d45a")
	var ph := i / 4.0 * TAU
	var amp := 14.0 if pose == "windup" else (2.0 if pose == "attack" else 9.0)
	var head_x := 58.0 if pose == "windup" else (80.0 if pose == "attack" else 68.0)
	var pts := []
	for k in 11:
		var t := k / 10.0
		pts.append(Vector2(12 + t * (head_x - 12), 82 - t * 34 + sin(ph + t * 5) * amp * (1 - t * 0.4)))
	line(pts, INK, 17)
	line(pts, col, 10.5)
	line(pts, shade(col, 1.2), 3)
	var hd: Vector2 = pts[pts.size() - 1]
	ellipse(hd.x + 2, hd.y - 2, 12, 10, -0.3); ink(shade(col, 1.05))
	if pose == "hurt":
		cross(hd.x + 2, hd.y - 7, hd.x + 8, hd.y - 1)
	else:
		ellipse(hd.x + 5, hd.y - 4, 3.2, 3.6); fill(Color.WHITE)
		ellipse(hd.x + 6, hd.y - 4, 1.6, 2.2); fill(INK)
	if pose == "attack":
		line([Vector2(hd.x + 12, hd.y), Vector2(hd.x + 20, hd.y + 1), Vector2(hd.x + 23, hd.y - 2)], Color("#e05a6a"), 2.5)


func draw_flanker(pose: String, i: int) -> void:
	var col := Color("#4fd0e8")
	var ph := i / 4.0 * TAU
	var crouch := 6.0 if pose == "windup" else 0.0
	var lean: float = {attack = 0.35, hurt = -0.3, windup = -0.1}.get(pose, 0.05)
	for s in [0.0, PI]:
		var off := sin(ph + s) * 6.0 if pose == "walk" else ((-8.0 if s > 0 else 8.0) if pose == "attack" else 0.0)
		line([Vector2(46, 72 + crouch), Vector2(46 + off, 90)], INK, 7)
		line([Vector2(46, 72 + crouch), Vector2(46 + off, 90)], shade(col, 0.6), 3)
	save()
	shift(46, 70 + crouch)
	turn(lean)
	ellipse(0, -6, 13, 15); ink(shade(col, 0.8))
	begin(); move_to(-2, -44); quad_to(18, -30, 16, -12); line_to(-16, -12); quad_to(-18, -30, -2, -44); ink(shade(col, 0.55))
	ellipse(2, -22, 10, 8); fill(Color("#0e1a22"))
	if pose != "hurt":
		for ox in [-1, 7]:
			ellipse(ox, -22, 2, 2.4); fill(Color("#dffbff"))
	var da := -2.4 if pose == "windup" else (0.1 if pose == "attack" else 0.6)
	save()
	shift(12, -4)
	turn(da)
	begin(); move_to(0, -2); line_to(20, 0); line_to(0, 3); close(); ink(Color("#efe6d2"), 2.5)
	restore()
	restore()


func draw_circler(pose: String, i: int) -> void:
	var col := Color("#a97cf0")
	var flap := sin(i / 4.0 * TAU) if pose == "walk" else (-1.0 if pose == "attack" else 0.6)
	var cy := 46.0
	for s in [-1.0, 1.0]:
		begin()
		move_to(48 + s * 10, cy - 4)
		line_to(48 + s * 40, cy - 16 - flap * 14)
		line_to(48 + s * 34, cy + 2 - flap * 6)
		line_to(48 + s * 26, cy - 2 - flap * 6)
		line_to(48 + s * 18, cy + 8)
		close()
		ink(shade(col, 0.6), 3)
	begin(); move_to(44, cy + 14); quad_to(40 + flap * 4, cy + 30, 48, cy + 40); quad_to(52, cy + 28, 52, cy + 14); ink(shade(col, 0.8), 3)
	var s := 1.15 if pose == "attack" else (0.92 if pose == "windup" else 1.0)
	ellipse(48, cy, 17 * s, 16 / s); ink(col)
	ellipse(51, cy - 1, 10, 9.5); ink(Color("#fbf5ea"), 2.5)
	if pose == "hurt":
		cross(46, cy - 6, 56, cy + 4)
	else:
		ellipse(53, cy - 1, 5.5, 5.5); fill(Color("#e0443a") if pose == "windup" else Color("#6a3fc0"))
		ellipse(54, cy - 1, 2.4, 3.2); fill(INK)


func _limb(p0: Vector2, p1: Vector2, p2: Vector2, col: Color, w: float = 6.0) -> void:
	line([p0, p1, p2], INK, w + 5)
	line([p0, p1, p2], col, w)


func draw_stalker(pose: String, i: int) -> void:
	var col := Color("#f07ab4")
	var ph := i / 4.0 * TAU
	var sway := sin(ph) * 3.0 if pose == "walk" else 0.0
	var stride := sin(ph) * 12.0 if pose == "walk" else 0.0
	var lc := shade(col, 0.85)
	_limb(Vector2(46, 54), Vector2(44 + stride * 0.5, 72), Vector2(44 + stride, 90), lc)
	_limb(Vector2(50, 54), Vector2(52 - stride * 0.5, 72), Vector2(52 - stride, 90), lc)
	var a1: Array
	var a2: Array
	match pose:
		"windup":
			a1 = [30, 10, 22, -2]; a2 = [70, 12, 80, 0]
		"attack":
			a1 = [66, 30, 88, 36]; a2 = [64, 38, 86, 46]
		"hurt":
			a1 = [36, 36, 30, 50]; a2 = [60, 34, 66, 48]
		_:
			a1 = [36 + sway, 40, 34 + sway, 62]; a2 = [60 + sway, 40, 62 + sway, 62]
	_limb(Vector2(44 + sway, 26), Vector2(a1[0], a1[1]), Vector2(a1[2], a1[3]), lc, 4.5)
	begin(); move_to(40 + sway, 22); line_to(56 + sway, 22); line_to(52, 56); line_to(44, 56); close(); ink(col)
	_limb(Vector2(52 + sway, 26), Vector2(a2[0], a2[1]), Vector2(a2[2], a2[3]), lc, 4.5)
	ellipse(49 + sway, 14, 8, 9); ink(shade(col, 1.1))
	if pose == "hurt":
		cross(48 + sway, 11, 54 + sway, 17, 2)
	else:
		ellipse(52 + sway, 13, 3, 3.4); fill(Color.WHITE)
		ellipse(53 + sway, 13, 1.5, 2); fill(INK)


func draw_brute(pose: String, i: int) -> void:
	var col := Color("#e0443a")
	var ph := i / 4.0 * TAU
	var sway := sin(ph) * 3.0 if pose == "walk" else 0.0
	var stomp := absf(sin(ph)) * 3.0 if pose == "walk" else 0.0
	for leg in [[36, 1.0], [58, -1.0]]:
		round_rect(leg[0] - 7 + (sin(ph) * 3 * leg[1] if pose == "walk" else 0.0), 70, 14, 20 - (stomp if leg[1] > 0 else 0.0), 4)
		ink(shade(col, 0.55))
	var fl: Vector2
	var fr: Vector2
	match pose:
		"windup":
			fl = Vector2(30, 10); fr = Vector2(64, 8)
		"attack":
			fl = Vector2(66, 80); fr = Vector2(84, 72)
		"hurt":
			fl = Vector2(16, 56); fr = Vector2(80, 56)
		_:
			fl = Vector2(14 + sway, 66); fr = Vector2(80 + sway, 66)
	var arm := func(s: Vector2, f: Vector2) -> void:
		line([s, f], INK, 16)
		line([s, f], shade(col, 0.8), 10)
	arm.call(Vector2(24 + sway, 34), fl)
	begin(); move_to(18 + sway, 30); line_to(78 + sway, 30); line_to(66, 74); line_to(30, 74); close(); ink(col)
	begin(); move_to(34 + sway, 42); line_to(62 + sway, 42); line_to(58, 66); line_to(38, 66); close(); ink(shade(col, 0.72), 2.5)
	arm.call(Vector2(72 + sway, 34), fr)
	for f in [fl, fr]:
		ellipse(f.x, f.y, 11, 10); ink(shade(col, 0.9))
	ellipse(48 + sway, 24, 10, 9); ink(shade(col, 1.1))
	begin(); move_to(40 + sway, 18); line_to(32 + sway, 6); line_to(44 + sway, 15); ink(Color("#efe6d2"), 2.5)
	begin(); move_to(56 + sway, 18); line_to(64 + sway, 6); line_to(52 + sway, 15); ink(Color("#efe6d2"), 2.5)
	var eye := Color("#ffe066") if pose == "windup" else Color.WHITE
	for ox in [-4, 4]:
		ellipse(48 + sway + ox, 24, 2.2, 2); fill(eye)


func draw_totem(i: int) -> void:
	var col := Color("#efe6d2")
	begin(); move_to(34, 90); quad_to(30, 50, 40, 22); quad_to(48, 12, 56, 22); quad_to(66, 50, 62, 90); close(); ink(col)
	for yw in [[70, 30], [52, 26], [36, 20]]:
		begin(); move_to(48 - yw[1] / 2.0, yw[0]); quad_to(48, yw[0] + 5, 48 + yw[1] / 2.0, yw[0]); stroke(Color("#b9ab95"), 2.5)
	ellipse(48, 30, 7, 2 if i == 1 else 7); ink(Color("#f5c95a") if i == 1 else Color.WHITE, 2.5)
	if i == 0:
		ellipse(49, 30, 3, 4); fill(INK)


# ---------------- props ----------------

func draw_shrine() -> void:
	begin(); move_to(22, 90); line_to(28, 58); line_to(68, 58); line_to(74, 90); close(); ink(Color("#6d6680"))
	round_rect(18, 50, 60, 12, 3); ink(Color("#8a83a0"))
	line([Vector2(40, 70), Vector2(48, 82), Vector2(56, 70)], Color("#b99cff"), 2.5)
	begin(); move_to(48, 8); line_to(60, 26); line_to(48, 44); line_to(36, 26); close(); ink(Color("#c8a8ff"), 3)
	line([Vector2(48, 12), Vector2(48, 40)], Color(1, 1, 1, 0.5), 2)


func draw_well() -> void:
	for x in [22, 70]:
		round_rect(x, 20, 6, 52, 2); ink(Color("#6b4f3a"), 2.5)
	round_rect(18, 16, 62, 7, 2); ink(Color("#7d5c44"), 2.5)
	line([Vector2(48, 23), Vector2(48, 50)], INK, 2)
	round_rect(42, 48, 12, 10, 2); ink(Color("#8a6440"), 2)
	ellipse(48, 74, 32, 16); ink(Color("#7a7486"))
	ellipse(48, 70, 24, 9); ink(Color("#3f8fb0"), 2.5)
	rect_path(38, 67, 10, 2); fill(Color(1, 1, 1, 0.35))
	begin(); move_to(16, 74); line_to(16, 86); quad_to(48, 100, 80, 86); line_to(80, 74); stroke(INK, LW)


func draw_rack() -> void:
	begin(); move_to(26, 92); line_to(30, 66); line_to(66, 66); line_to(70, 92); close(); ink(Color("#7a6f66"))
	round_rect(22, 58, 52, 11, 3); ink(Color("#958a7e"))
	line([Vector2(34, 78), Vector2(62, 78)], Color("#5d544d"), 2)


func draw_board() -> void:
	for x in [26, 64]:
		round_rect(x, 30, 7, 62, 2); ink(Color("#6b4f3a"), 2.5)
	round_rect(16, 18, 64, 44, 4); ink(Color("#8a6440"))
	for n in [[22, 24, 20, 16, "#efe6d2"], [46, 26, 26, 12, "#f5d98a"], [26, 44, 16, 13, "#cfe6f5"], [48, 42, 22, 15, "#efe6d2"]]:
		rect_path(n[0], n[1], n[2], n[3]); ink(Color(n[4]), 2)
		begin(); move_to(n[0] + 3, n[1] + 5); line_to(n[0] + n[2] - 3, n[1] + 5); move_to(n[0] + 3, n[1] + 9); line_to(n[0] + n[2] - 5, n[1] + 9)
		stroke(Color("#8f8578"), 1.2)


func draw_cache(open: bool) -> void:
	round_rect(22, 56, 52, 34, 4); ink(Color("#8a6440"))
	line([Vector2(22, 70), Vector2(74, 70)], Color("#4a4459"), 3)
	if open:
		begin(); move_to(22, 56); line_to(30, 32); line_to(80, 32); line_to(74, 56); close(); ink(Color("#6b4f3a"))
		ellipse(48, 58, 20, 5); fill(Color("#f5c95a"))
	else:
		begin(); move_to(20, 58); quad_to(48, 36, 76, 58); close(); ink(Color("#9b7350"))
		round_rect(44, 60, 8, 10, 2); ink(Color("#f5c95a"), 2)


# ---------------- trees (neutral greens: the room theme tints them) ----------------

func draw_tree_round() -> void:
	begin(); move_to(42, 94); line_to(44, 58); line_to(52, 58); line_to(55, 94); close(); ink(Color("#6b5140"), 3)
	for b in [[48, 44, 34, 26, "#5f8f64"], [34, 34, 20, 18, "#6fa070"], [62, 32, 20, 18, "#6a9a6c"], [48, 20, 22, 17, "#7fb07c"]]:
		ellipse(b[0], b[1], b[2], b[3]); ink(Color(b[4]), 3)
	ellipse(42, 16, 9, 5); fill(Color(1, 1, 1, 0.12))


func draw_tree_pine() -> void:
	round_rect(44, 76, 8, 18, 2); ink(Color("#5e4636"), 3)
	for t in [[40, 82, 38, "#4f7f5a"], [22, 62, 30, "#5a8c62"], [4, 42, 21, "#679a6c"]]:
		begin(); move_to(48, t[0]); line_to(48 + t[2], t[1]); quad_to(48, t[1] + 6, 48 - t[2], t[1]); close(); ink(Color(t[3]), 3)


func draw_tree_dead() -> void:
	var branch := func(x0: float, y0: float, x1: float, y1: float, w: float) -> void:
		line([Vector2(x0, y0), Vector2(x1, y1)], INK, w + 3.5)
		line([Vector2(x0, y0), Vector2(x1, y1)], Color("#6e5a4c"), w)
	branch.call(48, 94, 46, 40, 9)
	branch.call(46, 58, 24, 34, 5); branch.call(24, 34, 16, 18, 3)
	branch.call(47, 50, 70, 26, 5); branch.call(70, 26, 78, 12, 3)
	branch.call(46, 40, 50, 10, 4)
	for v in [Vector2(20, 26), Vector2(74, 20), Vector2(50, 12), Vector2(32, 40)]:
		ellipse(v.x, v.y, 9, 6); ink(Color("#6b8a66"), 2.5)


func draw_bush(v: int) -> void:
	var blobs := [[32, 74, 18, 14], [58, 72, 20, 16], [46, 62, 18, 14]] if v == 0 else [[28, 78, 15, 12], [48, 70, 19, 15], [68, 78, 15, 12]]
	for b in blobs:
		ellipse(b[0], b[1], b[2], b[3]); ink(Color("#6a9a6c"), 3)
	ellipse(44, 62, 8, 4); fill(Color(1, 1, 1, 0.1))
