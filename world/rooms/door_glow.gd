class_name DoorGlow
extends Node2D
## Passages (prototype: src/main.ts drawWorld "passages"): a faint warm glow on the path while
## open, a wall of red light while the room is sealed. Also draws the stress test's sprayers.

var world: World


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null or world.map == null:
		return
	var map := world.map
	var now := Time.get_ticks_msec()
	var pulse := 0.5 + 0.5 * sin(now * 0.004)
	var C := float(Tuning.CELL)
	var font := ThemeDB.fallback_font
	for d in map.doors:
		var link = world.room.doors.get(d.id)
		if world.in_run() and link == null:
			# the way you came in: shut behind you
			for c in d.cells:
				var p := Vector2((c % map.w + 0.5) * C, (c / map.w + 0.5) * C)
				var at := View.to_world(p, float(map.height[c]))
				draw_rect(Rect2(at.x - C * 0.45, at.y - C * 0.45, C * 0.9, C * 0.9), Color(0.1, 0.09, 0.12, 0.55))
			continue
		if world.in_run() and world.doors_open:
			# what lies beyond: a label floating over the passage
			var to: RoomData = world.rooms[world.room_index_of(link[0])]
			var col: Color = WorldMapView.KIND_COLORS.get(to.kind, Color.WHITE)
			var text := RunPlan.describe(to)
			var top := View.to_world(Vector2(d.cx, d.cy), float(map.ground_at(d.cx, d.cy)) + 70.0 + pulse * 4.0)
			draw_set_transform(top, 0.0, Vector2(1.0, View.upright()))
			draw_string_outline(font, Vector2(-120, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 240, 13, 4, Color(0, 0, 0, 0.8))
			draw_string(font, Vector2(-120, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 240, 13, Color(col, 1.0).lightened(0.35))
			draw_set_transform(Vector2.ZERO)
		for c in d.cells:
			var p := Vector2((c % map.w + 0.5) * C, (c / map.w + 0.5) * C)
			var gz := float(map.height[c])
			var at := View.to_world(p, gz)
			if world.doors_open:
				Draw25.ground_circle(self, at, C * 0.4, Color(0.5, 0.38, 0.16, 0.12 + pulse * 0.08))
			else:
				draw_rect(Rect2(at.x - C * 0.45, at.y - C * 0.45, C * 0.9, C * 0.9), Color(0.6, 0.12, 0.1, 0.35 + pulse * 0.2))
				for h in 4:
					var hz := gz + 10.0 + h * 14.0 + sin(now * 0.006 + h + c) * 3.0
					Draw25.upright_circle(self, View.to_world(p, hz), 9.0, Color(1, 0.25, 0.2, 0.28 + pulse * 0.15))
	# stress-test sprayers (proto-towers)
	for em in world.projectiles.emitters:
		var gz := float(map.ground_at(em.pos.x, em.pos.y))
		var base := View.to_world(em.pos, gz)
		Draw25.ground_circle(self, base, 18.0, Color(0, 0, 0, 0.35))
		Draw25.ground_ring(self, base, 26.0, Color(0.2, 0.6, 0.6, 0.6), 2.0)
		var top := View.to_world(em.pos, gz + 20.0)
		draw_set_transform(top, PI / 4.0, Vector2(1.0, View.upright()))
		draw_rect(Rect2(-10, -10, 20, 20), Color(0.3, 0.8, 0.8, 1.0))
		draw_set_transform(Vector2.ZERO)
