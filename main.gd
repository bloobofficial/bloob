extends Node
## Boot + glue (prototype: src/main.ts boot). Wires the World to the camera, HUD and panels,
## and handles the global controls: start card, pause menu, pause, restart, room keys,
## god mode, dev console, mute, hitboxes, performance panel, camera tilt and zoom.

const ROOM_KEYS := ["sanctum", "hollow", "ridge", "proving"]

var started := false
var _suppress_use := 0

@onready var world: World = $World
@onready var camera: GameCamera = $Camera
@onready var hud: Hud = $Hud
@onready var panels: CanvasLayer = $Panels

var shrine: ShrinePanel
var board: BoardPanel
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
	menu = PauseMenu.new()
	menu.world = world
	menu.restart_requested.connect(func(): _close_menu(); restart(Content.START_ROOM))
	menu.perf_toggled.connect(func(): hud.show_perf = not hud.show_perf)
	dev = DevPanel.new()
	dev.world = world
	dev.main = self
	start_card = Cards.start_card()
	death_card = Cards.death_card()
	pause_card = Cards.pause_card()
	for p in [shrine, board, death_card, pause_card, menu, dev, start_card]:
		panels.add_child(p)
	start_card.body.get_node("Begin").pressed.connect(begin)
	world.station_opened.connect(_on_station_opened)
	world.talk.connect(func(i, line, at): hud.show_bubble(world.room.npcs[i].name, line, at))
	world.room_loaded.connect(func(_i): camera.snap.call_deferred(); shrine.close(); board.close())
	world.reset_run(Content.START_ROOM)
	camera.snap()
	start_card.open()


func begin() -> void:
	if started:
		return
	started = true
	start_card.close()
	world.running = true
	world.fx.say(world.room.name, 1.6)


func restart(room_id: String = Content.START_ROOM) -> void:
	world.reset_run(room_id)
	world.fx.reset()
	Engine.time_scale = 1.0
	snap_camera()


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


func _process(_delta: float) -> void:
	death_card.visible = started and world.player.dead
	if world.room.encounter != null and shrine.visible:
		shrine.close()   # the Shrine is a safe-area thing
	# a panel over the game eats T / clicks so they don't also act in the world
	var modal := shrine.visible or board.visible or dev.visible
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
	if event.is_action_pressed(&"dev"):
		dev.toggle()
	elif dev.visible and (event is InputEventKey) and dev.get_viewport().gui_get_focus_owner() is LineEdit:
		return   # typing in the console never drives Bloob
	elif event.is_action_pressed(&"menu"):
		if shrine.visible:
			shrine.close()
		elif board.visible:
			board.close()
		else:
			_open_menu()
	elif event.is_action_pressed(&"use") and (shrine.visible or board.visible):
		shrine.close()
		board.close()
	elif event.is_action_pressed(&"restart"):
		restart(Content.START_ROOM)
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
	else:
		for i in ROOM_KEYS.size():
			if event.is_action_pressed(StringName("room_%d" % (i + 1))):
				restart(ROOM_KEYS[i])
