class_name WorldMapView
extends Control
## The world map (prototype: render/worldmap.ts): areas on their map grid, linked by their
## passages, with fog of war. Visited areas and their neighbours show ("?" until visited),
## the current area is highlighted. Used small in the HUD corner and large in the menu.

@export var box := Vector2(38, 26)
@export var gap := Vector2(14, 12)
@export var label_chars := 3          ## 0 = full names
@export var font_size := 10

const KIND_COLORS := {
	combat = Color(0.77, 0.29, 0.23, 0.5), elite = Color(0.77, 0.29, 0.23, 0.5),
	hub = Color(0.85, 0.65, 0.29, 0.45), shop = Color(0.9, 0.55, 0.27, 0.45),
	social = Color(0.35, 0.67, 0.75, 0.45), rest = Color(0.35, 0.67, 0.75, 0.45),
	explore = Color(0.55, 0.55, 0.47, 0.35), training = Color(0.55, 0.55, 0.47, 0.35),
}

var room_idx := 0


func _ready() -> void:
	custom_minimum_size = _size()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _size() -> Vector2:
	var cols := 0
	var rows := 0
	for r in Content.rooms:
		if r.on_map:
			cols = maxi(cols, r.map_pos.x + 1)
			rows = maxi(rows, r.map_pos.y + 1)
	return Vector2(12 + cols * (box.x + gap.x) - gap.x, 12 + rows * (box.y + gap.y) - gap.y)


func _pos(r: RoomData) -> Vector2:
	return Vector2(6 + r.map_pos.x * (box.x + gap.x), 6 + r.map_pos.y * (box.y + gap.y))


func refresh(current: int) -> void:
	room_idx = current
	queue_redraw()


func _draw() -> void:
	var states := GameState.room_states
	if states.is_empty():
		return
	# fog of war: visited areas, plus the ones next to them
	var known := {}
	for i in Content.rooms.size():
		var r := Content.rooms[i]
		if not r.on_map or (not states[i].visited and i != room_idx):
			continue
		known[i] = true
		for d in r.doors.values():
			var j := Content.room_index(d[0])
			if Content.rooms[j].on_map:
				known[j] = true
	var font := get_theme_default_font()
	for i in Content.rooms.size():
		var r := Content.rooms[i]
		if not r.on_map:
			continue
		for d in r.doors.values():
			var j := Content.room_index(d[0])
			if j <= i or not Content.rooms[j].on_map:
				continue
			if known.has(i) and known.has(j) and (states[i].visited or states[j].visited):
				draw_line(_pos(r) + box / 2, _pos(Content.rooms[j]) + box / 2, Color(0.94, 0.9, 0.82, 0.3), 2.0)
	for i in Content.rooms.size():
		var r := Content.rooms[i]
		if not r.on_map or not known.has(i):
			continue
		var st: Dictionary = states[i]
		var rect := Rect2(_pos(r), box)
		var col: Color = KIND_COLORS.get(r.kind, Color(0.5, 0.5, 0.5, 0.4))
		if st.cleared:
			col = Color(0.55, 0.55, 0.47, 0.35)
		if st.visited or i == room_idx:
			draw_rect(rect, col)
		draw_rect(rect, Color(0.94, 0.9, 0.82, 0.45 if st.visited else 0.25), false, 1.0)
		if i == room_idx:
			draw_rect(rect.grow(2), UiStyle.CANDLE, false, 2.0)
		var name := r.name.trim_prefix("The ")
		var text := (name.substr(0, label_chars) if label_chars > 0 else name) if st.visited or i == room_idx else "?"
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, rect.get_center() + Vector2(-ts.x / 2, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiStyle.BONE)
