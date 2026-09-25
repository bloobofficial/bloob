class_name BoardPanel
extends ModalPanel
## The notice board (prototype: #board + renderBoard): the run's tally and which weapons
## you've found (with hints for the missing ones).

var world: World
var _content: RichTextLabel


func _init() -> void:
	super("Notice board", "Your tally this run. %s to close." % UiStyle.kbd("T"), 560)
	_content = UiStyle.rich(12)
	body.add_child(_content)


func _process(_delta: float) -> void:
	if visible:
		refresh()


func refresh() -> void:
	var combat := []
	var mapped := []
	for i in Content.rooms.size():
		var r := Content.rooms[i]
		if r.on_map:
			mapped.append(i)
			if r.encounter:
				combat.append(i)
	var cleared := combat.filter(func(i): return GameState.room_states[i].cleared).size()
	var seen := mapped.filter(func(i): return GameState.room_states[i].visited).size()
	var secs := GameState.run_ticks / 60
	var techs := 0
	for t in GameState.techs:
		techs += t
	var txt := "Level [b]%d[/b]      Defeated [b]%d[/b]      Areas cleared [b]%d / %d[/b]\nPlaces found [b]%d / %d[/b]      Techs [b]%d / %d[/b]      Time [b]%d:%02d[/b]\n\n[color=#d9a74a]WEAPONS[/color]\n" % [
		GameState.level, GameState.kills, cleared, combat.size(), seen, mapped.size(), techs, Content.techs.size(), secs / 60, secs % 60]
	for w in Content.weapons.size():
		var wd := Content.weapons[w]
		if GameState.weapons[w]:
			txt += "[b]%s[/b]  [color=#9a93a8]%s[/color]\n" % [wd.name, wd.traits]
		else:
			var hint := ""
			for r in Content.rooms:
				if r.reward == wd.id:
					hint = ("clear " + r.name) if r.encounter else ("somewhere in " + r.name)
			hint = hint + (", or buy it at the Forge" if hint != "" else "buy it at the Forge")
			txt += "[b]???[/b]  [color=#9a93a8]%s[/color]\n" % hint
	if _content.text != txt:
		_content.text = txt
