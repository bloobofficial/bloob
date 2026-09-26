class_name Minimap
extends Control
## The minimap (Patch 1): the actual ground of the map you're on, uncovered as you walk (fog of
## war), with the places that matter marked and you as an arrow pointing where you aim.
## Zoom: whole map, or closer views that follow Bloob (, and . or the mouse wheel).
##   white arrow   you                     blue    altar        green  shop
##   red           lounge / safe room      chest   hidden loot (once found)
##   gold arch     the gate (red while shut)        dashed  a place not yet explored
## Used small in the HUD corner (follows Bloob) and large in the menu (whole map, legend).

const ZOOMS := [1.0, 2.0, 3.2]
const ICON := {
	altar = Color(0.42, 0.5, 1.0), shop = Color(0.35, 0.85, 0.45), lounge = Color(0.95, 0.35, 0.32),
	loot = Color(0.98, 0.78, 0.3), exit = Color(0.98, 0.85, 0.5),
}

@export var box := Vector2(236, 170)
@export var zoom_i := 1
@export var show_title := true

var world: World
var _img: Image
var _tex: ImageTexture
var _room: RoomData
var _logged := 0
var _dirty := false


func _ready() -> void:
	custom_minimum_size = box
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func zoom(step: int) -> void:
	zoom_i = clampi(zoom_i + step, 0, ZOOMS.size() - 1)
	queue_redraw()


## the colour a revealed cell shows
func _cell_color(c: int) -> Color:
	var m := world.map
	var hh := m.height[c]
	if hh == Tuning.VOID_H:
		return Color(0, 0, 0, 0)
	var st := m.style[c]
	if m.door[c] != 0:
		return Color(0.95, 0.8, 0.45)
	if m.wall[c] == 1:
		return Color(0.42, 0.4, 0.44)
	match m.mat[c]:
		RoomMap.Mat.TREE:
			return Color(0.13, 0.27, 0.16)
		RoomMap.Mat.BUSH:
			return Color(0.2, 0.37, 0.2)
		RoomMap.Mat.WATER:
			return Color(0.25, 0.45, 0.62)
		RoomMap.Mat.PROP:
			return Color(0.85, 0.8, 0.7)
		RoomMap.Mat.ROCK:
			return Color(0.45, 0.45, 0.47)
	if st == 119 or st == 114:
		return Color(0.55, 0.38, 0.24)
	if st == 115:
		return Color(0.5, 0.48, 0.62)
	if m.mat[c] == RoomMap.Mat.PATH:
		return Color(0.62, 0.5, 0.33)
	if hh >= Tuning.LEVEL_H:
		return Color(0.42, 0.6, 0.36)
	return Color(0.3, 0.48, 0.3)


func _sync() -> void:
	var m := world.map
	if _room != world.room or _img == null or _img.get_width() != m.w or _img.get_height() != m.h or world.reveal_log.size() < _logged:
		_room = world.room
		_img = Image.create(maxi(1, m.w), maxi(1, m.h), false, Image.FORMAT_RGBA8)
		_img.fill(Color(0, 0, 0, 0))
		_logged = 0
		_tex = null
	var log := world.reveal_log
	if _logged < log.size():
		for i in range(_logged, log.size()):
			var c := log[i]
			_img.set_pixel(c % m.w, c / m.w, _cell_color(c))
		_logged = log.size()
		_dirty = true
	if _tex == null:
		_tex = ImageTexture.create_from_image(_img)
		_dirty = false
	elif _dirty:
		_tex.update(_img)
		_dirty = false


