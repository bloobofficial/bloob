class_name Hud
extends CanvasLayer
## The HUD (prototype: src/page.html + the HUD half of src/main.ts), as native Controls:
##  top left: area name, objective, resources   top right: world map
##  bottom left: vitals (level, job, status, HP with damage-lag + heal preview, MP, XP)
##  bottom centre: time state, toast, kit (weapon + combo pips, skills, flask, dodge)
##  bottom right: key hints     centre: banner     over locals: speech bubbles
##  screen overlays: hit flash, slow-mo vignette, room fade

const SAFE_LABEL := {
	hub = "Safe · home. The Sanctum mends you", shop = "Safe · wares for sale",
	social = "Safe · friends and the notice board", rest = "Safe · a well and a Shrine",
	explore = "Safe · look around", training = "Safe · practice ground",
	start = "Safe · take up a weapon, then go on", altar = "Safe · an altar offers skills",
	weapon = "Safe · a weapon waits", event = "Safe · a cache of Essence", safe = "Safe · the well mends you once",
}

var world: World
var show_perf := false

var _flash: ColorRect
var _slowmo: TextureRect
var _fade: ColorRect
var _banner: Label
var _room_name: Label
var _objective: Label
var _res: Label
var _sub: Label
var minimap: Minimap
var _lvl: Label
var _job: Label
var _status: Label
var _hp: Meter
var _hp_text: Label
var _mp: Meter
var _mp_text: Label
var _xp: Meter
var _timestate: Label
var _toast: Label
var _weapon_icon: TextureRect
var _weapon_name: Label
var _pips: HBoxContainer
var _skills: Array = []      ## [{box, name, mp, cd: Meter}]
var _flask: Label
var _dodge: Label
var _prompt: RichTextLabel
var _prompt_box: PanelContainer
var _bubble: PanelContainer
var _bubble_name: Label
var _bubble_text: Label
var _bubble_at := Vector3.ZERO
var _bubble_until := 0
var _perf: Label
var _boss_box: VBoxContainer
var _boss_name: Label
var _boss_hp: Meter
var _hp_lag := 1.0
var _shown_weapon := -1
var _slow_alpha := 0.0


