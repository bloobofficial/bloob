class_name ShrinePanel
extends ModalPanel
## The Shrine (prototype: #altar in page.html + renderAltar in main.ts): spend what you've
## gathered on techs, switch jobs. Safe areas only.

var world: World
var _content: VBoxContainer


func _init() -> void:
	super("Shrine", "Spend what you've gathered. %s to close." % UiStyle.kbd("T"), 720)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	body.add_child(_content)
	GameState.changed.connect(func(): if visible: refresh())


func refresh() -> void:
	UiStyle.clear(_content)
	var rs := PackedStringArray()
	for k in Tuning.RES_COUNT:
		rs.append("%s: [b]%d[/b]" % [Tuning.RES_NAMES[k], GameState.res[k]])
	var res := UiStyle.rich(12)
	res.text = "    ".join(rs)
	_content.add_child(res)
	_content.add_child(section("Job"))
	var jobs := HBoxContainer.new()
	jobs.add_theme_constant_override("separation", 8)
	for j in Content.jobs.size():
		var jd := Content.jobs[j]
		var unlocked := GameState.job_unlocked(j)
		var current := GameState.job == j
		var skills := " + ".join(jd.skills.map(func(s): return s.name))
		var b := UiStyle.button("%s\n%s\nSkills: %s\n%s" % [jd.name, jd.blurb, skills, "Current job" if current else ("Switch" if unlocked else "Locked: buy its tech")], 11)
		b.disabled = current or not unlocked
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(func(): world.switch_job(j))
		jobs.add_child(b)
	_content.add_child(jobs)
	_content.add_child(section("Techs"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for i in Content.techs.size():
		var t := Content.techs[i]
		var why := GameState.tech_blocker(i)
		var status := "Owned" if why == "owned" else Tuning.cost_text(t.cost) + ("" if why == "" else " · " + why)
		var b := UiStyle.button("%s\n%s\n%s" % [t.name, t.desc, status], 11)
		b.disabled = why != ""
		b.custom_minimum_size = Vector2(220, 64)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if why == "owned":
			b.add_theme_color_override("font_disabled_color", UiStyle.OK)
		b.pressed.connect(func(): world.buy_tech(i))
		grid.add_child(b)
	_content.add_child(grid)
