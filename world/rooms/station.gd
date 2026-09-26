class_name Station
extends Node2D
## A station, local or reward spot in a room (prototype: sim/sim.ts stations, drawn in
## src/main.ts): Shrine, Well, weapon rack, a local (a tinted Bloob), notice board, cache,
## reward spot. The cell itself is solid terrain (RoomCollision); this node draws it and
## highlights it when Bloob is close enough to press T.

var world: World
var data: Dictionary       ## {kind, pos, z, ref, slot, active}

@onready var screen: Node2D = $Screen
@onready var prop: Sprite2D = $Screen/Prop
@onready var item: Sprite2D = $Screen/Item


func setup(w: World, s: Dictionary) -> void:
	world = w
	data = s
	position = s.pos
	refresh()


func refresh() -> void:
	queue_redraw()


func _process(_delta: float) -> void:
	if world == null:
		return
	var now := Time.get_ticks_msec()
	var z: float = data.z
	screen.position = Vector2(0, View.lift(z))
	screen.scale = Vector2(1, View.upright())
	var bob := sin(now * 0.003 + data.slot) * 3.0
	prop.visible = true
	item.visible = false
	prop.flip_h = false
	prop.modulate = Color.WHITE
	prop.offset = Vector2(0, -(0.5 - 0.05) * 96.0)
	match data.kind:
		World.StationKind.SHRINE:
			_set_prop("prop.shrine", 0.66)
		World.StationKind.WELL:
			_set_prop("prop.well", 0.64)
		World.StationKind.BOARD:
			_set_prop("prop.board", 0.62)
		World.StationKind.CACHE:
			_set_prop("prop.cache" if data.active else "prop.cache.open", 0.46)
		World.StationKind.RACK:
			_set_prop("prop.rack", 0.56)
			var wd: WeaponData = Content.weapons[data.ref]
			_set_item(wd, minf(0.5, wd.art_scale * 0.8), 34.0 + bob, sin(now * 0.0015 + data.slot) * 0.25, 0.0)
		World.StationKind.NPC:
			var npc: NpcData = world.room.npcs[data.ref] if data.ref < world.room.npcs.size() else null
			var frame := "bloob.idle.%d" % ((world.tick_n + data.slot * 7) / 14 % 4)
			_set_prop(frame, PlayerVisual.BLOOB_SCALE * 0.95)
			prop.offset = Vector2(0, -(0.5 - PlayerVisual.ANCHOR) * 96.0)
			prop.modulate = npc.tint if npc else Color.WHITE
			prop.flip_h = world.player.position.x < position.x
		World.StationKind.ALTAR:
			_set_prop("prop.shrine", 0.66)
			prop.modulate = Color(0.85, 0.7, 1.2) if data.active else Color(0.45, 0.45, 0.5)
		World.StationKind.OFFER:
			var o: Dictionary = data.get("offer", {sold = true, type = ""})
			_set_prop("prop.rack", 0.56)
			prop.modulate = Color(0.5, 0.5, 0.55) if o.sold else Color.WHITE
			if not o.sold and o.type == "weapon":
				var wd: WeaponData = Content.weapons[o.ref]
				_set_item(wd, minf(0.5, wd.art_scale * 0.8), 34.0 + bob, sin(now * 0.0015 + data.slot) * 0.25, 0.0)
		World.StationKind.DROP:
			prop.visible = false
			if data.active:
				var wd: WeaponData = Content.weapons[data.ref]
				_set_item(wd, wd.art_scale * 0.9, 18.0 + bob, sin(now * 0.0012) * 0.5, 0.1)
		World.StationKind.REWARD:
			prop.visible = false
			if data.active:
				var wd: WeaponData = Content.weapons[data.ref]
				var pulse := 0.5 + 0.5 * sin(now * 0.004)
				_set_item(wd, wd.art_scale * 0.9, 22.0 + bob, sin(now * 0.0012) * 0.5, 0.15 + pulse * 0.15)
	queue_redraw()


func _set_prop(name: String, scale: float) -> void:
	prop.texture = Art.frame(name)
	prop.scale = Vector2(scale, scale)