func _ready() -> void:
	layer = 5
	_build()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# overlays
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	root.add_child(_flash)
	_slowmo = TextureRect.new()
	_slowmo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slowmo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slowmo.texture = _vignette_texture()
	_slowmo.stretch_mode = TextureRect.STRETCH_SCALE
	_slowmo.modulate.a = 0.0
	root.add_child(_slowmo)
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.color = Color(UiStyle.DUSK, 0)
	root.add_child(_fade)
	_banner = UiStyle.label("", 34)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.anchor_top = 0.26
	_banner.anchor_bottom = 0.26
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_banner.add_theme_constant_override("outline_size", 6)
	root.add_child(_banner)
	# top left
	var tl := VBoxContainer.new()
	tl.position = Vector2(16, 14)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tl)
	_room_name = UiStyle.label("Sanctum", 30)
	_room_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_room_name.add_theme_constant_override("outline_size", 4)
	tl.add_child(_room_name)
	_sub = UiStyle.label("THE BLOOB", 9, UiStyle.ASH)
	tl.add_child(_sub)
	_objective = UiStyle.label("", 11, UiStyle.ASH)
	tl.add_child(_objective)
	_res = UiStyle.label("", 11)
	tl.add_child(_res)
	# minimap (top right)
	var mm := UiStyle.panel(0.7)
	mm.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mm.position = Vector2(-16, 14)
	mm.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	minimap = Minimap.new()
	minimap.box = Vector2(236, 170)
	mm.add_child(minimap)
	root.add_child(mm)
	# vitals (bottom left)
	var vit := UiStyle.panel()
	vit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	vit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	vit.position = Vector2(16, -16)
	vit.custom_minimum_size = Vector2(290, 0)
	root.add_child(vit)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vit.add_child(vb)
	var who := HBoxContainer.new()
	_lvl = UiStyle.label("1", 18, UiStyle.CANDLE)
	_lvl.custom_minimum_size = Vector2(28, 0)
	_lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.add_child(_lvl)
	var wt := VBoxContainer.new()
	wt.add_theme_constant_override("separation", 0)
	wt.add_child(UiStyle.label("Bloob", 13))
	_job = UiStyle.label("Brawler", 10, UiStyle.ASH)
	wt.add_child(_job)
	who.add_child(wt)
	_status = UiStyle.label("", 10, UiStyle.CANDLE)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	who.add_child(_status)
	vb.add_child(who)
	var hp_row := _meter_row("HP", UiStyle.BLOOD)
	_hp = hp_row[0]
	_hp_text = hp_row[1]
	vb.add_child(hp_row[2])
	var mp_row := _meter_row("MP", Color(0.45, 0.6, 1.0))
	_mp = mp_row[0]
	_mp_text = mp_row[1]
	vb.add_child(mp_row[2])
	_xp = Meter.new()
	_xp.fill_color = UiStyle.CANDLE
	_xp.custom_minimum_size = Vector2(0, 3)
	vb.add_child(_xp)
	# bottom centre: time state, toast, kit
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position = Vector2(0, -16)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	_timestate = UiStyle.label("", 11, UiStyle.CANDLE)
	_timestate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(_timestate)
	_toast = UiStyle.label("", 11, UiStyle.CANDLE)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(_toast)
	var kit := UiStyle.panel()
	kit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(kit)
	var kh := HBoxContainer.new()
	kh.add_theme_constant_override("separation", 10)
	kit.add_child(kh)
	var wslot := HBoxContainer.new()
	_weapon_icon = TextureRect.new()
	_weapon_icon.custom_minimum_size = Vector2(40, 40)
	_weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wslot.add_child(_weapon_icon)
	var wtext := VBoxContainer.new()
	_weapon_name = UiStyle.label("Goo Paws", 12)
	wtext.add_child(_weapon_name)
	_pips = HBoxContainer.new()
	_pips.add_theme_constant_override("separation", 3)
	wtext.add_child(_pips)
	wslot.add_child(wtext)
	kh.add_child(wslot)
	for k in 2:
		var sk := VBoxContainer.new()
		sk.custom_minimum_size = Vector2(92, 0)
		var top := HBoxContainer.new()
		top.add_child(UiStyle.label("Q" if k == 0 else "E", 11, UiStyle.CANDLE))
		var nm := UiStyle.label("", 12)
		top.add_child(nm)
		sk.add_child(top)
		var mp := UiStyle.label("", 10, UiStyle.ASH)
		sk.add_child(mp)
		var cd := Meter.new()
		cd.fill_color = Color(0.94, 0.9, 0.82, 0.5)
		cd.custom_minimum_size = Vector2(0, 3)
		sk.add_child(cd)
		kh.add_child(sk)
		_skills.append({box = sk, name = nm, mp = mp, cd = cd})
	var fl := VBoxContainer.new()
	fl.add_child(UiStyle.label("F  flask", 11, UiStyle.CANDLE))
	_flask = UiStyle.label("", 14, Color("#f5c95a"))
	fl.add_child(_flask)
	kh.add_child(fl)
	_dodge = UiStyle.label("dodge", 12)
	_dodge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kh.add_child(_dodge)
	# key hints (bottom right)
	var hint := UiStyle.label("Esc menu    T use    ` dev", 11, UiStyle.ASH)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.position = Vector2(-16, -16)
	root.add_child(hint)
	# interaction prompt
	_prompt_box = UiStyle.panel(0.9)
	_prompt_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt_box.position = Vector2(0, -118)
	_prompt_box.visible = false
	_prompt = UiStyle.rich(13)
	_prompt.custom_minimum_size = Vector2(420, 0)
	_prompt_box.add_child(_prompt)
	root.add_child(_prompt_box)
	# speech bubble
	_bubble = PanelContainer.new()
	var bsb := UiStyle.panel_box(0.96)
	bsb.bg_color = Color(239 / 255.0, 230 / 255.0, 210 / 255.0, 0.96)
	_bubble.add_theme_stylebox_override("panel", bsb)
	_bubble.custom_minimum_size = Vector2(200, 0)
	var bv := VBoxContainer.new()
	_bubble_name = UiStyle.label("", 10, Color("#7a4d1c"))
	bv.add_child(_bubble_name)
	_bubble_text = UiStyle.label("", 12, Color("#1d1822"))
	_bubble_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_text.custom_minimum_size = Vector2(240, 0)
	bv.add_child(_bubble_text)
	_bubble.add_child(bv)
	_bubble.visible = false
	root.add_child(_bubble)
	# boss health (top centre)
	_boss_box = VBoxContainer.new()
	_boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_boss_box.offset_left = -260
	_boss_box.offset_right = 260
	_boss_box.offset_top = 18
	_boss_box.custom_minimum_size = Vector2(520, 0)
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_name = UiStyle.label("", 16, Color(0.9, 0.7, 1.0))
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_boss_name.add_theme_constant_override("outline_size", 4)
	_boss_box.add_child(_boss_name)
	_boss_hp = Meter.new()
	_boss_hp.fill_color = Color(0.75, 0.3, 0.95)
	_boss_hp.custom_minimum_size = Vector2(520, 10)
	_boss_box.add_child(_boss_hp)
	_boss_box.visible = false
	root.add_child(_boss_box)
	# performance panel (F2)
	_perf = UiStyle.label("", 10)
	_perf.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_perf.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_perf.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_perf.position = Vector2(-16, -44)
	_perf.visible = false
	root.add_child(_perf)


