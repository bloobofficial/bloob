class_name PixelArt
extends RefCounted
## Bloob and his weapons as pixel art (prototype: render/pixelart.ts, the v0.9 concept-sheet
## style): chunky pixels, a 1-px ink outline, a flat cream body, dot eyes, little cat ears.
## Every frame is generated at native resolution from a small pose description and scaled
## up with no smoothing (art.gd). Replace with real sprite sheets later by keeping the frame
## names ("bloob.run.3", "weapon.sword", ...).

const PAL := [
	Color8(0, 0, 0, 0),
	Color8(20, 15, 22), Color8(246, 238, 226), Color8(224, 211, 196), Color8(199, 184, 166), Color8(255, 251, 245),
	Color8(124, 43, 56), Color8(126, 116, 136), Color8(206, 194, 178), Color8(232, 32, 60), Color8(255, 214, 214),
	Color8(245, 201, 90), Color8(185, 138, 82), Color8(255, 243, 190), Color8(244, 240, 238), Color8(205, 197, 203),
	Color8(139, 128, 137), Color8(120, 55, 61), Color8(168, 133, 138), Color8(72, 34, 40), Color8(138, 100, 64),
	Color8(92, 64, 40), Color8(241, 234, 216), Color8(200, 188, 160), Color8(210, 64, 63), Color8(143, 136, 166),
	Color8(90, 84, 112), Color8(180, 174, 200), Color8(199, 155, 255), Color8(90, 58, 102), Color8(255, 143, 200),
	Color8(58, 36, 68), Color8(242, 184, 176),
]
enum { NONE, OUT, BODY, SHADE, DEEP, HI, MOUTH, LINE, DUST, SPARK, SPARK2, GOLD, GOLD_DK, GLINT,
	STEEL_HI, STEEL, STEEL_DK, HILT, HILT_HI, HILT_DK, WOOD, WOOD_DK, BONE, BONE_DK, RIBBON,
	STONE, STONE_DK, STONE_HI, RUNE, FANG, FANG_HI, FANG_DK, PAD }

const BLOOB_PX := 32
const CX := 16


## a palette-index grid
class Pix:
	var w: int
	var h: int
	var d: PackedByteArray
	var clip_edge := false

	func _init(ww: int, hh: int) -> void:
		w = ww
		h = hh
		d = PackedByteArray()
		d.resize(w * h)

	func get_c(x: int, y: int) -> int:
		return d[y * w + x] if x >= 0 and y >= 0 and x < w and y < h else 0

	func set_c(x: int, y: int, c: int) -> void:
		if x >= 0 and y >= 0 and x < w and y < h:
			d[y * w + x] = c

	## only where something is already drawn
	func over(x: int, y: int, c: int) -> void:
		if get_c(x, y):
			set_c(x, y, c)

	## only where nothing is drawn yet (kept off the frame's edge when clip_edge is on)
	func under(x: int, y: int, c: int) -> void:
		if clip_edge and (x < 1 or y < 1 or x >= w - 1 or y >= h - 1):
			return
		if not get_c(x, y):
			set_c(x, y, c)

	func rect(x: int, y: int, ww: int, hh: int, c: int) -> void:
		for j in hh:
			for i in ww:
				set_c(x + i, y + j, c)

	## 1-px ink line around everything drawn so far (4-neighbour)
	func outline(c: int = 1) -> void:
		var add := []
		for y in h:
			for x in w:
				if get_c(x, y):
					continue
				if get_c(x - 1, y) or get_c(x + 1, y) or get_c(x, y - 1) or get_c(x, y + 1):
					add.append(Vector2i(x, y))
		for v in add:
			set_c(v.x, v.y, c)

	func to_image(scale: int) -> Image:
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var c := d[y * w + x]
				if c:
					img.set_pixel(x, y, PAL[c])
		img.resize(w * scale, h * scale, Image.INTERPOLATE_NEAREST)
		return img


static func _r(v: float) -> int:
	return int(floor(v + 0.5))


