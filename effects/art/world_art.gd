class_name WorldArt
extends RefCounted
## Pixel art for the world, generated at boot (Patch 1 "better visuals"): ground tiles
## (grass, dirt paths that blend into the grass, planks, flagstones, rugs, water, cliff faces
## with a grass lip), trees and bushes, torches and braziers.
##
## Ground tiles are 16 x 10 texels drawn over a 32 x 32 cell, so after the camera's 2.5D
## squash their pixels come out square on screen; cliff faces are 16 x 16 texels per segment
## of 32 / ground_k units for the same reason. Tile colours come from the room's theme, so
## every map keeps its own mood. Trees and props are neutral and tinted where they're drawn.
## Real art can replace the sprites by name (see autoload/art.gd).

const TW := 16          ## tile width in texels
const TH := 10          ## ground tile height in texels
const FH := 16          ## face tile height in texels
const COLS := 16        ## tiles per atlas row (each slot is 16 x 16)

static var _cache := {}


# ---------------- helpers ----------------

static func _img(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _h(x: int, y: int, s: int) -> float:
	return RoomMap.hash2(x * 17 + s * 131 + 7, y * 29 + s * 71 + 3)


static func _vivid(c: Color, vk: float, sk: float, vmax := 0.78) -> Color:
	return Color.from_hsv(c.h, clampf(c.s * sk, 0.0, 0.85), clampf(c.v * vk, 0.0, vmax))


static func _shade(c: Color, k: float) -> Color:
	return Color(clampf(c.r * k, 0, 1), clampf(c.g * k, 0, 1), clampf(c.b * k, 0, 1), c.a)


## periodic value noise over a tile (period `p` texels) so tiles repeat without seams
static func _vnoise(x: int, y: int, s: int, cell: int, px: int, py: int) -> float:
	var gx := px / cell
	var gy := py / cell
	var fx := float(x) / cell
	var fy := float(y) / cell
	var ix := floori(fx)
	var iy := floori(fy)
	var tx := fx - ix
	var ty := fy - iy
	var a := _h(posmod(ix, gx), posmod(iy, gy), s)
	var b := _h(posmod(ix + 1, gx), posmod(iy, gy), s)
	var c := _h(posmod(ix, gx), posmod(iy + 1, gy), s)
	var d := _h(posmod(ix + 1, gx), posmod(iy + 1, gy), s)
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


## 1-px outline around every opaque pixel
static func _outline(img: Image, col: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var add := []
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and img.get_pixel(q.x, q.y).a > 0.0:
					add.append(Vector2i(x, y))
					break
	for v in add:
		img.set_pixelv(v, col)


static func _up(img: Image, k: int) -> Image:
	var out := img.duplicate() as Image
	out.resize(img.get_width() * k, img.get_height() * k, Image.INTERPOLATE_NEAREST)
	return out


# ---------------- ground tiles ----------------

## The tile atlas for a theme: {tex: ImageTexture, r: {name: [Rect2, ...]}} (cached per theme)
static func tiles_for(th: ThemeData) -> Dictionary:
	var key := th.resource_path if th.resource_path != "" else str(th.get_instance_id())
	if _cache.has(key):
		return _cache[key]
	var t := _build_tiles(th)
	_cache[key] = t
	return t


static func _build_tiles(th: ThemeData) -> Dictionary:
	var grass := _vivid(th.floor, 2.0, 1.45, 0.62)
	grass = Color.from_hsv(lerpf(grass.h, 0.28, 0.35), maxf(grass.s, 0.38), maxf(grass.v, 0.42))
	var dirt := _vivid(th.path, 1.55, 1.15, 0.62)
	var cliff := _vivid(th.cliff, 1.35, 1.05, 0.5)
	var rock := _vivid(th.wall, 1.55, 0.8, 0.55)
	var water := _vivid(th.water, 1.7, 1.25, 0.6)
	var forest := _shade(grass, 0.62)
	var wood := Color(0.55, 0.36, 0.21)
	var stone := Color(0.44, 0.42, 0.56)
	var rug := Color(0.62, 0.13, 0.15)
	var gold := Color(0.88, 0.68, 0.32)
	var list := []   # [name, Image]
	for v in 8:
		list.append(["grass", _grass(grass, v, v >= 6)])
	for v in 3:
		list.append(["trail", _trail(grass, dirt, v)])
	for v in 3:
		list.append(["forest", _forest(forest, v)])
	for mask in 16:
		for v in 2:
			list.append(["path%d" % mask, _path(dirt, grass, mask, v)])
	for v in 3:
		list.append(["wood", _wood(wood, v)])
	for v in 3:
		list.append(["stone", _flag(stone, v)])
	for mask in 16:
		list.append(["rug%d" % mask, _rug(rug, gold, mask)])
	for v in 3:
		list.append(["water", _water(water, v)])
	list.append(["stairs", _stairs(_shade(rock, 1.15))])
	for v in 2:
		list.append(["rock_top", _rock_top(rock, v)])
	for v in 2:
		list.append(["rock_face", _rock_face(rock, v)])
	list.append(["wood_top", _wood_top(wood)])
	list.append(["wood_face", _wood_face(wood)])
	list.append(["pillar_top", _flag(_shade(stone, 1.2), 7)])
	list.append(["pillar_face", _pillar_face(stone)])
	for v in 2:
		list.append(["cliff_lip", _cliff(cliff, grass, v, true)])
	for v in 3:
		list.append(["cliff", _cliff(cliff, grass, v + 2, false)])
	for v in 2:
		list.append(["wood_lip", _cliff(_shade(wood, 0.8), _shade(wood, 1.1), v, false)])
	var rows := ceili(list.size() / float(COLS))
	var atlas := _img(COLS * TW, rows * FH)
	var regions := {}
	for i in list.size():
		var name: String = list[i][0]
		var img: Image = list[i][1]
		var at := Vector2i((i % COLS) * TW, (i / COLS) * FH)
		atlas.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), at)
		if not regions.has(name):
			regions[name] = []
		regions[name].append(Rect2(at.x, at.y, img.get_width(), img.get_height()))
	return {tex = ImageTexture.create_from_image(atlas), r = regions, grass = grass, dirt = dirt, cliff = cliff,
		water = water, rock = rock, wood = wood, stone = stone, rug = rug, forest = forest}


