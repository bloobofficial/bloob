class_name WorldMapView
extends Control
## The map (prototype: render/worldmap.ts): areas on their map grid, linked by their passages,
## with fog of war. Visited areas and their neighbours show, the current area is highlighted.
## Used small in the HUD corner and large in the menu. Draws either the hub world or the
## current run (where the rooms ahead show what they are, so you can choose a path).

@export var box := Vector2(38, 26)
@export var gap := Vector2(14, 12)
@export var label_chars := 3          ## 0 = full names
@export var font_size := 10

const KIND_COLORS := {
	combat = Color(0.77, 0.29, 0.23, 0.5), elite = Color(0.85, 0.3, 0.5, 0.55), boss = Color(0.65, 0.3, 0.85, 0.6),
	hub = Color(0.85, 0.65, 0.29, 0.45), shop = Color(0.9, 0.55, 0.27, 0.45), start = Color(0.85, 0.65, 0.29, 0.45),
	social = Color(0.35, 0.67, 0.75, 0.45), rest = Color(0.35, 0.67, 0.75, 0.45), safe = Color(0.35, 0.67, 0.75, 0.45),
	altar = Color(0.62, 0.45, 0.9, 0.5), weapon = Color(0.85, 0.75, 0.35, 0.45), event = Color(0.55, 0.45, 0.8, 0.45),
	explore = Color(0.55, 0.55, 0.47, 0.35), training = Color(0.55, 0.55, 0.47, 0.35),
}
## what an unexplored run room is called on the map
const KIND_SHORT := {
	combat = "Fight", elite = "Elite", boss = "Boss", shop = "Shop", start = "Start", safe = "Rest",
	altar = "Altar", weapon = "Arms", event = "Cache",
}

var room_idx := 0
var rooms: Array = []
var reveal_kinds := false


func _ready() -> void:
	if rooms.is_empty():
		rooms = Content.rooms
	custom_minimum_size = _size()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## draw these rooms (the world's list); a run's rooms say what they are before you visit
func use_rooms(list: Array, run: bool) -> void:
	if list == rooms:
		return
	rooms = list
	reveal_kinds = run
	custom_minimum_size = _size()
	update_minimum_size()


func _size() -> Vector2:
	var cols := 0
	var rows := 0
	for r in rooms:
		if r.on_map:
			cols = maxi(cols, r.map_pos.x + 1)
			rows = maxi(rows, r.map_pos.y + 1)
	return Vector2(12 + cols * (box.x + gap.x) - gap.x, 12 + rows * (box.y + gap.y) - gap.y)


func _pos(r: RoomData) -> Vector2:
	return Vector2(6 + r.map_pos.x * (box.x + gap.x), 6 + r.map_pos.y * (box.y + gap.y))


func _index(id: String) -> int:
	for i in rooms.size():
		if rooms[i].id == id:
			return i
	return -1


func refresh(current: int) -> void:
	room_idx = current
	queue_redraw()


func _draw() -> void:
	var states := GameState.room_states
	if states.size() != rooms.size():
		return
	# fog of war: visited areas, plus the ones next to them
	var known := {}
	for i in rooms.size():
		var r: RoomData = rooms[i]
		if not r.on_map or (not states[i].visited and i != room_idx):
			continue
		known[i] = true
		for d in r.doors.values():
			var j := _index(d[0])
			if j >= 0 and rooms[j].on_map:
				known[j] = true
	var font := get_theme_default_font()
	for i in rooms.size():
		var r: RoomData = rooms[i]
		if not r.on_map:
			continue
		for d in r.doors.values():
			var j := _index(d[0])
			if j < 0 or (j <= i and not reveal_kinds) or not rooms[j].on_map:
				continue
			if known.has(i) and known.has(j) and (states[i].visited or states[j].visited):
				draw_line(_pos(r) + box / 2, _pos(rooms[j]) + box / 2, Color(0.94, 0.9, 0.82, 0.3), 2.0)
	for i in rooms.size():
		var r: RoomData = rooms[i]
		if not r.on_map or not known.has(i):
			continue
		var st: Dictionary = states[i]
		var rect := Rect2(_pos(r), box)
		var col: Color = KIND_COLORS.get(r.kind, Color(0.5, 0.5, 0.5, 0.4))
		if st.cleared:
			col = Color(0.55, 0.55, 0.47, 0.35)
		if st.visited or i == room_idx or reveal_kinds:
			draw_rect(rect, col if st.visited or i == room_idx else Color(col, col.a * 0.55))
		draw_rect(rect, Color(0.94, 0.9, 0.82, 0.45 if st.visited else 0.25), false, 1.0)
		if i == room_idx:
			draw_rect(rect.grow(2), UiStyle.CANDLE, false, 2.0)
		var name := r.name.trim_prefix("The ")
		if reveal_kinds:
			name = KIND_SHORT.get(r.kind, name)
		var text := (name.substr(0, label_chars) if label_chars > 0 else name) if st.visited or i == room_idx or reveal_kinds else "?"
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, rect.get_center() + Vector2(-ts.x / 2, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiStyle.BONE)