## Build one Bloob frame from a pose (prototype: bloobPix).
static func bloob(p: Dictionary) -> Pix:
	var g := Pix.new(BLOOB_PX, BLOOB_PX)
	var lift := _r(p.get("lift", 0))
	var B := 28 - lift
	var w: float = p.w
	var h: float = p.h
	var lean: float = p.get("lean", 0.0)
	var hw := w / 2.0
	var col_x := func(ny: float) -> float: return CX + lean * (ny - 0.25)
	var body := Pix.new(BLOOB_PX, BLOOB_PX)   # mask (a reference type, so lambdas can write it)
	# body: a loaf (flat bottom, round top) sheared by the lean
	for y in BLOOB_PX:
		var ny := (B + 1 - (y + 0.5)) / h
		if ny < 0.0 or ny > 1.0:
			continue
		var dy := ny * 2.0 - 1.0
		var ey := 3.2 if dy < 0.0 else 2.3
		var cxy: float = col_x.call(ny)
		for x in BLOOB_PX:
			var dx := (x + 0.5 - cxy) / hw
			if pow(absf(dx), 2.5) + pow(absf(dy), ey) <= 1.0:
				body.set_c(x, y, 1)
	var is_body := func(x: int, y: int) -> bool:
		return body.get_c(x, y) == 1
	var top_at := func(x: int) -> int:
		for y in BLOOB_PX:
			if is_body.call(x, y):
				return y
		return int(B - h)
	# ears: small rounded triangles, back one and front one
	var ear_h := _r(p.get("ears", 3))
	var tilt: float = p.get("earTilt", 0.0)
	var top_cx: float = col_x.call(0.92)
	for u in [-0.5, 0.46]:
		var x0 := _r(top_cx + u * hw)
		var ty: int = top_at.call(x0)
		for r in range(-1, ear_h + 1):
			var k := maxf(0, r) / maxf(1, ear_h)
			var half := 2.9 * (1.0 - k) + 0.75
			var c := x0 + 0.5 + tilt * k
			for x in range(floori(c - half), ceili(c + half) + 1):
				if absf(x + 0.5 - c) <= half:
					var yy := ty - r
					body.set_c(x, yy, 1)
	# feet: stubby bumps under the body
	var feet: String = p.get("feet", "stand")
	var foot := func(u: float, dyy: int) -> void:
		var x0 := _r(col_x.call(0.0) + u * hw) - 1
		for i in 3:
			body.set_c(x0 + i, B + dyy, 1)
	match feet:
		"stand":
			foot.call(-0.5, 1); foot.call(0.38, 1)
		"a":
			foot.call(-0.62, 1); foot.call(0.55, 1)
		"b":
			foot.call(-0.2, 1); foot.call(0.12, 0)
		"c":
			foot.call(-0.35, 0); foot.call(0.3, 1)
		"wide":
			foot.call(-0.78, 1); foot.call(0.7, 1)
	var cy := B + 1 - h * 0.5
	var paw_at := func(pp: Array) -> Vector2:
		return Vector2(col_x.call(0.5) + cos(pp[0]) * pp[1], cy + sin(pp[0]) * pp[1])
	# fill + shading
	for y in BLOOB_PX:
		for x in BLOOB_PX:
			if not is_body.call(x, y):
				continue
			var ny := (B + 1 - (y + 0.5)) / h
			var c := BODY
			var front: bool = x + 0.5 > col_x.call(ny)
			if not is_body.call(x, y + 1):
				c = SHADE
			elif not is_body.call(x, y + 2) and front and ny < 0.3:
				c = SHADE
			elif not is_body.call(x + 1, y) and ny < 0.55 and ny > 0.05:
				c = SHADE
			if not is_body.call(x, y + 1) and y >= B:
				c = DEEP
			g.set_c(x, y, c)
	g.outline()
	# paws: little limbs with their own outline; the front one over the body, the back one behind
	var draw_paw := func(pp, front: bool) -> void:
		if pp == null:
			return
		var pa: Vector2 = paw_at.call(pp)
		var q := Pix.new(BLOOB_PX, BLOOB_PX)
		for y in range(floori(pa.y - 2), ceili(pa.y + 2) + 1):
			for x in range(floori(pa.x - 2), ceili(pa.x + 2) + 1):
				var dx := (x + 0.5 - pa.x) / 1.75
				var dy := (y + 0.5 - pa.y) / 1.55
				if dx * dx + dy * dy <= 1.0:
					q.set_c(x, y, SHADE if dy > 0.45 else BODY)
		q.outline()
		for i in q.d.size():
			if q.d[i] and (front or not g.d[i]):
				g.d[i] = q.d[i]
	draw_paw.call(p.get("paw2"), false)
	# face
	var eyes: String = p.get("eyes", "open")
	var look: float = p.get("look", 0.0)
	var er := _r(B + 1 - h * 0.64)
	var ecx: float = col_x.call(0.64)
	var fx := _r(ecx + hw * 0.62 + look)
	var bx := _r(ecx + hw * 0.08 + look)
	if eyes == "front":
		fx = _r(ecx + 3 + look)
		bx = _r(ecx - 3 + look)
	match eyes:
		"open", "front":
			g.over(bx, er, OUT); g.over(bx, er + 1, OUT); g.over(fx, er, OUT); g.over(fx, er + 1, OUT)
		"up":
			g.over(bx, er - 1, OUT); g.over(bx, er, OUT); g.over(fx, er - 1, OUT); g.over(fx, er, OUT)
		"blink", "closed":
			g.over(bx - 1, er + 1, OUT); g.over(bx, er + 1, OUT); g.over(fx, er + 1, OUT); g.over(fx + 1, er + 1, OUT)
		"squint":
			g.over(bx - 1, er + 1, OUT); g.over(bx, er + 1, OUT); g.over(fx, er + 1, OUT); g.over(fx + 1, er + 1, OUT)
			g.over(bx - 1, er, OUT); g.over(fx + 1, er, OUT)
		"fierce":
			g.over(bx - 1, er, OUT); g.over(bx, er + 1, OUT); g.over(fx + 1, er, OUT); g.over(fx, er + 1, OUT)
		"hurt":
			g.over(bx - 1, er - 1, OUT); g.over(bx, er, OUT); g.over(bx - 1, er + 1, OUT)
			g.over(fx + 1, er - 1, OUT); g.over(fx, er, OUT); g.over(fx + 1, er + 1, OUT)
	var mouth: String = p.get("mouth", "none")
	var mr := er + 4
	var mx := _r(ecx + look) if eyes == "front" else fx - 1
	match mouth:
		"o", "yell":
			g.over(mx, mr, OUT); g.over(mx + 1, mr, OUT); g.over(mx, mr + 1, MOUTH); g.over(mx + 1, mr + 1, MOUTH)
			g.over(mx, mr + 2, OUT); g.over(mx + 1, mr + 2, OUT)
		"shut":
			g.over(mx, mr + 1, OUT); g.over(mx + 1, mr + 1, OUT)
		"smile":
			g.over(mx - 1, mr, OUT); g.over(mx, mr + 1, OUT); g.over(mx + 1, mr + 1, OUT); g.over(mx + 2, mr, OUT)
	draw_paw.call(p.get("paw"), true)
	# extras (no outline), kept off the frame's edge
	g.clip_edge = true
	var left := _r(col_x.call(0.5) - hw)
	var speed: int = p.get("speed", 0)
	for k in speed:
		var y := _r(B + 1 - h * (0.2 + k * 0.3))
		var length := 4 - (k % 2)
		for i in length:
			g.under(left - 2 - i - (k % 2), y, LINE)
	if p.get("fall", false):
		for dx in [-5, 0, 5]:
			for i in 4 - absi(dx) / 5:
				g.under(_r(col_x.call(1.0)) + dx, int(B - h - ear_h - 2 - i), LINE)
	if p.get("dust", false):
		var rgt := _r(col_x.call(0.0) + hw)
		for v in [Vector2i(left - 2, B + 1), Vector2i(left - 3, B), Vector2i(left - 1, B - 1), Vector2i(rgt + 2, B + 1), Vector2i(rgt + 3, B), Vector2i(rgt + 1, B - 1)]:
			g.under(v.x, v.y, DUST)
	if p.get("sparkle", false):
		for v in [Vector2i(left - 1, int(B - h + 1)), Vector2i(_r(col_x.call(1.0) + hw) + 1, int(B - h + 3)), Vector2i(_r(col_x.call(1.0)) + 1, int(B - h - ear_h - 3))]:
			g.under(v.x, v.y, GLINT); g.under(v.x - 1, v.y, GOLD); g.under(v.x + 1, v.y, GOLD); g.under(v.x, v.y - 1, GOLD); g.under(v.x, v.y + 1, GOLD)
	if p.get("flask", false) and p.get("paw") != null:
		var fp: Vector2 = paw_at.call(p.paw)
		var px := _r(fp.x)
		var py := _r(fp.y)
		var f := Pix.new(BLOOB_PX, BLOOB_PX)
		f.rect(px - 1, py - 4, 3, 4, GOLD)
		f.set_c(px + 1, py - 3, GLINT)
		f.rect(px, py - 5, 1, 1, GOLD_DK)
		f.outline()
		for i in f.d.size():
			if f.d[i]:
				g.d[i] = f.d[i]
	var sparks: int = p.get("sparks", 0)
	if sparks > 0:
		var right := _r(col_x.call(0.5) + hw)
		var spots := [[right + 3, B - 6, SPARK], [right + 5, B - 3, SPARK2], [right + 2, B - 10, SPARK], [right + 6, B - 8, SPARK], [right + 4, B - 1, SPARK], [right + 7, B - 5, SPARK2]]
		for k in mini(sparks, spots.size()):
			g.under(spots[k][0], spots[k][1], spots[k][2])
	if p.get("sweat", false):
		g.under(left + 1, int(B - h - 1), SPARK2)
		g.under(left, int(B - h), SPARK2)
	return g