static func _grass(base: Color, v: int, flowers: bool) -> Image:
	var img := _img(TW, TH)
	var dark := _shade(base, 0.8)
	var deep := _shade(base, 0.66)
	var light := Color.from_hsv(base.h - 0.02, base.s * 0.95, minf(1.0, base.v * 1.18))
	var hi := Color.from_hsv(base.h - 0.04, base.s * 0.8, minf(1.0, base.v * 1.38))
	for y in TH:
		for x in TW:
			var n := _vnoise(x, y, 11, 4, TW, 20) * 0.7 + _vnoise(x, y, 5 + v, 2, TW, TH * 2) * 0.3
			var r := _h(x, y, 40 + v)
			var c := base
			if n > 0.64:
				c = light
			elif n < 0.34:
				c = dark
			if r > 0.95:
				c = hi
			elif r < 0.04:
				c = deep
			img.set_pixel(x, y, c)
	# tufts: little v-shaped blades
	for k in 3 + v % 3:
		var bx := 1 + int(_h(k, v, 3) * (TW - 2))
		var by := 2 + int(_h(v, k, 9) * (TH - 3))
		img.set_pixel(bx, by, hi)
		img.set_pixel(bx - 1, by - 1, light)
		img.set_pixel(bx + 1, by - 1, light)
		img.set_pixel(bx, by + 1, deep)
	if flowers:
		var cols := [Color(0.98, 0.9, 0.55), Color(0.95, 0.5, 0.55), Color(0.85, 0.85, 1.0), Color(1, 1, 1)]
		for k in 3:
			var fx := 2 + int(_h(k, v, 21) * (TW - 4))
			var fy := 2 + int(_h(v, k, 23) * (TH - 4))
			var fc: Color = cols[(k + v) % cols.size()]
			img.set_pixel(fx, fy, Color(1, 0.85, 0.3))
			img.set_pixel(fx - 1, fy, fc)
			img.set_pixel(fx + 1, fy, fc)
			img.set_pixel(fx, fy - 1, fc)
			img.set_pixel(fx, fy + 1, _shade(fc, 0.7))
	return img