func _meter_row(tag: String, col: Color) -> Array:
	var row := HBoxContainer.new()
	row.add_child(UiStyle.label(tag, 10, UiStyle.ASH))
	var m := Meter.new()
	m.fill_color = col
	m.custom_minimum_size = Vector2(0, 9)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(m)
	var t := UiStyle.label("", 10)
	t.custom_minimum_size = Vector2(70, 0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(t)
	return [m, t, row]


func _vignette_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.add_point(0.55, Color(0.16, 0.09, 0.03, 0.0))
	g.set_color(g.get_point_count() - 1, Color(0.05, 0.02, 0.01, 0.85))
	g.add_point(0.8, Color(0.16, 0.09, 0.03, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 1.0)
	t.width = 256
	t.height = 256
	return t


func show_bubble(npc_name: String, line: String, at: Vector3) -> void:
	_bubble_name.text = npc_name.to_upper()
	_bubble_text.text = line
	_bubble_at = at
	_bubble_until = Time.get_ticks_msec() + 5200
	_bubble.visible = true


func _process(_delta: float) -> void:
	if world == null:
		return
	var p := world.player
	var fx := world.fx
	# overlays
	_flash.color = Color(fx.flash_col, fx.flash)
	var slow_target := maxf(0.85 if world.time.slowmo > 0 else 0.0, fx.vignette * 0.6)
	_slowmo.modulate.a = slow_target
	var exit_fade := 1.0 - float(world.exit_t) / Tuning.EXIT_TICKS if world.exit_t > 0 else 0.0
	_fade.color = Color(UiStyle.DUSK, minf(1.0, maxf(fx.fade, exit_fade)))
	_banner.text = fx.banner
	_banner.modulate.a = clampf(fx.banner_t * 3.0, 0.0, 1.0)
	_toast.text = fx.toast
	_toast.modulate.a = 1.0 if fx.toast_t > 0.0 else 0.0
	_timestate.text = "HITSTOP" if world.time.hitstop > 0 else ("SLOW-MO" if world.time.slowmo > 0 else "")
	# vitals
	var hp_frac := maxf(0.0, p.hp / maxf(1.0, p.max_hp))
	_hp_lag = hp_frac if _hp_lag < hp_frac else _hp_lag + (hp_frac - _hp_lag) * 0.06
	_hp.value = hp_frac
	_hp.lag = _hp_lag
	_hp.heal = (p.hp + p.heal_left) / maxf(1.0, p.max_hp)
	_hp.pulse = hp_frac < 0.3 and not p.dead
	_hp.queue_redraw()
	_hp_text.text = "%d / %d%s" % [ceili(p.hp), p.max_hp, " · god" if p.god else ""]
	_mp.value = p.mana / maxf(1.0, p.max_mana)
	_mp.queue_redraw()
	_mp_text.text = "%d / %d" % [floori(p.mana), p.max_mana]
	_xp.value = 1.0 if GameState.level >= Tuning.MAX_LEVEL else float(GameState.xp) / Tuning.xp_to_next(GameState.level)
	_xp.queue_redraw()
	_lvl.text = str(GameState.level)
	var job := GameState.job_data()
	_job.text = job.name
	var st := PackedStringArray()
	if p.rally_t > 0: st.append("Rally %ds" % ceili(p.rally_t / 60.0))
	if p.guard_t > 0: st.append("Guard %ds" % ceili(p.guard_t / 60.0))
	if p.buff > 0: st.append("Empowered %ds" % ceili(p.buff / 60.0))
	if p.heal_left > 0: st.append("Mending")
	if GameState.haste_t > 0: st.append("Bloodrush")
	_status.text = "  ".join(st)
	# kit
	var w := GameState.weapon
	if w != _shown_weapon:
		_shown_weapon = w
		var wd := GameState.weapon_data()
		_weapon_name.text = wd.name
		_weapon_icon.tooltip_text = "%s: %s" % [wd.name, wd.traits]
		UiStyle.clear(_pips)
		for k in wd.combo.size():
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(10, 4)
			_pips.add_child(pip)
	_weapon_icon.texture = Art.frame(GameState.weapon_data().sprite)
	var lit := p.melee.atk_step if p.melee.swinging() or p.melee.combo_window > 0 else 0
	for k in _pips.get_child_count():
		(_pips.get_child(k) as ColorRect).color = UiStyle.CANDLE if k < lit else Color(0.94, 0.9, 0.82, 0.2)
	for k in 2:
		var sd: SkillData = job.skills[k]
		var ui: Dictionary = _skills[k]
		ui.name.text = sd.name
		ui.mp.text = "%d MP" % sd.mana
		var cd_max := maxi(1, roundi(sd.cooldown * GameState.cd_mul))
		ui.cd.value = float(p.skill_cd[k]) / cd_max
		ui.cd.queue_redraw()
		var ready: bool = p.skill_cd[k] == 0 and p.mana >= sd.mana
		ui.box.modulate = Color(1, 1, 1, 1.0 if ready else 0.5)
		ui.box.tooltip_text = "%s (%d mana)" % [sd.desc, sd.mana]
	_flask.text = "●".repeat(GameState.flask) + "○".repeat(maxi(0, GameState.flask_max - GameState.flask))
	_dodge.modulate = Color(1, 1, 1, 1.0 if p.dodge_cd == 0 else 0.35)
	# top left
	minimap.world = world
	_room_name.text = world.place_name()
	var wilds: bool = world.room.kind == "wilds"
	if wilds:
		_sub.text = "MAP %d OF %d  ·  %s" % [world.room.map_no + 1, RunPlan.MAPS, world.room.name.to_upper()]
	elif world.in_run():
		_sub.text = "THE LAST GATE  ·  %s" % world.room.name.to_upper()
	else:
		_sub.text = "THE BLOOB · HUB WORLD"
	var rem := world.remaining()
	var obj: String
	if wilds and not world.room_state().cleared:
		var awake := Hunt.awake(world)
		obj = "Hunt · %d of %d monsters remain%s" % [rem, world.budget(), " · %d awake" % awake if awake > 0 else " · the gate opens when they fall"]
	elif wilds:
		obj = "The gate is open · go on when you're ready" if not world.run_over else "The run is won"
	elif world.room.encounter == null:
		obj = SAFE_LABEL.get(world.room.kind, "Safe")
	elif world.encounter == null or world.room_state().cleared:
		obj = "Cleared · passages open" if not world.run_over else "The run is won"
	elif world.phase == World.Phase.ENTERED:
		obj = "Something stirs…"
	elif rem < 0:
		obj = "Endless · passages stay open"
	elif world.room.waves.size() > 1:
		obj = "Passages sealed · wave %d of %d · %d left" % [world.wave + 1, world.room.waves.size(), rem]
	else:
		obj = "Passages sealed · %d left" % rem
	_objective.text = obj
	_objective.add_theme_color_override("font_color", UiStyle.BLOOD if not world.doors_open and (not wilds or Hunt.awake(world) > 0) else UiStyle.ASH)
	if world.in_run():
		_res.text = "Essence %d" % GameState.essence
		_res.add_theme_color_override("font_color", Tuning.ESSENCE_COLOR)
	else:
		var rs := PackedStringArray()
		for k in Tuning.RES_COUNT:
			rs.append("%s %d" % [Tuning.RES_NAMES[k], GameState.res[k]])
		_res.text = "   ".join(rs)
		_res.add_theme_color_override("font_color", UiStyle.BONE)
	_update_boss()
	_update_prompt()
	_update_bubble()
	_perf.visible = show_perf
	if show_perf:
		_perf.text = "fps %d\nenemies %d\nprojectiles %d\nparticles %d\npickups %d\nhitstop budget %.1f / 18\naudio voices %d\ntick %d\ncamera %.0f° · %.0f wide" % [
			Engine.get_frames_per_second(), world.enemies.size(), world.projectiles.count(), fx.particle_count(), world.pickups.size(),
			world.time.budget, Sfx.active_voices(), world.tick_n, View.pitch_deg, View.view_width]


func _update_prompt() -> void:
	var p := world.player
	var html := ""
	var blocked: bool = get_tree().paused or not world.running
	if not blocked and not p.dead and world.exit_t == 0:
		var k := world.nearest_station(p.position)
		var T := UiStyle.kbd("T")
		if k >= 0:
			var s: Dictionary = world.stations[k]
			match s.kind:
				World.StationKind.SHRINE: html = "%s Shrine [color=#9a93a8]techs and jobs[/color]" % T
				World.StationKind.WELL: html = "%s Well [color=#9a93a8]mend and refill flasks[/color]" % T
				World.StationKind.BOARD: html = "%s Notice board [color=#9a93a8]your tally[/color]" % T
				World.StationKind.CACHE: html = "%s Open the cache" % T
				World.StationKind.NPC:
					var npc: NpcData = world.room.npcs[s.ref] if s.ref < world.room.npcs.size() else null
					html = "%s Talk to %s" % [T, npc.name if npc else "them"]
				World.StationKind.ALTAR: html = "%s Altar [color=#9a93a8]choose one of three skills[/color]" % T
				World.StationKind.DROP:
					var wd: WeaponData = Content.weapons[s.ref]
					html = "%s Pick up the %s%s\n[color=#9a93a8]%s · reach %d · %.1f per combo[/color]" % [T, wd.name,
						" [color=#9a93a8](drops your %s)[/color]" % GameState.weapon_data().name if GameState.weapon > 0 else "", wd.traits, wd.reach(), wd.combo_damage()]
				World.StationKind.OFFER:
					var o: Dictionary = s.offer
					var can: bool = GameState.essence >= o.price
					var what := ""
					match o.type:
						"weapon":
							var wd: WeaponData = Content.weapons[o.ref]
							what = "%s\n[color=#9a93a8]%s[/color]" % [wd.name, wd.traits]
						"skill":
							var pd := Content.passive(o.ref)
							what = "Skill: %s\n[color=#9a93a8]%s[/color]" % [pd.name, pd.desc]
						"heal":
							what = "Heal %d%% HP" % roundi(float(o.ref) * 100)
					html = "%s Buy %s  [color=%s]%d Essence[/color]" % [T, what, "#b98cff" if can else "#e0453a", o.price]
				World.StationKind.RACK, World.StationKind.REWARD:
					var wd: WeaponData = Content.weapons[s.ref]
					var stats := "\n[color=#9a93a8]%s · reach %d · %.1f per combo[/color]" % [wd.traits, wd.reach(), wd.combo_damage()]
					if s.kind == World.StationKind.REWARD:
						html = "%s Take the %s%s%s" % [T, wd.name, " [color=#9a93a8](a spare: breaks into Relic Shards)[/color]" if GameState.weapons[s.ref] else "", stats]
					elif GameState.weapon == s.ref:
						html = "%s [color=#9a93a8]in hand[/color]%s" % [wd.name, stats]
					elif GameState.weapons[s.ref]:
						html = "%s Take the %s%s" % [T, wd.name, stats]
					else:
						var can := GameState.can_afford(wd.cost)
						html = "%s Buy the %s [color=%s]%s[/color]%s" % [T, wd.name, "#d9a74a" if can else "#e0453a", Tuning.cost_text(wd.cost), stats]
		elif not world.doors_open and world.room.kind == "wilds":
			for d in world.map.doors:
				if Vector2(d.cx, d.cy).distance_to(p.position) < 160 and world.room.doors.has(d.id):
					html = "The gate is shut [color=#9a93a8]· %d monsters still roam this wood[/color]" % world.remaining()
					break
		elif world.doors_open:
			# near an open passage: say where it leads
			for d in world.map.doors:
				if Vector2(d.cx, d.cy).distance_to(p.position) > 120:
					continue
				var link = world.room.doors.get(d.id)
				if link:
					var to := world.rooms[world.room_index_of(link[0])]
					if world.in_run():
						html = "Onward: [b]%s[/b]" % RunPlan.describe(to)
					else:
						html = "To %s [color=#9a93a8]%s[/color]" % [to.name, "danger" if to.kind == "combat" or to.kind == "elite" else "safe"]
				break
	_prompt_box.visible = html != ""
	if _prompt.text != html:
		_prompt.text = "[center]%s[/center]" % html if html != "" else ""


func _update_bubble() -> void:
	if not _bubble.visible:
		return
	var p := world.player
	if Time.get_ticks_msec() > _bubble_until or Vector2(_bubble_at.x, _bubble_at.y).distance_to(p.position) > 200 or world.exit_t > 0:
		_bubble.visible = false
		return
	var wp := View.to_world(Vector2(_bubble_at.x, _bubble_at.y), _bubble_at.z + 64.0)
	var sp := world.get_viewport().get_canvas_transform() * wp
	_bubble.position = sp - Vector2(_bubble.size.x / 2.0, _bubble.size.y)


## the boss's health across the top of the screen while it lives
func _update_boss() -> void:
	var boss: Enemy = null
	for e in world.enemies:
		if e.alive and e.data.boss:
			boss = e
			break
	_boss_box.visible = boss != null
	if boss == null:
		return
	_boss_name.text = boss.data.name + ("  ·  enraged" if boss.enraged else "")
	_boss_hp.value = maxf(0.0, boss.hp / maxf(1.0, boss.max_hp))
	_boss_hp.lag = 0.0
	_boss_hp.queue_redraw()
