extends Node
## Visual check: boots the real game (main.tscn) in a window, optionally jumps to a room and
## scripts a little play, then saves screenshots and quits.
## Run: godot res://tests/capture.tscn -- <room id> <out dir> [scenario]
## Scenarios: idle (default), fight (spawns monsters and swings), menu, shrine

const MAIN := preload("res://main.tscn")


func _ready() -> void:
	_run.call_deferred()


func _shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
	print("saved ", dir.path_join(name + ".png"))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var room := args[0] if args.size() > 0 else "sanctum"
	var dir := args[1] if args.size() > 1 else OS.get_user_data_dir()
	var scenario := args[2] if args.size() > 2 else "idle"
	var main := MAIN.instantiate()
	add_child(main)
	await _frames(5)
	if not Art.ready_done:
		await Art.baked
	if scenario == "start":
		await _frames(20)
		await _shot(dir, "start_card")
		get_tree().quit()
		return
	main.begin()
	if scenario == "map":
		await _map_tour(main, int(room), dir)
		get_tree().quit()
		return
	if scenario == "run":
		await _run_tour(main, int(room), dir)
		get_tree().quit()
		return
	main.restart(room)
	await _frames(40)
	var world: World = main.world
	match scenario:
		"fight":
			world.spawning = false
			var p := world.player
			for i in 3:
				Director.spawn_enemy(world, [0, 1, 5][i], p.position + Vector2(90 + i * 40, -30 + i * 30), p.z, true)
			await _frames(30)
			await _shot(dir, room + "_fight_a")
			var f := InputFrame.new()
			for t in 40:
				f.atk = true
				f.aim = world.enemies[0].position if world.enemies.size() > 0 else p.position + Vector2(50, 0)
				p.scripted = f
				await get_tree().physics_frame
				if t == 9:
					await _shot(dir, room + "_fight_b")
			p.scripted = null
			await _frames(20)
			await _shot(dir, room + "_fight_c")
		"perf", "perf_noemit", "perf_noenemy":
			if scenario == "perf_noemit":
				world.projectiles.emitters.clear()
			if scenario == "perf_noenemy":
				world.spawning = false
				for e in world.enemies.duplicate():
					CombatRules.kill_enemy(world, e, true)
			# let the room run with its director for a while and report frame / physics cost
			world.player.god = true
			var t0 := Time.get_ticks_msec()
			var frames := 0
			var worst := 0.0
			var proc := 0.0
			var phys := 0.0
			while Time.get_ticks_msec() - t0 < 6000:
				await get_tree().process_frame
				frames += 1
				var ph := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
				worst = maxf(worst, ph)
				phys += ph
				proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			print("PERF %s: %.1f fps avg, physics avg %.2f ms worst %.2f ms, process avg %.2f ms, enemies %d, projectiles %d, particles %d" % [
				room, frames / 6.0, phys / frames, worst, proc / frames, world.enemies.size(), world.projectiles.count(), world.fx.particle_count()])
			await _shot(dir, room + "_perf")
		"death":
			world.player.hurt(9999, world.player.position + Vector2(10, 0))
			await _frames(90)
			await _shot(dir, room + "_death")
		"talk":
			var npc = null
			for st in world.stations:
				if st.kind == World.StationKind.NPC:
					npc = st
			world.player.place(npc.pos + Vector2(0, 40), npc.z)
			var f := InputFrame.new()
			f.use = true
			f.aim = npc.pos
			world.player.scripted = f
			await get_tree().physics_frame
			await get_tree().physics_frame
			world.player.scripted = null
			await _frames(20)
			await _shot(dir, room + "_talk")
		"menu":
			main._open_menu()
			await _frames(10)
			await _shot(dir, room + "_menu")
		"shrine":
			main.shrine.open()
			await _frames(10)
			await _shot(dir, room + "_shrine")
		_:
			await _shot(dir, room)
	get_tree().quit()