## a hidden trail: trodden grass with a few bare patches
static func _trail(grass: Color, dirt: Color, v: int) -> Image:
	var img := _grass(_shade(grass, 0.95), v + 2, false)
	for y in TH:
		for x in TW:
			if _vnoise(x, y, 60 + v, 4, TW, 20) > 0.66:
				img.set_pixel(x, y, _shade(dirt, 0.9 + _h(x, y, v) * 0.15))
	return img


static func _forest(base: Color, v: int) -> Image:
	var img := _img(TW, TH)
	for y in TH:
		for x in TW:
			var n := _vnoise(x, y, 70 + v, 3, 15, TH * 3)
			var c := _shade(base, 0.8 + n * 0.35)
			var r := _h(x, y, 80 + v)
			if r > 0.9:
				c = Color(0.42, 0.3, 0.18)   # leaf litter
			img.set_pixel(x, y, c)
	return img


## dirt; wherever the neighbour on a side isn't path (mask bits N 1, E 2, S 4, W 8) the grass
## creeps in over a ragged edge with a dark rim of shadow
static func _path(dirt: Color, grass: Color, mask: int, v: int) -> Image:
	var img := _img(TW, TH)
	var dark := _shade(dirt, 0.78)
	var light := Color.from_hsv(dirt.h, dirt.s * 0.8, minf(1.0, dirt.v * 1.2))
	for y in TH:
		for x in TW:
			var n := _vnoise(x, y, 90 + v, 4, TW, 20)
			var c := dirt
			if n > 0.66:
				c = light
			elif n < 0.3:
				c = dark
			img.set_pixel(x, y, c)
	# pebbles
	for k in 3:
		var px := 1 + int(_h(k, v, 33) * (TW - 3))
		var py := 1 + int(_h(v, k, 35) * (TH - 2))
		img.set_pixel(px, py, Color.from_hsv(dirt.h, dirt.s * 0.5, minf(1.0, dirt.v * 1.45)))
		img.set_pixel(px + 1, py, Color.from_hsv(dirt.h, dirt.s * 0.5, minf(1.0, dirt.v * 1.3)))
		img.set_pixel(px, py + 1, _shade(dirt, 0.65))
	var g := _grass(grass, v + 1, false)
	for y in TH:
		for x in TW:
			var depth := 0
			var d := 99
			if mask & 1:
				d = mini(d, y)
			if mask & 4:
				d = mini(d, TH - 1 - y)
			if mask & 8:
				d = mini(d, x)
			if mask & 2:
				d = mini(d, TW - 1 - x)
			depth = 1 + int(_h(x + y, v, 50) * 2.4)
			if d < depth:
				img.set_pixel(x, y, g.get_pixel(x, y))
			elif d == depth:
				img.set_pixel(x, y, _shade(dirt, 0.62))
	return img


static func _wood(base: Color, v: int) -> Image:
	var img := _img(TW, TH)
	var plank_h := 5
	for y in TH:
		var row := y / plank_h
		var tint := 0.88 + _h(row, v, 5) * 0.24
		var joint := int(_h(row, v, 6) * TW)
		for x in TW:
			var c := _shade(base, tint + (_h(x, y, v + 7) - 0.5) * 0.08)
			if y % plank_h == plank_h - 1:
				c = _shade(base, 0.55)
			elif y % plank_h == 0:
				c = _shade(base, tint * 1.12)
			if x == joint and y % plank_h != plank_h - 1:
				c = _shade(base, 0.6)
			# grain
			if _h(x / 3, y, v + 9) > 0.86:
				c = _shade(c, 0.86)
			img.set_pixel(x, y, c)
	img.set_pixel(posmod(int(_h(v, 1, 2) * TW) + 2, TW), 2, Color(0.25, 0.2, 0.18))
	return img