func _set_item(wd: WeaponData, scale: float, height: float, rot: float, glow: float) -> void:
	item.visible = true
	item.texture = Art.frame(wd.sprite)
	item.scale = Vector2(scale, scale)
	item.position = Vector2(0, -height * View.height_k)
	item.rotation = -rot
	item.offset = Vector2(0, -(0.5 - 0.02) * 96.0)
	item.modulate = Color(1 + glow, 1 + glow, 1 + glow)


func _draw() -> void:
	if world == null:
		return
	var z: float = data.z
	var feet := Vector2(0, View.lift(z))
	var now := Time.get_ticks_msec()
	var pulse := 0.5 + 0.5 * sin(now * 0.004)
	var kind: int = data.kind
	if kind == World.StationKind.NPC:
		Draw25.ground_ellipse(self, feet, Player.R * 1.4 * 1.25, Player.R * 1.4 * 0.8, Color(0, 0, 0, 0.4))
	elif kind != World.StationKind.REWARD and kind != World.StationKind.DROP:
		Draw25.ground_ellipse(self, feet + Vector2(0, 4), 22.0 * 1.3, 22.0 * 0.7, Color(0, 0, 0, 0.35))
	var near: bool = world.running and world.nearest_station(world.player.position) == world.stations.find(data)
	if near:
		Draw25.ground_ring(self, feet, 26 + pulse * 3, Color(1, 0.85, 0.5, 0.6), 2.0)
	match kind:
		World.StationKind.SHRINE:
			Draw25.upright_circle(self, Vector2(0, View.lift(z + 50)), 16 + pulse * 3, Color(0.75, 0.55, 1, 0.12))
		World.StationKind.CACHE:
			if data.active:
				Draw25.upright_circle(self, Vector2(0, View.lift(z + 18)), 10 + pulse * 2, Color(1, 0.85, 0.4, 0.14))
		World.StationKind.RACK:
			var wd: WeaponData = Content.weapons[data.ref]
			var owned: bool = GameState.weapons[data.ref] == 1
			var held: bool = GameState.weapon == data.ref
			var c := Color(1, 0.85, 0.4) if held else (Color(0.55, 1, 0.65) if owned else wd.fx_glow)
			Draw25.ground_ring(self, feet, 22, Color(c, 0.8 if held else (0.55 if owned else 0.3)), 2.0)
			Draw25.upright_circle(self, Vector2(0, View.lift(z + 50)), 14, Color(c, 0.1))
		World.StationKind.ALTAR:
			if data.active:
				Draw25.upright_circle(self, Vector2(0, View.lift(z + 50)), 18 + pulse * 4, Color(0.75, 0.5, 1, 0.2))
				Draw25.ground_ring(self, feet, 30 + pulse * 4, Color(0.8, 0.55, 1, 0.6), 2.0)
		World.StationKind.OFFER:
			var o: Dictionary = data.get("offer", {sold = true, type = ""})
			if not o.sold:
				Draw25.ground_ring(self, feet, 22, Color(Tuning.ESSENCE_COLOR, 0.6), 2.0)
				if o.type != "weapon":
					var c := Color(0.45, 1, 0.5) if o.type == "heal" else Content.passive(o.ref).color
					var orb := Vector2(0, View.lift(z + 40 + sin(now * 0.003 + data.ref) * 3.0))
					Draw25.upright_circle(self, orb, 12 + pulse * 2, Color(c, 0.2))
					Draw25.upright_circle(self, orb, 6, Color(c, 0.95))
		World.StationKind.DROP:
			if data.active:
				var c: Color = Content.weapons[data.ref].fx_heavy_glow
				Draw25.ground_ring(self, feet, 18 + pulse * 4, Color(c, 0.6), 2.0)
				Draw25.ground_circle(self, feet, 10, Color(c, 0.2))
		World.StationKind.REWARD:
			if data.active:
				var c: Color = Content.weapons[data.ref].fx_heavy_glow
				# a beam of light and the weapon turning slowly above its spot
				Draw25.ground_ring(self, feet, 20 + pulse * 6, Color(c, 0.7), 2.5)
				Draw25.ground_circle(self, feet, 12, Color(c, 0.25))
				for hh in 6:
					Draw25.upright_circle(self, Vector2(0, View.lift(z + 8 + hh * 22)), 10 - hh, Color(c, 0.12))
