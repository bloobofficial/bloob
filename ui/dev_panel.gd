class_name DevPanel
extends PanelContainer
## The developer console (prototype: render/devpanel.ts + sim/dev.ts), opened with `.
## Type `help` for the command list. Overrides live in World.dev (World.DevState).

var world: World
var main: Node
var _log: RichTextLabel
var _input: LineEdit


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_stylebox_override("panel", UiStyle.panel_box(0.94))
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	custom_minimum_size = Vector2(380, 0)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_left = -396
	offset_right = -16
	offset_top = 14
	offset_bottom = -16
	var v := VBoxContainer.new()
	add_child(v)
	v.add_child(UiStyle.label("Dev console", 16, UiStyle.CANDLE))
	var toggles := HFlowContainer.new()
	for t in [["god", "god"], ["no cooldowns", "nocd"], ["freeze AI", "freeze"], ["passive", "passive"], ["hitboxes", "hitbox"],
			["AI states", "states"], ["kill all", "kill"], ["clear room", "clear"], ["heal", "heal"], ["+500 all", "give all 500"], ["all weapons", "weapons"]]:
		var b := UiStyle.button(t[0], 10)
		b.pressed.connect(run.bind(t[1]))
		toggles.add_child(b)
	v.add_child(toggles)
	_log = UiStyle.rich(10)
	_log.fit_content = false
	_log.scroll_active = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.mouse_filter = Control.MOUSE_FILTER_STOP
	v.add_child(_log)
	_input = LineEdit.new()
	_input.placeholder_text = "command (help)"
	_input.text_submitted.connect(func(t): run(t); _input.clear())
	v.add_child(_input)
	visible = false


func toggle() -> void:
	visible = not visible
	if visible:
		_input.grab_focus()
		if _log.text == "":
			log_line("Type [b]help[/b] for the command list.")
	else:
		_input.release_focus()


func log_line(t: String) -> void:
	_log.append_text(t + "\n")