## flagstones
static func _flag(base: Color, v: int) -> Image:
	var img := _img(TW, TH)
	for y in TH:
		var row := y / 5
		var off := 4 if row % 2 else 0
		for x in TW:
			var col := (x + off) / 8
			var t := 0.9 + _h(col + row * 3, v, 13) * 0.2
			var c := _shade(base, t + (_h(x, y, v + 14) - 0.5) * 0.1)
			if y % 5 == 4 or (x + off) % 8 == 7:
				c = _shade(base, 0.6)
			elif y % 5 == 0 or (x + off) % 8 == 0:
				c = _shade(base, t * 1.15)
			img.set_pixel(x, y, c)
	if v % 3 == 1:
		# a crack
		var cx := 3 + v
		for k in 3:
			img.set_pixel(cx + k, 2 + k % 2, _shade(base, 0.6))
	return img


static func _rug(red: Color, gold: Color, mask: int) -> Image:
	var img := _img(TW, TH)
	for y in TH:
		for x in TW:
			var c := red
			if (x + y) % 4 == 0 and (x / 4 + y / 3) % 2 == 0:
				c = _shade(red, 1.2)
			var edge := 99
			if mask & 1:
				edge = mini(edge, y)
			if mask & 4:
				edge = mini(edge, TH - 1 - y)
			if mask & 8:
				edge = mini(edge, x)
			if mask & 2:
				edge = mini(edge, TW - 1 - x)
			if edge == 0:
				c = _shade(red, 0.55)
			elif edge == 1:
				c = gold
			elif edge == 2:
				c = _shade(red, 0.8)
			img.set_pixel(x, y, c)
	return img


static func _water(base: Color, v: int) -> Image:
	var img := _img(TW, TH)
	var light := Color.from_hsv(base.h, base.s * 0.6, minf(1.0, base.v * 1.5))
	for y in TH:
		for x in TW:
			var n := _vnoise(x, y, 110 + v, 4, TW, 20)
			img.set_pixel(x, y, _shade(base, 0.85 + n * 0.3))
	for k in 2:
		var wx := int(_h(k, v, 3) * (TW - 5))
		var wy := 2 + k * 4 + v % 2
		for i in 4:
			img.set_pixel(wx + i, wy - (1 if i == 1 or i == 2 else 0), light)
	return img


static func _stairs(base: Color) -> Image:
	var img := _img(TW, TH)
	for y in TH:
		for x in TW:
			var c := _shade(base, 0.95 + (_h(x, y, 3) - 0.5) * 0.12)
			if y < 2:
				c = _shade(base, 1.25)
			elif y >= TH - 2:
				c = _shade(base, 0.65)
			img.set_pixel(x, y, c)
	return img


static func _rock_top(base: Color, v: int) -> Image:
	var img := _img(TW, TH)
	var moss := Color(0.35, 0.5, 0.28)
	for y in TH:
		for x in TW:
			var n := _vnoise(x, y, 120 + v, 4, TW, 20)
			var c := _shade(base, 0.85 + n * 0.35)
			if _vnoise(x, y, 130 + v, 3, 15, 30) > 0.72:
				c = moss.lerp(c, 0.3)
			img.set_pixel(x, y, c)
	for k in 5:
		img.set_pixel(3 + k + v * 4, 4 + (k % 2), _shade(base, 0.62))
	return img


## blocky stone for walls and boulders
static func _rock_face(base: Color, v: int) -> Image:
	var img := _img(TW, FH)
	for y in FH:
		var course := y / 5
		var off := int(_h(course, v, 17) * 6)
		for x in TW:
			var block := (x + off) / 6
			var t := 0.78 + _h(block + course * 7, v, 19) * 0.28
			var c := _shade(base, t)
			if y % 5 == 4 or (x + off) % 6 == 5:
				c = _shade(base, 0.5)
			elif y % 5 == 0:
				c = _shade(base, t * 1.18)
			img.set_pixel(x, y, c)
	return img


static func _wood_top(base: Color) -> Image:
	var img := _img(TW, TH)
	for y in TH:
		for x in TW:
			var c := _shade(base, 1.0 + (_h(x, y, 44) - 0.5) * 0.12)
			if x % 4 == 3:
				c = _shade(base, 0.62)
			if y == 0:
				c = _shade(base, 1.25)
			img.set_pixel(x, y, c)
	return img