## Every Bloob clip (prototype: BLOOB_POSES). Slash 1 = 5, Slash 2 = 5, Big Slash = 6, Recovery = 4.
static func bloob_poses() -> Dictionary:
	return {
		idle = [
			{w = 22, h = 16, eyes = "open", mouth = "o"},
			{w = 22, h = 16, lift = 0, eyes = "open", mouth = "o", ears = 3, earTilt = -0.4},
			{w = 23, h = 15, eyes = "open", mouth = "o"},
			{w = 22, h = 16, eyes = "open", mouth = "o", earTilt = 0.4},
		],
		blink = [{w = 22, h = 16, eyes = "blink", mouth = "o"}],
		run = [
			{w = 24, h = 14, lean = 1, feet = "a", eyes = "open", mouth = "shut", earTilt = -1},
			{w = 21, h = 16, lean = 2, lift = 1, feet = "b", eyes = "open", mouth = "shut", earTilt = -1.2},
			{w = 20, h = 17, lean = 2, lift = 2, feet = "tuck", eyes = "open", mouth = "shut", earTilt = -1.5, speed = 2},
			{w = 21, h = 16, lean = 2, lift = 1, feet = "c", eyes = "open", mouth = "shut", earTilt = -1.2},
			{w = 23, h = 15, lean = 1, feet = "a", eyes = "open", mouth = "shut", earTilt = -1},
			{w = 24, h = 14, lean = 1, feet = "wide", eyes = "open", mouth = "shut", earTilt = -0.8, dust = true},
		],
		slash1 = [
			{w = 22, h = 16, lean = -1, eyes = "fierce", mouth = "shut", paw = [PI - 0.6, 11]},
			{w = 24, h = 14, lean = -2, eyes = "fierce", mouth = "shut", paw = [PI - 0.3, 12], feet = "wide", earTilt = -1},
			{w = 24, h = 15, lean = 3, eyes = "fierce", mouth = "yell", paw = [0.05, 11.5], feet = "a", speed = 3, earTilt = -1.5},
			{w = 23, h = 15, lean = 2, eyes = "fierce", mouth = "shut", paw = [0.4, 12], feet = "a", earTilt = -1},
			{w = 22, h = 16, lean = 1, eyes = "open", mouth = "shut", paw = [0.8, 10]},
		],
		slash2 = [
			{w = 22, h = 16, lean = 1, eyes = "fierce", mouth = "shut", paw = [-0.7, 11]},
			{w = 20, h = 18, lean = 0, eyes = "front", mouth = "shut", paw = [-0.9, 12], earTilt = 0.5},
			{w = 24, h = 15, lean = -1, eyes = "front", mouth = "yell", paw = [PI - 0.45, 12], feet = "wide", speed = 2},
			{w = 23, h = 15, lean = -1, eyes = "front", mouth = "shut", paw = [PI - 0.25, 11], feet = "wide"},
			{w = 22, h = 16, eyes = "open", mouth = "shut", paw = [2.2, 9]},
		],
		bigslash = [
			{w = 21, h = 17, eyes = "fierce", mouth = "shut", paw = [-0.5, 12], earTilt = 0.5},
			{w = 19, h = 19, lift = 1, eyes = "fierce", mouth = "shut", paw = [-0.75, 12], feet = "tuck", earTilt = 0.8},
			{w = 18, h = 20, lift = 2, eyes = "fierce", mouth = "yell", paw = [-0.95, 12], feet = "tuck", ears = 4},
			{w = 27, h = 12, eyes = "squint", mouth = "yell", paw = [0.2, 12.5], paw2 = [0.45, 11], feet = "wide", dust = true, earTilt = -1.5},
			{w = 26, h = 13, lean = 1, eyes = "fierce", mouth = "shut", paw = [0.2, 12.5], paw2 = [0.45, 11], feet = "wide", dust = true, earTilt = -1},
			{w = 25, h = 14, lean = 1, eyes = "fierce", mouth = "shut", paw = [0.35, 13], feet = "wide", sparks = 4},
		],
		recovery = [
			{w = 24, h = 15, lean = 1, eyes = "open", mouth = "shut", paw = [0.6, 10], sparks = 6},
			{w = 23, h = 15, eyes = "open", mouth = "shut", sparks = 4},
			{w = 22, h = 16, eyes = "blink", mouth = "shut", sparks = 2},
			{w = 22, h = 16, eyes = "open", mouth = "o"},
		],
		dodge = [
			{w = 26, h = 12, lean = 3, eyes = "squint", mouth = "shut", feet = "b", speed = 3, earTilt = -2},
			{w = 24, h = 14, lean = 3, eyes = "open", mouth = "shut", feet = "a", speed = 2, earTilt = -1.5},
		],
		hurt = [{w = 24, h = 15, lean = -3, eyes = "hurt", mouth = "yell", sweat = true, earTilt = -1}],
		jump = [
			{w = 18, h = 20, lift = 0, eyes = "up", mouth = "o", feet = "tuck", paw = [-0.9, 10], ears = 4, earTilt = -0.5},
			{w = 22, h = 17, eyes = "open", mouth = "o", feet = "tuck", paw = [-0.2, 12]},
			{w = 20, h = 18, eyes = "open", mouth = "yell", feet = "stand", paw = [-0.7, 13], paw2 = [-2.45, 13], ears = 4, earTilt = 1},
		],
		airslash = [
			{w = 22, h = 16, lean = -1, eyes = "fierce", mouth = "shut", feet = "tuck", paw = [PI - 0.7, 11]},
			{w = 23, h = 15, lean = 3, eyes = "fierce", mouth = "yell", feet = "tuck", paw = [0, 11.5], speed = 2},
			{w = 22, h = 16, lean = 1, eyes = "open", mouth = "shut", feet = "tuck", paw = [0.6, 11]},
		],
		dive = [{w = 17, h = 21, eyes = "fierce", mouth = "yell", feet = "tuck", paw = [1.25, 9.5], paw2 = [1.9, 9.5], fall = true, ears = 4, earTilt = 1}],
		land = [{w = 28, h = 11, eyes = "squint", mouth = "shut", feet = "wide", paw = [1.0, 13], paw2 = [2.1, 13], dust = true, earTilt = -2}],
		cast = [
			{w = 20, h = 18, eyes = "fierce", mouth = "shut", paw = [-0.45, 13], paw2 = [-2.7, 13], sparkle = true, earTilt = 0.5},
			{w = 23, h = 16, eyes = "squint", mouth = "yell", paw = [-0.6, 12], paw2 = [-0.2, 12], sparkle = true},
		],
		drink = [
			{w = 22, h = 16, lean = -1, eyes = "open", mouth = "o", paw = [-0.25, 12], flask = true},
			{w = 22, h = 16, lean = -2, eyes = "closed", mouth = "shut", paw = [-0.5, 11], flask = true},
		],
	}


