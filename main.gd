extends Node
## Boot + glue (prototype: src/main.ts boot). Wires the World to the camera, HUD and panels,
## and handles the global controls: start card, pause menu, pause, restart, room keys,
## god mode, dev console, mute, hitboxes, performance panel, camera tilt and zoom.
## The game is the run loop (World.start_run); the number keys still open the old hub world
## for testing.

const ROOM_KEYS := ["sanctum", "hollow", "ridge", "proving"]

var started := false
var _suppress_use := 0
var _end_shown := false

@onready var world: World = $World
@onready var camera: GameCamera = $Camera
@onready var hud: Hud = $Hud
@onready var panels: CanvasLayer = $Panels

var shrine: ShrinePanel
var board: BoardPanel
var altar: AltarPanel
var menu: PauseMenu
var dev: DevPanel
var start_card: ModalPanel
var death_card: ModalPanel
var pause_card: ModalPanel


func _ready() -> void:
	camera.world = world
	hud.world = world
	shrine = ShrinePanel.new()
	shrine.world = world
	board = BoardPanel.new()
	board.world = world
	altar = AltarPanel.new()
	altar.world = world
	menu = PauseMenu.new()
	menu.world = world
	menu.restart_requested.connect(func(): _close_menu(); restart())
	menu.perf_toggled.connect(func(): hud.show_perf = not hud.show_perf)
	dev = DevPanel.new()
	dev.world = world
	dev.main = self
	start_card = Cards.start_card()
	death_card = Cards.death_card()
	pause_card = Cards.pause_card()
	for p in [shrine, board, altar, death_card, pause_card, menu, dev, start_card]:
		panels.add_child(p)
	start_card.body.get_node("Begin").pressed.connect(begin)
	death_card.body.get_node("Restart").pressed.connect(func(): restart())
	world.station_opened.connect(_on_station_opened)
	world.talk.connect(func(i, line, at): hud.show_bubble(world.room.npcs[i].name, line, at))
	world.room_loaded.connect(func(_i): camera.snap.call_deferred(); shrine.close(); board.close(); altar.close())
	world.run_won.connect(_show_end.bind(true))
	world.start_run()
	camera.snap()
	start_card.open()


func begin() -> void:
	if started:
		return
	started = true
	start_card.close()
	world.running = true
	world.fx.say(world.room.name, 1.6)


## A new run ("" = the run loop with a fresh seed), or the hub world starting in `room_id`.
func restart(room_id: String = "", seed_value: int = -1) -> void:
	if room_id == "":
		world.start_run(seed_value)
	else:
		world.reset_run(room_id)
	world.fx.reset()
	world.running = started
	Engine.time_scale = 1.0
	_end_shown = false
	death_card.close()
	altar.close()
	snap_camera()
	if started:
		world.fx.say(world.room.name, 1.6)


func snap_camera() -> void:
	camera.snap()


func toggle_pause() -> void:
	if not started or menu.visible:
		return
	get_tree().paused = not get_tree().paused
	pause_card.visible = get_tree().paused


func _open_menu() -> void:
	shrine.close()
	board.close()
	altar.close()
	menu.toggle(true)
	get_tree().paused = true


func _close_menu() -> void:
	menu.toggle(false)
	get_tree().paused = pause_card.visible


func _on_station_opened(kind: int) -> void:
	if kind == 1 and world.room.encounter == null:
		shrine.open()
	elif kind == 2:
		board.open()
	elif kind == 3:
		altar.open()


## the run is over: the tally, and a button to go again
func _show_end(won: bool) -> void:
	if _end_shown:
		return
	_end_shown = true
	Cards.fill_summary(death_card, world, won)
	death_card.open()
	if won:
		world.running = false


func _process(_delta: float) -> void:
	if started and world.player.dead and not _end_shown:
		_show_end(false)
	if (world.phase == World.Phase.COMBAT or world.danger_near()) and (shrine.visible or altar.visible):
		shrine.close()   # the Shrine and altars are safe-area things
		altar.close()
	# a panel over the game eats T / clicks so they don't also act in the world
	var modal := shrine.visible or board.visible or dev.visible or altar.visible or death_card.visible
	if modal:
		_suppress_use = 2
	elif _suppress_use > 0:
		_suppress_use -= 1
	world.player.block_actions = _suppress_use > 0
	# scenery: upright sprites and see-through foliage
	world.terrain.update_scenery(world.player.position)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if menu.visible:
		if event.is_action_pressed(&"menu"):
			_close_menu()
		elif event.is_action_pressed(&"skill_1") or event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_up"):
			menu.cycle(-1)
		elif event.is_action_pressed(&"skill_2") or event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"ui_down"):
			menu.cycle(1)
		elif event.is_action_pressed(&"mute"):
			Sfx.enabled = not Sfx.enabled
		elif event.is_action_pressed(&"dev"):
			dev.toggle()
		get_viewport().set_input_as_handled()
		return
	if not started:
		if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"jump"):
			begin()
			get_viewport().set_input_as_handled()
		return
	if altar.visible:
		# 1 / 2 / 3 pick at an altar (instead of jumping rooms)
		for i in 3:
			if event.is_action_pressed(StringName("room_%d" % (i + 1))):
				altar.choose(i)
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed(&"dev"):
		dev.toggle()
	elif dev.visible and (event is InputEventKey) and dev.get_viewport().gui_get_focus_owner() is LineEdit:
		return   # typing in the console never drives Bloob
	elif event.is_action_pressed(&"menu"):
		if shrine.visible:
			shrine.close()
		elif board.visible:
			board.close()
		elif altar.visible:
			altar.close()
		else:
			_open_menu()
	elif event.is_action_pressed(&"use") and (shrine.visible or board.visible or altar.visible):
		shrine.close()
		board.close()
		altar.close()
	elif event.is_action_pressed(&"restart"):
		restart()
	elif event.is_action_pressed(&"god"):
		world.dev.god = not world.dev.god
		world.player.god = world.dev.god or world.mode.god_mode
	elif event.is_action_pressed(&"pause"):
		toggle_pause()
	elif event.is_action_pressed(&"perf"):
		hud.show_perf = not hud.show_perf
	elif event.is_action_pressed(&"mute"):
		Sfx.enabled = not Sfx.enabled
	elif event.is_action_pressed(&"hitboxes"):
		world.debug_hitboxes = not world.debug_hitboxes
	elif event.is_action_pressed(&"tilt_down"):
		View.set_pitch(View.pitch_deg - 2)
		world.terrain.redraw_all()
	elif event.is_action_pressed(&"tilt_up"):
		View.set_pitch(View.pitch_deg + 2)
		world.terrain.redraw_all()
	elif event.is_action_pressed(&"zoom_out"):
		View.set_view_width(View.view_width + 80)
	elif event.is_action_pressed(&"zoom_in"):
		View.set_view_width(View.view_width - 80)
	elif event.is_action_pressed(&"map_zoom_in"):
		hud.minimap.zoom(1)
	elif event.is_action_pressed(&"map_zoom_out"):
		hud.minimap.zoom(-1)
	else:
		for i in ROOM_KEYS.size():
			if event.is_action_pressed(StringName("room_%d" % (i + 1))):
				restart(ROOM_KEYS[i])