static func _wood_face(base: Color) -> Image:
	var img := _img(TW, FH)
	for y in FH:
		for x in TW:
			var c := _shade(base, 0.82 + _h(x / 4, 1, 45) * 0.2 + (_h(x, y, 46) - 0.5) * 0.06)
			if x % 4 == 3:
				c = _shade(base, 0.5)
			if y == 2 or y == 12:
				c = _shade(base, 0.45)   # cross beams
			elif y == 3 or y == 13:
				c = _shade(base, 1.0)
			img.set_pixel(x, y, c)
	return img


static func _pillar_face(base: Color) -> Image:
	var img := _img(TW, FH)
	for y in FH:
		for x in TW:
			var k := 0.75 + 0.35 * sin(float(x) / TW * PI)   # rounded: lit in the middle
			var c := _shade(base, k + (_h(x, y, 48) - 0.5) * 0.08)
			if y % 8 == 7:
				c = _shade(base, 0.55)
			img.set_pixel(x, y, c)
	# a glowing rune
	img.set_pixel(7, 4, Color(0.6, 0.8, 1.0))
	img.set_pixel(8, 4, Color(0.6, 0.8, 1.0))
	img.set_pixel(7, 5, Color(0.45, 0.65, 1.0))
	return img


## earth with stones bedded in it; `lip`: the top has grass hanging over the edge
static func _cliff(base: Color, grass: Color, v: int, lip: bool) -> Image:
	var img := _img(TW, FH)
	for y in FH:
		for x in TW:
			var n := _vnoise(x, y, 140 + v, 4, TW, FH)
			var c := _shade(base, 0.8 + n * 0.32 + (_h(x, y, 141 + v) - 0.5) * 0.08)
			img.set_pixel(x, y, c)
	# erosion streaks
	for k in 2:
		var sx := int(_h(k, v, 142) * TW)
		var sy := int(_h(v, k, 143) * FH)
		for i in 3 + k * 2:
			img.set_pixel(sx, posmod(sy + i, FH), _shade(base, 0.66))
	# stones bedded in the earth, lit on top
	var stone := Color.from_hsv(base.h, base.s * 0.45, minf(1.0, base.v * 1.3))
	for k in 3:
		var cx := 2 + int(_h(k, v, 144) * (TW - 4))
		var cy := 2 + int(_h(v, k, 145) * (FH - 4))
		var rw := 2 + int(_h(k, v, 146) * 2)
		var rh := 1 + int(_h(v, k, 147) * 2)
		for oy in range(-rh, rh + 1):
			for ox in range(-rw, rw + 1):
				if Vector2(ox / float(rw), oy / float(rh)).length() > 1.05:
					continue
				var col := stone
				if oy == -rh:
					col = stone.lightened(0.18)
				elif oy == rh:
					col = _shade(stone, 0.62)
				img.set_pixel(posmod(cx + ox, TW), posmod(cy + oy, FH), col)
	if lip:
		var gd := _shade(grass, 0.72)
		for x in TW:
			var drop := 1 + int(_h(x, v, 67) * 3.2)
			if _h(x, v, 68) > 0.8:
				drop += 2   # a long tuft
			for y in drop:
				img.set_pixel(x, y, grass if y < drop - 1 else gd)
			img.set_pixel(x, drop, _shade(base, 0.55))   # shadow under the overhang
		# a root dangling down the face
		var rx := 3 + int(_h(v, 3, 69) * (TW - 6))
		for y in range(3, 9):
			img.set_pixel(rx + (1 if y > 6 else 0), y, Color(0.3, 0.2, 0.12))
	return img


# ---------------- boulders ----------------