# ---------------- weapons (upright: blade up, grip near the bottom) ----------------

static func _steel_blade(g: Pix, x: int, y0: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		g.set_c(x - 2, y, STEEL_HI); g.set_c(x - 1, y, STEEL_HI); g.set_c(x, y, STEEL); g.set_c(x + 1, y, STEEL_DK)
	g.set_c(x - 2, y0, 0); g.set_c(x + 1, y0, 0)
	g.set_c(x - 1, y0 - 1, STEEL_HI); g.set_c(x, y0 - 1, STEEL)
	g.set_c(x - 1, y0 - 2, STEEL_HI)


static func sword() -> Pix:
	var g := Pix.new(32, 32)
	_steel_blade(g, 16, 4, 21)
	for y in range(7, 20, 4):
		g.set_c(16, y, STEEL_HI)
	for x in range(10, 22):
		g.set_c(x, 22, HILT)
	for x in range(11, 21):
		g.set_c(x, 23, HILT_DK)
	g.set_c(10, 22, HILT_HI); g.set_c(21, 22, HILT_HI); g.set_c(14, 22, HILT_HI); g.set_c(9, 21, HILT); g.set_c(22, 21, HILT)
	for y in range(24, 28):
		g.set_c(15, y, HILT_HI if y & 1 else HILT)
		g.set_c(16, y, HILT if y & 1 else HILT_DK)
	g.rect(14, 28, 4, 2, HILT); g.set_c(14, 28, HILT_HI); g.set_c(17, 29, HILT_DK)
	g.outline()
	return g


static func spear() -> Pix:
	var g := Pix.new(48, 48)
	for y in range(14, 47):
		g.set_c(24, y, WOOD_DK if y % 6 == 0 else WOOD)
		g.set_c(23, y, WOOD_DK if y % 6 == 3 else WOOD)
	g.rect(22, 13, 4, 2, BONE_DK); g.set_c(22, 13, BONE)
	for v in [Vector2i(26, 14), Vector2i(27, 15), Vector2i(27, 16), Vector2i(28, 17), Vector2i(28, 18), Vector2i(27, 19), Vector2i(26, 15), Vector2i(28, 16)]:
		g.set_c(v.x, v.y, RIBBON)
	var rows := [1, 2, 2, 3, 3, 4, 4, 4, 3, 2]
	for k in rows.size():
		var y := 2 + k
		for x in range(24 - rows[k], 24 + rows[k]):
			g.set_c(x, y, BONE if x < 24 else BONE_DK)
	g.set_c(23, 1, BONE)
	g.set_c(23, 4, STEEL_HI); g.set_c(23, 6, STEEL_HI)
	g.outline()
	return g


static func hammer() -> Pix:
	var g := Pix.new(32, 32)
	for y in range(12, 28):
		g.set_c(15, y, WOOD_DK)
		g.set_c(16, y, WOOD_DK if y % 4 == 0 else WOOD)
	g.rect(14, 26, 4, 3, WOOD); g.set_c(14, 26, WOOD_DK)
	g.rect(6, 2, 20, 10, STONE)
	g.rect(6, 2, 20, 1, STONE_HI); g.rect(6, 2, 1, 10, STONE_HI)
	g.rect(6, 4, 20, 1, STONE_DK); g.rect(6, 10, 20, 1, STONE_DK)
	g.set_c(6, 2, 0); g.set_c(25, 2, 0)
	for v in [Vector2i(13, 6), Vector2i(14, 7), Vector2i(15, 8), Vector2i(16, 8), Vector2i(17, 7), Vector2i(18, 6)]:
		g.set_c(v.x, v.y, RUNE)
	g.outline()
	return g


static func fang() -> Pix:
	var g := Pix.new(24, 24)
	var cols := [[12, 1], [12, 2], [11, 3], [11, 4], [11, 5], [10, 6], [10, 7], [10, 8], [10, 9], [10, 10], [10, 11], [10, 12], [10, 13], [10, 14], [10, 15]]
	for k in cols.size():
		var wide := 1 if k < 2 else (2 if k < 5 else 3)
		for i in wide:
			g.set_c(cols[k][0] + i, cols[k][1], FANG_HI if i == wide - 1 and wide > 1 else FANG)
	g.rect(8, 16, 7, 1, FANG_DK)
	for y in range(17, 21):
		g.set_c(11, y, FANG)
		g.set_c(12, y, FANG_DK if y & 1 else FANG)
	g.outline()
	return g


static func paw() -> Pix:
	var g := Pix.new(32, 32)
	var blob := func(cx: float, cy: float, rx: float, ry: float, c: int) -> void:
		for y in range(floori(cy - ry), ceili(cy + ry) + 1):
			for x in range(floori(cx - rx), ceili(cx + rx) + 1):
				var dx := (x + 0.5 - cx) / rx
				var dy := (y + 0.5 - cy) / ry
				if dx * dx + dy * dy <= 1.0:
					g.set_c(x, y, c)
	blob.call(16.0, 20.0, 7.5, 6.5, BODY)
	for v in [Vector2(9.5, 12), Vector2(16, 9.5), Vector2(22.5, 12)]:
		blob.call(v.x, v.y, 3.0, 3.2, BODY)
	blob.call(16.0, 21.0, 3.5, 2.6, PAD)
	for v in [Vector2(9.5, 12.5), Vector2(16, 10), Vector2(22.5, 12.5)]:
		blob.call(v.x, v.y, 1.3, 1.3, PAD)
	for y in range(23, 27):
		for x in range(10, 23):
			if g.get_c(x, y) == BODY and not g.get_c(x, y + 1):
				g.set_c(x, y, SHADE)
	g.outline()
	for v in [Vector2i(8, 7), Vector2i(16, 4), Vector2i(24, 7)]:
		g.set_c(v.x, v.y, OUT)
		g.set_c(v.x, v.y + 1, OUT)
	return g


static func staff() -> Pix:
	var g := Pix.new(48, 48)
	for y in range(12, 46):
		g.set_c(24, y, WOOD_DK if y % 7 == 0 else WOOD)
		g.set_c(23, y, WOOD_DK if y % 7 == 4 else WOOD)
	# a gnarled crook cradling a wisp crystal
	for v in [Vector2i(21, 10), Vector2i(20, 9), Vector2i(20, 8), Vector2i(21, 7), Vector2i(26, 10), Vector2i(27, 9), Vector2i(27, 8), Vector2i(26, 7)]:
		g.set_c(v.x, v.y, WOOD_DK)
	g.rect(22, 11, 4, 1, WOOD_DK)
	var rows := [1, 2, 3, 3, 2, 1]
	for k in rows.size():
		for x in range(24 - rows[k], 24 + rows[k]):
			g.set_c(x, 3 + k, RUNE if x < 24 else STONE_HI)
	g.set_c(23, 5, GLINT); g.set_c(22, 6, SPARK2)
	g.rect(22, 26, 4, 2, BONE_DK); g.set_c(22, 26, BONE)
	g.outline()
	return g