## "run" scenario: walk a whole run (seed = the room argument) and shoot every room:
## godot res://tests/capture.tscn -- <seed> <out dir> run
func _run_tour(main: Node, seed_value: int, dir: String) -> void:
	main.restart("", seed_value)
	var world: World = main.world
	await _frames(40)
	await _shot(dir, "run_00_start")
	world.player.god = true
	for i in range(1, world.rooms.size()):
		var r := world.rooms[i]
		world.load_room(i, r.entrance)
		world.player.god = true
		await _frames(30)
		var tag := "run_%02d_%s" % [i, r.kind]
		if r.encounter and r.kind == "wilds":
			for e in world.enemies:
				Hunt.wake(world, e)
			await _ticks(60)
			await _shot(dir, tag + "_awake")
			var g := 0
			while not world.doors_open and g < 20:
				for e in world.enemies.duplicate():
					CombatRules.kill_enemy(world, e, false)
				await _frames(10)
				g += 1
			await _frames(50)
			await _shot(dir, tag + "_cleared")
		elif r.encounter:
			Waves.engage(world)
			await _ticks(40)
			await _shot(dir, tag + "_tell")
			await _ticks(100)
			await _shot(dir, tag + "_fight")
			if r.kind == "boss":
				await _ticks(150)
				await _shot(dir, tag + "_fight2")
			var guard := 0
			while not world.doors_open and guard < 80:
				for e in world.enemies.duplicate():
					CombatRules.kill_enemy(world, e, false)
				await _frames(20)
				guard += 1
			await _frames(50)
			await _shot(dir, tag + "_cleared")
		else:
			await _shot(dir, tag)
		if r.kind == "altar" or r.kind == "elite":
			main.altar.open()
			await _frames(10)
			await _shot(dir, tag + "_altar")
			main.altar.close()
	await _frames(60)
	await _shot(dir, "run_99_end")
	world.running = true
	world.player.god = false
	main._end_shown = false
	world.player.hurt(9999, world.player.position + Vector2(10, 0))
	await _frames(90)
	await _shot(dir, "run_99_death")


## "map" scenario: a run's first map (seed = the room argument): the start, then a stop in
## every area, a fight in a glade, and the minimap at each zoom:
## godot res://tests/capture.tscn -- <seed> <out dir> map
func _map_tour(main: Node, seed_value: int, dir: String) -> void:
	var t0 := Time.get_ticks_msec()
	main.restart("", seed_value)
	print("PERF new run + first map: %d ms" % (Time.get_ticks_msec() - t0))
	var world: World = main.world
	await _frames(40)
	# frame cost while standing in the start clearing
	var ph := 0.0
	var pr := 0.0
	var frames := 0
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 3000:
		await get_tree().process_frame
		frames += 1
		ph += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		pr += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	print("PERF map: %.1f fps (software renderer), physics %.2f ms, process %.2f ms, nodes %d" % [frames / 3.0, ph / frames, pr / frames, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	await _shot(dir, "map_00_start")
	world.player.god = true
	var C := float(Tuning.CELL)
	var k := 1
	for a in world.room.areas:
		var at := world.free_spot(Vector2((a.cell.x + 0.5) * C, (a.cell.y + 2.5) * C))
		world.player.place(at, world.map.ground_at(at.x, at.y))
		main.snap_camera()
		await _ticks(30)
		await _shot(dir, "map_%02d_%s" % [k, a.kind])
		k += 1
	# wake a glade and fight
	for e in world.enemies:
		if e.alive:
			world.player.place(e.position + Vector2(0, 150), e.z)
			main.snap_camera()
			break
	await _ticks(90)
	await _shot(dir, "map_%02d_fight" % k)
	for zi in 3:
		main.hud.minimap.zoom_i = zi
		await _frames(3)
		await _shot(dir, "map_zoom_%d" % zi)
	main._open_menu()
	main.menu.show_tab(PauseMenu.TABS.find("Map"))
	await _frames(5)
	await _shot(dir, "map_menu")


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
