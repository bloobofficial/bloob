class_name Draw25
extends RefCounted
## Drawing helpers for the 2.5D view (see autoload/view.gd).
## "Ground" shapes lie on the ground plane: drawn as-is, the camera squashes them.
## "Upright" shapes stand facing the camera (glows, sparks, billboards): counter-scaled so
## they stay round.


static var _disc: Texture2D


## a soft-edged disc, drawn as one textured quad (draw_circle is costly in bulk)
static func disc() -> Texture2D:
	if _disc == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var c := (n - 1) / 2.0
		for y in n:
			for x in n:
				var d := Vector2(x - c, y - c).length()
				img.set_pixel(x, y, Color(1, 1, 1, clampf(c - d + 0.5, 0.0, 1.0)))
		_disc = ImageTexture.create_from_image(img)
	return _disc


## a filled circle of radius r at `at` in the current transform
static func dot(ci: CanvasItem, at: Vector2, r: float, col: Color) -> void:
	ci.draw_texture_rect(disc(), Rect2(at.x - r, at.y - r, r * 2.0, r * 2.0), false, col)


static func upright_circle(ci: CanvasItem, at: Vector2, r: float, col: Color) -> void:
	# an upright circle = a disc r wide and r / ground_k tall in (pre-squash) world space
	var ry := r * View.upright()
	ci.draw_texture_rect(disc(), Rect2(at.x - r, at.y - ry, r * 2.0, ry * 2.0), false, col)


static func upright_rect(ci: CanvasItem, at: Vector2, half: float, col: Color) -> void:
	ci.draw_set_transform(at, 0.0, Vector2(1.0, View.upright()))
	ci.draw_rect(Rect2(-half, -half, half * 2.0, half * 2.0), col)
	ci.draw_set_transform(Vector2.ZERO)


static func ground_circle(ci: CanvasItem, at: Vector2, r: float, col: Color) -> void:
	dot(ci, at, r, col)


static func ground_ellipse(ci: CanvasItem, at: Vector2, rx: float, ry: float, col: Color, rot: float = 0.0) -> void:
	if rot == 0.0:
		ci.draw_texture_rect(disc(), Rect2(at.x - rx, at.y - ry, rx * 2.0, ry * 2.0), false, col)
		return
	ci.draw_set_transform(at, rot, Vector2.ONE)
	ci.draw_texture_rect(disc(), Rect2(-rx, -ry, rx * 2.0, ry * 2.0), false, col)
	ci.draw_set_transform(Vector2.ZERO)


static func ground_ring(ci: CanvasItem, at: Vector2, r: float, col: Color, width: float = 2.0) -> void:
	if r <= 0.5:
		return
	ci.draw_arc(at, r, 0.0, TAU, maxi(16, int(r * 0.6)), col, width)


## an arc band on the ground from angle a0 to a1 between radii r0 and r1
static func ground_arc_band(ci: CanvasItem, at: Vector2, r0: float, r1: float, a0: float, a1: float, col: Color) -> void:
	var n := maxi(6, int(absf(a1 - a0) * 10.0))
	var pts := PackedVector2Array()
	for i in n + 1:
		pts.append(at + Vector2.from_angle(lerpf(a0, a1, float(i) / n)) * r1)
	for i in range(n, -1, -1):
		pts.append(at + Vector2.from_angle(lerpf(a0, a1, float(i) / n)) * r0)
	ci.draw_colored_polygon(pts, col)
