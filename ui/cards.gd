class_name Cards
extends RefCounted
## The start, death / victory and pause cards (prototype: #start, #death, #paused in page.html).


static func start_card() -> ModalPanel:
	var c := ModalPanel.new("Bloob", "", 640)
	c.closable = false
	var t := UiStyle.rich(13)
	t.text = "Every run is a short path through the wild: [b]fight[/b], choose which [b]passage[/b] to take, find [b]weapons[/b], gain [b]skills[/b] at altars, spend [b]Essence[/b] in shops, rest in a safe room, then face an [b]elite[/b] fight and the [b]Barrow King[/b]. Die, and it all starts over on a new path.\n\n" \
		+ "Rooms seal when a fight starts and open when it's won. Enemies [b]telegraph[/b] every attack: a red zone on the ground and a closing ring. Dodge as it lands for a [b]perfect dodge[/b]. Walk up to weapons, altars, pedestals and wells and press [b]T[/b].\n\n" \
		+ "[b]WASD[/b] move · [b]mouse[/b] aim · [b]L-click / J[/b] weapon combo · [b]R-click / K[/b] goo spit · [b]Space[/b] jump · [b]Shift[/b] dodge (dive slam in the air) · [b]Q / E[/b] job skills · [b]F[/b] flask · [b]Esc[/b] menu · [b]`[/b] dev console.\n\n" \
		+ "[color=#9a93a8]Controller: left stick move, right stick aim, X attack, A jump, B dodge, RB spit, LB / LT skills, Y use, Start menu.[/color]"
	c.body.add_child(t)
	var b := UiStyle.button("Begin the run", 16)
	b.name = "Begin"
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.body.add_child(b)
	return c


## The end of a run (death or victory): the tally and a button to go again.
static func death_card() -> ModalPanel:
	var c := ModalPanel.new("Overrun", "", 520)
	c.closable = false
	var stats := UiStyle.rich(13)
	stats.name = "Stats"
	stats.custom_minimum_size = Vector2(480, 0)
	c.body.add_child(stats)
	var b := UiStyle.button("Restart run", 15)
	b.name = "Restart"
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.body.add_child(b)
	return c


## fill an end-of-run card from the run so far
static func fill_summary(c: ModalPanel, world: World, won: bool) -> void:
	c.title_label.text = "Victory" if won else "Overrun"
	c.sub_label.text = "The Barrow King is dust. The wild remembers nothing." if won else "Bloob melts back into the moss. Everything gathered this run is gone."
	var secs := GameState.run_ticks / 60
	var names := PackedStringArray()
	for id in GameState.passives:
		var pd := Content.passive(id)
		if pd:
			names.append(pd.name)
	var reached := world.room.name if world.room else "?"
	var txt := "Enemies defeated   [b]%d[/b]\nRooms cleared   [b]%d[/b]\nEssence collected   [b]%d[/b]\nSkills   [b]%s[/b]\nWeapon   [b]%s[/b]%s\nRun time   [b]%d:%02d[/b]\n%s\n[color=#9a93a8]Seed %d[/color]" % [
		GameState.kills, GameState.rooms_cleared, GameState.essence_total,
		", ".join(names) if names.size() > 0 else "none",
		GameState.weapon_data().name,
		("  [color=#9a93a8](used: %s)[/color]" % ", ".join(GameState.weapons_used)) if GameState.weapons_used.size() > 1 else "",
		secs / 60, secs % 60,
		"" if won else "Fell in   [b]%s[/b]" % reached,
		world.run.seed_value if world.run else 0]
	(c.body.get_node("Stats") as RichTextLabel).text = txt
	(c.body.get_node("Restart") as Button).text = "New run" if won else "Restart run"


static func pause_card() -> ModalPanel:
	var c := ModalPanel.new("Paused", "Press [b]P[/b] to resume.", 360)
	c.closable = false
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