func _process(_delta: float) -> void:
	if world == null or not is_visible_in_tree():
		return
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.08, 0.82))
	if world == null or world.map == null or world.map.w == 0:
		return
	_sync()
	var m := world.map
	var p := world.player
	var fit := minf((size.x - 12.0) / m.w, (size.y - 12.0) / m.h)
	var s: float = fit * ZOOMS[zoom_i]
	var map_size := Vector2(m.w, m.h) * s
	var me := Vector2(p.position.x, p.position.y) / Tuning.CELL * s
	var origin := (size - map_size) / 2.0
	if map_size.x > size.x - 12.0 or map_size.y > size.y - 12.0:
		# closer views follow Bloob (kept inside the map)
		origin = size / 2.0 - me
		origin.x = clampf(origin.x, size.x - 6.0 - map_size.x, 6.0) if map_size.x > size.x - 12.0 else (size.x - map_size.x) / 2.0
		origin.y = clampf(origin.y, size.y - 6.0 - map_size.y, 6.0) if map_size.y > size.y - 12.0 else (size.y - map_size.y) / 2.0
	draw_texture_rect(_tex, Rect2(origin, map_size), false)
	var cs := s   # one cell on the minimap
	var to_map := func(cell: Vector2) -> Vector2: return origin + cell * cs
	# places: explored ones get their icon; the rest are dashed outlines (hidden groves stay hidden)
	var font := get_theme_default_font()
	for a in world.room.areas:
		var seen: bool = world.areas_seen.has(a.idx)
		var kind: String = a.kind
		var at: Vector2 = to_map.call(Vector2(a.cell) + Vector2(0.5, 0.5))
		if not seen:
			if kind == "loot":
				continue
			var r: Rect2i = a.rect
			var rr := Rect2(to_map.call(Vector2(r.position)), Vector2(r.size) * cs)
			_dashed_rect(rr, Color(0.94, 0.9, 0.82, 0.38))
		if ICON.has(kind) and (seen or kind != "loot"):
			_icon(kind, at, maxf(3.5, cs * 2.2), seen)
	# monsters you've seen that are awake
	for e: Enemy in world.enemies:
		if not e.alive or e.dormant:
			continue
		var c := world.map.cell_of(e.position.x, e.position.y)
		if c >= 0 and world.explored[c]:
			draw_circle(to_map.call(e.position / Tuning.CELL), maxf(1.6, cs * 0.9), Color(1, 0.3, 0.25, 0.95))
	# you: an arrow pointing where you aim
	var dir := (p.aim - p.position)
	var ang := dir.angle() if dir.length() > 1.0 else -PI / 2.0
	var tip := maxf(5.0, cs * 2.4)
	var c0 := origin + me
	var pts := PackedVector2Array([c0 + Vector2.from_angle(ang) * tip, c0 + Vector2.from_angle(ang + 2.5) * tip * 0.7, c0 + Vector2.from_angle(ang - 2.5) * tip * 0.7])
	draw_colored_polygon(pts, Color.WHITE)
	pts.append(pts[0])
	draw_polyline(pts, Color(0, 0, 0, 0.8), 1.0)
	if show_title:
		draw_string(font, Vector2(8, 14), "MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiStyle.ASH)
		var zt := "×%s   , ." % ("1" if zoom_i == 0 else str(ZOOMS[zoom_i]).trim_suffix(".0"))
		draw_string(font, Vector2(size.x - 60, size.y - 7), zt, HORIZONTAL_ALIGNMENT_RIGHT, 54, 9, UiStyle.ASH)


func _dashed_rect(r: Rect2, col: Color) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		draw_dashed_line(pts[i], pts[i + 1], col, 1.0, 3.0)


func _icon(kind: String, at: Vector2, r: float, seen: bool) -> void:
	var col: Color = ICON[kind]
	var a := 1.0 if seen else 0.55
	match kind:
		"loot":
			# a little chest
			var w := r * 2.2
			var h := r * 1.6
			draw_rect(Rect2(at.x - w / 2, at.y - h / 2, w, h), Color(0.55, 0.35, 0.15, a))
			draw_rect(Rect2(at.x - w / 2, at.y - h / 2, w, h * 0.4), Color(col, a))
			draw_rect(Rect2(at.x - 1, at.y - 1, 2, 3), Color(0.2, 0.12, 0.05, a))
			draw_rect(Rect2(at.x - w / 2, at.y - h / 2, w, h), Color(0, 0, 0, 0.7 * a), false, 1.0)
		"exit":
			# the gate: an arch, red while it's shut
			var shut := not world.doors_open
			var gc := Color(0.95, 0.35, 0.3, a) if shut else Color(col, a)
			draw_arc(at + Vector2(0, r * 0.2), r, PI, TAU, 10, gc, 2.0)
			draw_line(at + Vector2(-r, r * 0.2), at + Vector2(-r, r * 1.2), gc, 2.0)
			draw_line(at + Vector2(r, r * 0.2), at + Vector2(r, r * 1.2), gc, 2.0)
		_:
			draw_circle(at, r + 1.0, Color(0, 0, 0, 0.6 * a))
			draw_circle(at, r, Color(col, a))
			draw_circle(at + Vector2(-r * 0.3, -r * 0.3), r * 0.35, Color(1, 1, 1, 0.35 * a))
