extends Node
## The game's art atlas, generated at boot like the prototype's (render/art.ts paintAtlas):
##  - Bloob, locals and weapons: pixel art from pose data (effects/art/pixel_art.gd)
##  - monsters, the totem, station props, trees: vector drawings (effects/art/vector_painter.gd)
##    rendered once in a SubViewport and sliced into textures
## Every frame is 96 x 96 with the feet near the bottom (anchor 0.06). Frame names follow the
## prototype ("bloob.run.3", "brute.windup.0", "weapon.sword", "prop.well", "tree.2"), so real
## sprite sheets can replace them one by one: put a texture in res://assets/art/<name>.png and
## it is used instead of the generated one.

signal baked

const CELL := 96
const ENEMY_CLIPS := {walk = 4, windup = 1, attack = 1, hurt = 1}
const MONSTERS := ["charger", "weaver", "flanker", "circler", "stalker", "brute"]

var frames := {}
var ready_done := false
var _blank: Texture2D


func _ready() -> void:
	var img := Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 1, 0.0))
	_blank = ImageTexture.create_from_image(img)
	_build_pixel_frames()
	if DisplayServer.get_name() == "headless":
		ready_done = true
		return
	_bake_vectors.call_deferred()


## the texture for a frame name (a blank one until the vector atlas has baked)
func frame(name: String) -> Texture2D:
	return frames.get(name, _blank)


## Sprite2D scale for a character drawn `char_scale` world units per atlas pixel
func world_scale(char_scale: float) -> float:
	return char_scale


func _override(name: String) -> Texture2D:
	var path := "res://assets/art/%s.png" % name
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _put_image(name: String, img: Image) -> void:
	var tex := _override(name)
	frames[name] = tex if tex else ImageTexture.create_from_image(img)


func _build_pixel_frames() -> void:
	var poses := PixelArt.bloob_poses()
	for clip in poses:
		var list: Array = poses[clip]
		for i in list.size():
			_put_image("bloob.%s.%d" % [clip, i], PixelArt.bloob(list[i]).to_image(3))
	_put_image("weapon.paws", PixelArt.paw().to_image(3))
	_put_image("weapon.sword", PixelArt.sword().to_image(3))
	_put_image("weapon.spear", PixelArt.spear().to_image(2))
	_put_image("weapon.hammer", PixelArt.hammer().to_image(3))
	_put_image("weapon.daggers", PixelArt.fang().to_image(4))
	_put_image("weapon.staff", PixelArt.staff().to_image(2))


func _bake_vectors() -> void:
	var painter := VectorPainter.new()
	var names := []
	var add := func(n: String, c: Callable) -> void:
		painter.cells.append([n, c])
		names.append(n)
	add.call("totem.idle.0", painter.draw_totem.bind(0))
	add.call("totem.idle.1", painter.draw_totem.bind(1))
	add.call("prop.shrine", painter.draw_shrine)
	add.call("prop.well", painter.draw_well)
	add.call("prop.rack", painter.draw_rack)
	add.call("prop.board", painter.draw_board)
	add.call("prop.cache", painter.draw_cache.bind(false))
	add.call("prop.cache.open", painter.draw_cache.bind(true))
	add.call("tree.0", painter.draw_tree_round)
	add.call("tree.1", painter.draw_tree_pine)
	add.call("tree.2", painter.draw_tree_dead)
	add.call("tree.3", painter.draw_bush.bind(0))
	add.call("tree.4", painter.draw_bush.bind(1))
	for id in MONSTERS:
		var fn := Callable(painter, "draw_" + id)
		for clip in ENEMY_CLIPS:
			for i in ENEMY_CLIPS[clip]:
				add.call("%s.%s.%d" % [id, clip, i], fn.bind(clip, i))
	var vp := SubViewport.new()
	vp.size = painter.atlas_size()
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(vp)
	vp.add_child(painter)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var atlas := vp.get_texture().get_image()
	if atlas and not atlas.is_empty():
		var tex := ImageTexture.create_from_image(atlas)
		for i in names.size():
			var over := _override(names[i])
			if over:
				frames[names[i]] = over
				continue
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(painter.cell_origin(i), Vector2(CELL, CELL))
			frames[names[i]] = at
	vp.queue_free()
	ready_done = true
	baked.emit()
