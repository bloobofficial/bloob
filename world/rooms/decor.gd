class_name Decor
extends Node2D
## Scenery that lights the way on generated maps: torches along the paths and at the doors of
## places, blue braziers at altars. An upright pixel sprite with a flickering flame, a glow
## around the flame and a pool of light on the ground (both additive). Not solid.

const GLOW := {torch = Color(1.0, 0.55, 0.2), brazier = Color(0.35, 0.6, 1.0)}
const FLAME_Y := {torch = 36.0, brazier = 28.0}   ## flame height on the sprite (screen units)
const SCALE := 0.5

static var _glow_tex: Texture2D
static var _add: CanvasItemMaterial

var type := "torch"
var z := 0.0
var _screen: Node2D
var _spr: Sprite2D
var _halo: Sprite2D
var _pool: Sprite2D
var _seed := 0.0


static func glow_texture() -> Texture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.35, Color(1, 1, 1, 0.45))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_glow_tex = t
		_add = CanvasItemMaterial.new()
		_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _glow_tex


func setup(t: String, at: Vector2, gz: float) -> void:
	type = t
	position = at
	z = gz
	_seed = RoomMap.hash2(int(at.x), int(at.y)) * 100.0
	var tex := glow_texture()
	_pool = Sprite2D.new()
	_pool.texture = tex
	_pool.material = _add
	add_child(_pool)
	_screen = Node2D.new()
	add_child(_screen)
	_spr = Sprite2D.new()
	_spr.offset = Vector2(0, -(0.5 - 0.03) * 96.0)
	_spr.scale = Vector2(SCALE, SCALE)
	_screen.add_child(_spr)
	_halo = Sprite2D.new()
	_halo.texture = tex
	_halo.material = _add
	_screen.add_child(_halo)
	_process(0.0)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	var f := 0.86 + 0.09 * sin(now * 8.3 + _seed) + 0.05 * sin(now * 21.0 + _seed * 1.7)
	var col: Color = GLOW.get(type, GLOW.torch)
	_screen.position = Vector2(0, View.lift(z))
	_screen.scale = Vector2(1.0, View.upright())
	_spr.texture = Art.frame("decor.%s.%d" % [type, int(now * 9.0 + _seed) % 3])
	_halo.position = Vector2(0, -float(FLAME_Y.get(type, 36.0)))
	_halo.scale = Vector2.ONE * (0.9 * f)
	_halo.modulate = Color(col, 0.55 * f)
	# the pool of light on the ground (the camera squashes it into an ellipse)
	_pool.position = Vector2(0, View.lift(z))
	_pool.scale = Vector2.ONE * (3.4 * f)
	_pool.modulate = Color(col, 0.22 * f)
