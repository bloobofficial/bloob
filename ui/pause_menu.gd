class_name PauseMenu
extends Control
## The pause menu (prototype: render/menu.ts): Character, Equipment, Skills, Items, Map,
## System. Opening it pauses the game (the tree is paused; this menu keeps processing).
## Equipping from the Equipment tab works in safe areas only, like the prototype.

signal restart_requested
signal perf_toggled

const TABS := ["Character", "Equipment", "Skills", "Items", "Map", "System"]
const SHAPE_NAME := ["Arc", "Thrust", "Smash", "Ring"]

var world: World
var tab := 0
var _page: VBoxContainer
var _tab_buttons: Array[Button] = []
var _item_cat := 0
var _sel_item := 0
var _key := ""


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(UiStyle.DUSK, 0.85)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := UiStyle.panel(0.97)
	box.custom_minimum_size = Vector2(900, 560)
	center.add_child(box)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	box.add_child(h)
	var nav := VBoxContainer.new()
	nav.custom_minimum_size = Vector2(150, 0)
	nav.add_child(UiStyle.label("Bloob", 24))
	for i in TABS.size():
		var b := UiStyle.button(TABS[i], 13)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(show_tab.bind(i))
		nav.add_child(b)
		_tab_buttons.append(b)
	var foot := UiStyle.rich(10)
	foot.text = "[color=#9a93a8]Esc resume\nQ / E switch tabs[/color]"
	nav.add_child(foot)
	h.add_child(nav)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(700, 540)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 6)
	scroll.add_child(_page)


func toggle(open: bool) -> void:
	visible = open
	_key = ""
	if open:
		_render()


func cycle(dir: int) -> void:
	show_tab((tab + dir + TABS.size()) % TABS.size())


func show_tab(i: int) -> void:
	tab = i
	_key = ""
	_render()


func _process(_delta: float) -> void:
	if visible:
		_render()


func _render() -> void:
	var p := world.player
	var key := "%d|%d|%d|%d|%d|%d|%s|%s|%d|%d|%s|%d|%d|%d|%d|%d" % [tab, GameState.level, GameState.xp, ceili(p.hp), floori(p.mana), GameState.weapon,
		GameState.weapons, GameState.res, GameState.flask, GameState.job, GameState.techs, world.room_idx, _sel_item, _item_cat, GameState.kills, int(Sfx.enabled)] + "|%d|%d" % [GameState.passives.size(), GameState.essence]
	if key == _key:
		return
	_key = key
	for i in _tab_buttons.size():
		_tab_buttons[i].add_theme_color_override("font_color", UiStyle.CANDLE if i == tab else UiStyle.BONE)
	UiStyle.clear(_page)
	match tab:
		0: _character()
		1: _equipment()
		2: _skills()
		3: _items()
		4: _map()
		_: _system()


func _h3(t: String) -> void:
	_page.add_child(UiStyle.label(t, 22))


func _h4(t: String) -> void:
	_page.add_child(UiStyle.label(t.to_upper(), 11, UiStyle.CANDLE))


func _text(t: String) -> void:
	var r := UiStyle.rich(12)
	r.text = t
	_page.add_child(r)


func _stats(pairs: Array) -> void:
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 18)
	for pr in pairs:
		g.add_child(UiStyle.label(pr[0], 11, UiStyle.ASH))
		g.add_child(UiStyle.label(pr[1], 11))
	_page.add_child(g)


func _icon(frame: String, size: float, dark := false) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Art.frame(frame)
	t.custom_minimum_size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if dark:
		t.modulate = Color(0.05, 0.05, 0.08, 0.9)
	return t


func _pct(v: float) -> String:
	return "%d%%" % roundi(v * 100)


