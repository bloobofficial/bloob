class_name Backdrop
extends Node2D
## The depths below the island (Patch 1 "more 2.5D"): drifting banks of mist and faint motes
## far beneath the playfield, moving slower than the ground as the camera pans (parallax), so
## the island reads as floating high above something. Drawn first, under the terrain.

const TILE := 1600.0        ## the pattern repeats every TILE units
const PARALLAX := 0.45      ## how much slower than the ground it slides
const BLOBS := 30
const MOTES := 60

var world: World
var _blobs := []            ## [Vector2 pos, radius, alpha]
var _motes := []            ## [Vector2 pos, phase]


func _ready() -> void:
	for i in BLOBS:
		_blobs.append([Vector2(RoomMap.hash2(i, 1) * TILE, RoomMap.hash2(1, i) * TILE), 140.0 + RoomMap.hash2(i, 7) * 220.0, 0.05 + RoomMap.hash2(i, 9) * 0.07])
	for i in MOTES:
		_motes.append([Vector2(RoomMap.hash2(i, 31) * TILE, RoomMap.hash2(31, i) * TILE), RoomMap.hash2(i, 33) * TAU])


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null or world.room == null:
		return
	var vp := get_viewport_rect().size
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var view := Rect2(inv * Vector2.ZERO, inv.basis_xform(vp))
	var center := view.get_center()
	var fog: Color = world.room.theme.fog
	var mist := fog.lightened(0.22)
	var disc := Draw25.disc()
	var shift := center * (1.0 - PARALLAX)
	var reach := maxf(view.size.x, view.size.y) * 0.5 + 400.0
	var now := Time.get_ticks_msec() * 0.001
	for b in _blobs:
		var p := _wrap(b[0] + shift + Vector2(now * 6.0, 0), center)
		if absf(p.x - center.x) > reach or absf(p.y - center.y) > reach * 1.8:
			continue
		var r: float = b[1]
		draw_texture_rect(disc, Rect2(p.x - r, p.y - r * 0.6, r * 2.0, r * 1.2), false, Color(mist, b[2]))
	for m in _motes:
		var p := _wrap(m[0] + center * (1.0 - PARALLAX * 0.6), center)
		var tw := 0.5 + 0.5 * sin(now * 1.3 + m[1])
		draw_texture_rect(disc, Rect2(p.x - 2, p.y - 2, 4, 4), false, Color(mist.lightened(0.3), 0.12 + tw * 0.25))


## the copy of a repeating point nearest `c`
func _wrap(p: Vector2, c: Vector2) -> Vector2:
	return Vector2(c.x + fposmod(p.x - c.x + TILE * 0.5, TILE) - TILE * 0.5, c.y + fposmod(p.y - c.y + TILE * 0.5, TILE) - TILE * 0.5)