func run(line: String) -> void:
	var a := line.strip_edges().split(" ", false)
	if a.is_empty():
		return
	log_line("[color=#9a93a8]> %s[/color]" % line)
	var c := a[0].to_lower()
	var args := a.slice(1)
	var dev := world.dev
	var num := func(i: int, fallback: float) -> float: return float(args[i]) if args.size() > i and args[i].is_valid_float() else fallback
	var onoff := func(i: int, current: bool) -> bool:
		if args.size() <= i:
			return not current
		return args[i] in ["on", "1", "true", "yes"]
	match c:
		"help", "?":
			log_line("spawn <kind 0-5 or name> [count] [champ] [affix]\nkill · clear · doors open|close · director on|off\nrate <x> · max <n|room> · budget <n|endless|room> · threat <n>\nchamp <pct|auto> · patterns on|off|auto · freeze · passive\nespeed <x> · edmg <x> · ehp <x> · god · nocd · flask · dmg <x>\nheal · level <n> · give <res 0-3|all> <n> · techs [reset]\nweapon <id> · weapons · tp (to the cursor) · room <id> · newrun <id>\nrun [seed] · rooms · next · essence <n> · skill <id>\nforget · speed <x> · pause · step <n> · hitbox · states · perf · cls")
		"spawn":
			var kind := 0
			if args.size() > 0:
				kind = int(args[0]) if args[0].is_valid_int() else Content.ENEMY_ORDER.find(args[0].to_lower())
			if kind < 0 or kind > 5:
				log_line("[color=#e0453a]unknown kind[/color]")
				return
			var n := int(num.call(1, 1))
			var at := world.aim_ground(world.player.z)
			if not world.map.walkable(at.x, at.y):
				var oc := world.map.nearest_open(at.x, at.y)
				at = Vector2((oc.x + 0.5) * Tuning.CELL, (oc.y + 0.5) * Tuning.CELL)
			for i in n:
				var p := at + Vector2(randf_range(-20, 20), randf_range(-20, 20))
				var e := Director.spawn_enemy(world, kind, p, world.map.ground_at(at.x, at.y), true)
				if e and args.size() > 2 and args[2] == "champ":
					e.champ = true
					e.affix = Tuning.AFFIX_BITS[Tuning.AFFIX_NAMES.map(func(x): return x.to_lower()).find(args[3].to_lower())] if args.size() > 3 else 1
			log_line("Spawned %d %s." % [n, Content.ENEMY_ORDER[kind]])
		"kill":
			for e in world.enemies.duplicate():
				CombatRules.kill_enemy(world, e, args.size() > 0 and args[0] == "silent")
		"clear":
			world.spawned = world.budget()
			for e in world.enemies.duplicate():
				CombatRules.kill_enemy(world, e, true)
		"doors":
			world.doors_open = args.size() == 0 or args[0] == "open"
		"director": dev.director = onoff.call(0, dev.director)
		"rate": dev.spawn_mul = num.call(0, 1.0)
		"max": dev.max_alive = -1 if args.size() == 0 or args[0] in ["room", "default"] else int(num.call(0, -1))
		"budget": dev.budget = 0 if args.size() > 0 and args[0] == "endless" else (-1 if args.size() == 0 or args[0] in ["room", "default"] else int(num.call(0, -1)))
		"threat": world.threat = int(num.call(0, world.threat))
		"champ": dev.champ_chance = -1.0 if args.size() > 0 and args[0] == "auto" else num.call(0, 10) / 100.0
		"patterns": dev.patterns = -1 if args.size() > 0 and args[0] == "auto" else (1 if onoff.call(0, true) else 0)
		"freeze": dev.freeze_ai = onoff.call(0, dev.freeze_ai)
		"passive": dev.passive = onoff.call(0, dev.passive)
		"espeed": dev.enemy_speed = num.call(0, 1.0)
		"edmg": dev.enemy_damage = num.call(0, 1.0)
		"ehp": dev.enemy_hp = num.call(0, 1.0)
		"god":
			dev.god = onoff.call(0, dev.god)
			world.player.god = dev.god or world.mode.god_mode
		"nocd": dev.no_cooldowns = onoff.call(0, dev.no_cooldowns)
		"flask": dev.infinite_flask = onoff.call(0, dev.infinite_flask)
		"dmg": dev.player_damage = num.call(0, 1.0)
		"heal":
			world.player.hp = world.player.max_hp
			world.player.mana = world.player.max_mana
		"level":
			var lv := clampi(int(num.call(0, GameState.level)), 1, Tuning.MAX_LEVEL)
			GameState.level = lv
			GameState.xp = 0
			GameState.recompute()
			world.player.max_hp = GameState.max_hp
			world.player.hp = world.player.max_hp
			GameState.changed.emit()
		"give":
			var n := int(num.call(1, 100))
			if args.size() > 0 and args[0] == "all":
				for k in Tuning.RES_COUNT:
					GameState.add_res(k, n)
			else:
				GameState.add_res(int(num.call(0, 0)), n)
		"techs":
			for i in Content.techs.size():
				GameState.techs[i] = 0 if args.size() > 0 and args[0] == "reset" else 1
			GameState.recompute()
			world.player.max_hp = GameState.max_hp
			GameState.changed.emit()
		"weapon":
			var w := Content.weapon_index(args[0]) if args.size() > 0 else -1
			if w >= 0:
				GameState.weapons[w] = 1
				world.equip(w)
		"weapons":
			for i in Content.weapons.size():
				GameState.weapons[i] = 1
			GameState.changed.emit()
		"tp":
			var at := world.aim_ground(world.player.z)
			if not world.map.walkable(at.x, at.y):
				var oc := world.map.nearest_open(at.x, at.y)
				at = Vector2((oc.x + 0.5) * Tuning.CELL, (oc.y + 0.5) * Tuning.CELL)
			world.player.place(at, world.map.ground_at(at.x, at.y))
		"room":
			if args.size() > 0:
				world.load_room(world.room_index_of(args[0]), "C" if world.in_run() else "")
				main.snap_camera()
		"rooms":
			for i in world.rooms.size():
				log_line("%d  %s  [color=#9a93a8]%s[/color]" % [i, world.rooms[i].id, world.rooms[i].name])
		"next":
			# jump to the first way onward from this room (runs)
			var ways := world.room.doors.values()
			if ways.size() > 0:
				world.load_room(world.room_index_of(ways[0][0]), ways[0][1])
				main.snap_camera()
		"newrun":
			main.restart(args[0] if args.size() > 0 else Content.START_ROOM)
		"run":
			main.restart("", int(args[0]) if args.size() > 0 and args[0].is_valid_int() else -1)
			log_line("Run seed %d" % world.run.seed_value)
		"essence":
			GameState.add_essence(int(num.call(0, 50)))
		"skill":
			if args.size() > 0 and Content.passive(args[0]) != null:
				world.take_passive(args[0])
			else:
				log_line(", ".join(Content.passives.map(func(p): return p.id)))
		"forget":
			for st in GameState.room_states:
				st.cleared = false
				st.taken = 0
		"speed": Engine.time_scale = clampf(num.call(0, 1.0), 0.1, 8.0)
		"pause": main.toggle_pause()
		"step":
			for i in int(num.call(0, 1)):
				world.step()
		"hitbox", "hitboxes": world.debug_hitboxes = onoff.call(0, world.debug_hitboxes)
		"states": world.debug_states = onoff.call(0, world.debug_states)
		"perf": main.hud.show_perf = onoff.call(0, main.hud.show_perf)
		"cls": _log.clear()
		_:
			log_line("[color=#e0453a]Unknown command \"%s\". Type help.[/color]" % c)