func _character() -> void:
	var p := world.player
	var job := GameState.job_data()
	var wd := GameState.weapon_data()
	_h3("Character")
	var hero := HBoxContainer.new()
	hero.add_child(_icon("bloob.idle.0", 96))
	var hv := VBoxContainer.new()
	hv.add_child(UiStyle.label("Bloob  ·  Level %d %s" % [GameState.level, job.name], 16))
	hv.add_child(UiStyle.label("Experience  " + ("max" if GameState.level >= Tuning.MAX_LEVEL else "%d / %d" % [GameState.xp, Tuning.xp_to_next(GameState.level)]), 12, UiStyle.ASH))
	hv.add_child(UiStyle.label(job.blurb, 12, UiStyle.ASH))
	hero.add_child(hv)
	_page.add_child(hero)
	_h4("Combat")
	_stats([["Health", "%d / %d" % [ceili(p.hp), p.max_hp]], ["Mana", "%d / %d" % [floori(p.mana), p.max_mana]],
		["Damage", _pct(GameState.dmg_mul)], ["Weapon", wd.name], ["Move speed", _pct(GameState.speed_mul * wd.move_mul)],
		["Skill recharge", _pct(1.0 / GameState.cd_mul)],
		["Flask", "%d / %d · heals %s over %.1f s" % [GameState.flask, GameState.flask_max, _pct(GameState.flask_heal), Tuning.FLASK_TICKS / 60.0]],
		["Pickup reach", str(roundi(GameState.magnet))]])
	var combat := 0
	var cleared := 0
	for i in world.rooms.size():
		if world.rooms[i].encounter and world.rooms[i].on_map:
			combat += 1
			if GameState.room_states[i].cleared:
				cleared += 1
	if world.in_run():
		_h4("Run")
		_stats([["Essence", "%d  (%d collected)" % [GameState.essence, GameState.essence_total]], ["Seed", str(world.run.seed_value)],
			["Melee damage", _pct(GameState.melee_mul)], ["Reach", _pct(GameState.reach_mul)],
			["Swing speed", _pct(GameState.atk_speed)], ["Damage taken", _pct(GameState.dmg_taken_mul)]])
	var secs := GameState.run_ticks / 60
	var owned := []
	for i in Content.techs.size():
		if GameState.techs[i]:
			owned.append(Content.techs[i].name)
	_h4("This run")
	_stats([["Areas cleared", "%d / %d" % [cleared, combat]], ["Defeated", str(GameState.kills)], ["Time", "%d:%02d" % [secs / 60, secs % 60]],
		["Techs", "%d / %d" % [owned.size(), Content.techs.size()]]])
	_text(("Techs: " + " · ".join(owned)) if owned.size() > 0 else "No techs yet. Spend what you gather at a Shrine.")


func _equipment() -> void:
	var safe := world.room.encounter == null and not world.in_run()   # in a run you hold what you picked up
	var wd := GameState.weapon_data()
	_h3("Equipment")
	var cur := HBoxContainer.new()
	cur.add_child(_icon(wd.sprite, 56))
	var cv := VBoxContainer.new()
	cv.add_child(UiStyle.label(wd.name, 15))
	cv.add_child(UiStyle.label(wd.blurb, 11, UiStyle.ASH))
	var combo_t := 0.0
	for k in wd.combo.size():
		var q := wd.combo[k]
		combo_t += q.windup + q.active + (q.chain_from if k < wd.combo.size() - 1 else q.recover)
	cv.add_child(UiStyle.label("%d hits · reach %d · %.1f damage per combo · combo %.2f s · move %d%%" % [
		wd.combo.size(), wd.reach(), wd.combo_damage(), (combo_t + wd.combo_end_cd) / 60.0, roundi(wd.move_mul * 100)], 11, UiStyle.ASH))
	cur.add_child(cv)
	_page.add_child(cur)
	var table := GridContainer.new()
	table.columns = 5
	table.add_theme_constant_override("h_separation", 20)
	for hd in ["Swing", "Hitbox", "Reach", "Damage", "Lands after"]:
		table.add_child(UiStyle.label(hd, 11, UiStyle.ASH))
	for k in wd.combo.size():
		var q := wd.combo[k]
		var shape := q.shape()
		var hitbox: String = SHAPE_NAME[shape]
		if shape == SwingData.Shape.ARC:
			var span := absf((q.vis_to if q.has_vis else q.arc) - (q.vis_from if q.has_vis else -q.arc))
			hitbox += " %d°" % roundi(rad_to_deg(span))
		for cell in ["%d. %s" % [k + 1, q.name], hitbox, str(roundi(q.range)), "%.1f" % q.damage, "%.2f s" % ((q.windup + q.active) / 60.0)]:
			table.add_child(UiStyle.label(cell, 11))
	_page.add_child(table)
	_h4("Weapons")
	for i in Content.weapons.size():
		var w := Content.weapons[i]
		var row := HBoxContainer.new()
		var own := GameState.weapons[i] == 1
		row.add_child(_icon(w.sprite, 48, not own))
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if own:
			tv.add_child(UiStyle.label(w.name, 13))
			tv.add_child(UiStyle.label(w.traits, 11, UiStyle.ASH))
		else:
			tv.add_child(UiStyle.label("???", 13))
			var hint := "Buy it at the Forge"
			for r in Content.rooms:
				if r.reward == w.id:
					hint = ("Clear " + r.name if r.encounter else "Somewhere in " + r.name) + ", or buy it at the Forge"
			tv.add_child(UiStyle.label(hint, 11, UiStyle.ASH))
		row.add_child(tv)
		if own:
			var b: Button
			if GameState.weapon == i:
				b = UiStyle.button("In hand", 12)
				b.disabled = true
			elif safe:
				b = UiStyle.button("Equip", 12)
				b.pressed.connect(func(): world.menu_equip(i); _key = "")
			else:
				b = UiStyle.button("Safe areas only", 12)
				b.disabled = true
			row.add_child(b)
		_page.add_child(row)
	_text("Swap between owned weapons here or at any Forge rack." if safe else "You can swap weapons in safe areas.")