## a mossy boulder sitting on the ground (48 x 48 texels x 2, feet at the bottom)
static func boulder(variant: int) -> Image:
	var img := _img(48, 48)
	var rock := Color(0.5, 0.49, 0.52)
	var moss := [Color(0.24, 0.42, 0.22), Color(0.36, 0.56, 0.28)]
	var cx := 24.0
	var cy := 36.0
	var rx := 13.0 if variant == 0 else 11.0
	var ry := 9.0 if variant == 0 else 10.0
	for y in 48:
		for x in 48:
			var d := Vector2((x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry)
			var wob := 1.0 + 0.1 * sin(atan2(d.y, d.x) * 3.0 + variant * 2.0)
			if d.length() > wob:
				continue
			if y > cy + ry * 0.75:
				continue   # flat where it sits
			var lit := 0.55 - 0.45 * (d.x * 0.5 + d.y * 0.85) + (_h(x, y, 500 + variant) - 0.5) * 0.25
			var c := _shade(rock, 0.55 + clampf(lit, 0.0, 1.0) * 0.7)
			if lit > 0.85 and _vnoise(x, y, 510 + variant, 3, 48, 48) > 0.45:
				c = moss[1] if _h(x, y, 511) > 0.4 else moss[0]
			img.set_pixel(x, y, c)
	# a crack
	for k in 4:
		var px := int(cx) - 3 + k + variant
		var py := int(cy) - 2 + (k % 2)
		if img.get_pixel(px, py).a > 0.0:
			img.set_pixel(px, py, _shade(rock, 0.45))
	_outline(img, Color(0.1, 0.1, 0.12))
	return _up(img, 2)


# ---------------- trees and bushes (neutral greens; the theme tints them) ----------------

const LEAF_OUT := Color(0.07, 0.13, 0.1)
const LEAF := [Color(0.13, 0.28, 0.18), Color(0.2, 0.4, 0.23), Color(0.3, 0.54, 0.28), Color(0.45, 0.68, 0.34), Color(0.66, 0.84, 0.45)]
const BARK := [Color(0.2, 0.13, 0.09), Color(0.33, 0.22, 0.14), Color(0.46, 0.32, 0.2)]


## a canopy of overlapping circles, lit from the top left, dithered between tones
static func _canopy(img: Image, blobs: Array, s: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			# the front-most (lowest) lobe covering this pixel shades it, so every lobe shows
			var front := -1e9
			var n := Vector2.ZERO
			for b in blobs:
				var d := Vector2(x + 0.5 - b[0], y + 0.5 - b[1]) / float(b[2])
				if d.length() < 1.0 and b[1] > front:
					front = b[1]
					n = d
			if front < -1e8:
				continue
			var lit := 0.52 - 0.42 * (n.x * 0.55 + n.y * 0.85)
			lit += (_h(x, y, s) - 0.5) * 0.28 + (_vnoise(x, y, s + 3, 3, 48, 48) - 0.5) * 0.3
			var k := clampi(int(lit * 5.0), 0, 4)
			img.set_pixel(x, y, LEAF[k])


static func _trunk(img: Image, x0: int, y0: int, y1: int, tw: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x0 + tw):
			var k := 2 if x == x0 else (0 if x == x0 + tw - 1 else 1)
			img.set_pixel(x, y, BARK[k])
	img.set_pixel(x0 - 1, y1, BARK[1])
	img.set_pixel(x0 + tw, y1, BARK[0])


static func tree_round(variant: int) -> Image:
	var img := _img(48, 48)
	_trunk(img, 22, 30, 45, 4)
	var blobs := [[24, 22, 13], [15, 25, 9], [33, 25, 9], [24, 12, 10], [17, 15, 7], [31, 15, 7]]
	if variant == 1:
		blobs = [[24, 20, 14], [13, 23, 8], [35, 22, 8], [22, 9, 9], [30, 12, 8]]
	_canopy(img, blobs, 200 + variant)
	_outline(img, LEAF_OUT)
	return _up(img, 2)


static func tree_pine() -> Image:
	var img := _img(48, 48)
	_trunk(img, 22, 36, 45, 4)
	var tiers := [[4, 16, 8], [12, 25, 12], [21, 36, 15]]   # [top, bottom, half-width]
	for t in tiers:
		for y in range(t[0], t[1] + 1):
			var hw := int(float(y - t[0] + 2) / (t[1] - t[0] + 2) * t[2])
			for x in range(24 - hw, 24 + hw):
				var side := float(x - 24) / maxf(1.0, hw)
				var lit: float = 0.62 - side * 0.35 - float(y - t[0]) / (t[1] - t[0] + 1) * 0.3 + (_h(x, y, 300) - 0.5) * 0.3
				img.set_pixel(x, y, LEAF[clampi(int(lit * 5.0), 0, 4)])
		# ragged bottom edge of each tier
		for x in range(24 - t[2], 24 + t[2]):
			if _h(x, t[1], 301) > 0.5:
				img.set_pixel(x, t[1] + 1, LEAF[0])
	_outline(img, LEAF_OUT)
	return _up(img, 2)


static func bush(variant: int) -> Image:
	var img := _img(48, 48)
	var blobs := [[16, 36, 9], [31, 35, 10], [24, 29, 9]] if variant == 0 else [[13, 38, 8], [24, 33, 10], [35, 38, 8]]
	_canopy(img, blobs, 400 + variant)
	if variant == 1:
		for k in 5:
			var bx := 12 + int(_h(k, 1, 402) * 24)
			var by := 30 + int(_h(1, k, 403) * 9)
			if img.get_pixel(bx, by).a > 0.0:
				img.set_pixel(bx, by, Color(0.85, 0.2, 0.25))
				img.set_pixel(bx + 1, by, Color(1.0, 0.45, 0.45))
	_outline(img, LEAF_OUT)
	return _up(img, 2)


# ---------------- torches and braziers ----------------

## a torch on a post, flame frame f (0..2); 32 x 32 texels, feet at the bottom
static func torch(f: int) -> Image:
	var img := _img(32, 32)
	for y in range(13, 31):
		img.set_pixel(15, y, BARK[2])
		img.set_pixel(16, y, BARK[1])
	img.set_pixel(14, 30, BARK[1])
	img.set_pixel(17, 30, BARK[0])
	# iron cup
	for x in range(13, 19):
		img.set_pixel(x, 12, Color(0.28, 0.26, 0.3))
		img.set_pixel(x, 11, Color(0.4, 0.38, 0.42))
	_flame(img, 16, 10, f, [Color(1, 0.35, 0.12), Color(1, 0.62, 0.2), Color(1, 0.88, 0.45), Color(1, 1, 0.85)])
	_outline(img, Color(0.08, 0.06, 0.08))
	return _up(img, 3)


## a stone brazier with a blue spirit flame
static func brazier(f: int) -> Image:
	var img := _img(32, 32)
	var st := Color(0.42, 0.4, 0.55)
	for y in range(22, 31):
		for x in range(13, 19):
			img.set_pixel(x, y, _shade(st, 1.1 if x == 13 else (0.75 if x == 18 else 0.95)))
	for x in range(10, 22):
		img.set_pixel(x, 30, _shade(st, 0.8))
		img.set_pixel(x, 31, _shade(st, 0.6))
	for y in range(17, 22):
		var hw := 7 - (y - 17) / 2
		for x in range(16 - hw, 16 + hw):
			img.set_pixel(x, y, _shade(st, 1.2 if y == 17 else 0.9))
	_flame(img, 16, 16, f, [Color(0.25, 0.35, 0.95), Color(0.35, 0.6, 1.0), Color(0.6, 0.85, 1.0), Color(0.92, 0.98, 1.0)])
	_outline(img, Color(0.08, 0.06, 0.12))
	return _up(img, 3)


static func _flame(img: Image, cx: int, base_y: int, f: int, cols: Array) -> void:
	var hgt := 7 + f % 2
	for y in hgt:
		var t := float(y) / hgt
		var hw := int((1.0 - t) * 3.2 + 0.5)
		var sway := int(sin(f * 2.1 + y * 0.9) * 0.9)
		for x in range(-hw, hw + 1):
			var inner := absf(x) / maxf(1.0, hw)
			var k := clampi(int((1.0 - inner) * 2.5 + (1.0 - t) * 1.2), 0, 3)
			img.set_pixel(cx + x + sway, base_y - y, cols[k])