func _skills() -> void:
	var job := GameState.job_data()
	_h3("Skills")
	_h4("Learned skills")
	if GameState.passives.is_empty():
		_text("[color=#9a93a8]No skills acquired. Altars, elite rewards and shops offer them.[/color]")
	else:
		var seen := {}
		for id in GameState.passives:
			if seen.has(id):
				continue
			seen[id] = true
			var pd := Content.passive(id)
			var n := GameState.passive_count(id)
			_text("[b][color=%s]%s[/color][/b]%s\n%s" % [UiStyle.hex(pd.color), pd.name, "  ×%d" % n if n > 1 else "", pd.desc])
	_h4("Job abilities · " + job.name)
	for slot in 2:
		var d: SkillData = job.skills[slot]
		_text("[b]%s  %s[/b]\n%s\n[color=#9a93a8]%d mana · %.1f s cooldown[/color]" % ["Q" if slot == 0 else "E", d.name, d.desc, d.mana, roundi(d.cooldown * GameState.cd_mul) / 60.0])
	_text("Job abilities come from your job; change jobs at a Shrine.")


func _items() -> void:
	_h3("Items")
	var list := [{name = "Goo Flask", kind = "Consumable", color = Color("#f5c95a"), count = "%d/%d" % [GameState.flask, GameState.flask_max],
		desc = "Drink with F: heals %d%% over %.1f s. Refilled at the Sanctum and at wells." % [roundi(GameState.flask_heal * 100), Tuning.FLASK_TICKS / 60.0]}]
	for k in Tuning.RES_COUNT:
		list.append({name = Tuning.RES_NAMES[k], kind = "Material", color = Tuning.RES_COLORS[k], count = str(GameState.res[k]), desc = Tuning.RES_DESC[k]})
	var cats := [["All", ["Consumable", "Material", "Collectible", "Quest item"]], ["Consumables", ["Consumable"]], ["Materials", ["Material"]],
		["Collectibles", ["Collectible"]], ["Quest items", ["Quest item"]]]
	var chips := HBoxContainer.new()
	for k in cats.size():
		var n := list.filter(func(it): return cats[k][1].has(it.kind)).size()
		var b := UiStyle.button("%s %d" % [cats[k][0], n], 11)
		if k == _item_cat:
			b.add_theme_color_override("font_color", UiStyle.CANDLE)
		b.pressed.connect(func(): _item_cat = k; _sel_item = 0; _key = "")
		chips.add_child(b)
	_page.add_child(chips)
	var shown := list.filter(func(it): return cats[_item_cat][1].has(it.kind))
	var grid := GridContainer.new()
	grid.columns = 9
	for k in 18:
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(56, 56)
		var sb := UiStyle.panel_box(0.6, 4)
		if k < shown.size() and k == _sel_item:
			sb.border_color = UiStyle.CANDLE
		slot.add_theme_stylebox_override("normal", sb)
		slot.add_theme_stylebox_override("hover", sb)
		if k < shown.size():
			var it: Dictionary = shown[k]
			slot.text = it.count
			slot.add_theme_font_size_override("font_size", 10)
			slot.add_theme_color_override("font_color", it.color)
			slot.tooltip_text = it.name
			slot.pressed.connect(func(): _sel_item = k; _key = "")
		grid.add_child(slot)
	_page.add_child(grid)
	if shown.size() > 0:
		var sel: Dictionary = shown[mini(_sel_item, shown.size() - 1)]
		_text("[b]%s[/b]  [color=#9a93a8]%s[/color]\n%s" % [sel.name, sel.kind, sel.desc])
	else:
		_text("[color=#9a93a8]%s[/color]" % ("No collectibles yet. Trinkets and lore found out in the world will be kept here." if _item_cat == 3 else "No quest items yet. Things the locals ask you to find or carry will be kept here."))


func _map() -> void:
	var r := world.room
	_h3("Map")
	if world.in_run():
		_text("You are in [b]%s[/b], %s. %s" % [world.place_name(), r.name, r.blurb])
		var m := Minimap.new()
		m.world = world
		m.box = Vector2(600, 330)
		m.zoom_i = 0
		m.show_title = false
		_page.add_child(m)
		_text("[color=#ffffff]▲[/color] You   [color=#6b80ff]●[/color] Altar   [color=#59d973]●[/color] Shop   [color=#f25952]●[/color] Lounge / safe room   [color=#fac84d]■[/color] Hidden loot   [color=#fad980]∩[/color] Gate (red while shut)   [color=#ff4d40]•[/color] Monster awake   ┅ Not explored yet")
		var route := PackedStringArray()
		for i in world.rooms.size():
			var name := RunPlan.describe(world.rooms[i])
			route.append("[b]%s[/b]" % name if i == world.room_idx else ("[color=#9a93a8]%s[/color]" % name if i < world.room_idx else name))
		_text("The way: " + "  →  ".join(route))
		return
	_text("You are in [b]%s[/b]. %s" % [r.name, r.blurb])
	var wm := WorldMapView.new()
	wm.use_rooms(world.rooms, world.in_run())
	wm.box = Vector2(110, 60)
	wm.gap = Vector2(24, 20)
	wm.label_chars = 0
	wm.font_size = 12
	_page.add_child(wm)
	wm.refresh(world.room_idx)
	_text("[color=#c44a3a]■[/color] Danger   [color=#8c8c78]■[/color] Cleared   [color=#d9a74a]■[/color] Home   [color=#e68c46]■[/color] Forge   [color=#5aaabe]■[/color] Rest & friends   □ Not explored")


func _system() -> void:
	_h3("System")
	var row := HBoxContainer.new()
	var resume := UiStyle.button("Resume")
	resume.pressed.connect(func(): toggle(false); get_tree().paused = false)
	row.add_child(resume)
	var restart := UiStyle.button("Restart run")
	restart.pressed.connect(func(): restart_requested.emit())
	row.add_child(restart)
	var mute := UiStyle.button("Sound: " + ("on" if Sfx.enabled else "off"))
	mute.pressed.connect(func(): Sfx.enabled = not Sfx.enabled; _key = "")
	row.add_child(mute)
	var perf := UiStyle.button("Performance panel")
	perf.pressed.connect(func(): perf_toggled.emit())
	row.add_child(perf)
	_page.add_child(row)
	var vol := HBoxContainer.new()
	vol.add_child(UiStyle.label("Volume", 12, UiStyle.ASH))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Sfx.volume
	slider.custom_minimum_size = Vector2(220, 0)
	slider.value_changed.connect(func(v): Sfx.volume = v; Sfx.play("pick"))
	vol.add_child(slider)
	_page.add_child(vol)
	_h4("Controls")
	_text("WASD move · Mouse aim\nL-click / J  weapon combo · in the air: air swing\nR-click / K  goo spit\nSpace  jump · up one ledge\nShift  dodge · in the air: dive slam\nDodge as a hit lands: perfect dodge\nQ / E  job skills (mana)\nF  flask\nT  use · talk · take\nEsc / Tab  this menu\n, .  or wheel  minimap zoom\n[ ]  camera tilt    - =  zoom\nM  mute    P  pause")
	_text("[color=#9a93a8]Controller: left stick move, right stick aim, X attack, A jump, B dodge, RB / RT spit, LB / LT skills, D-pad down flask, Y use, Start menu.[/color]")
	_h4("Developer")
	_text("`  dev console    F2  performance    H  hitboxes\n1–4  jump to an area (new run)    R  restart    G  god mode")
