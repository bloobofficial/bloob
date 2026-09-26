class_name AltarPanel
extends ModalPanel
## An altar: three skills (passives) on offer, take one. Click a card or press 1 / 2 / 3.
## Taking one applies it at once, adds it to the Skills tab and puts the altar out.

var world: World
var _row: HBoxContainer


func _init() -> void:
	super("Altar", "Choose one. %s %s %s to pick, %s to leave." % [UiStyle.kbd("1"), UiStyle.kbd("2"), UiStyle.kbd("3"), UiStyle.kbd("T")], 720)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 10)
	body.add_child(_row)


func refresh() -> void:
	UiStyle.clear(_row)
	var list := world.altar_choices()
	for i in list.size():
		var pd := Content.passive(list[i])
		if pd == null:
			continue
		var owned := GameState.passive_count(pd.id)
		var b := UiStyle.button("%d  %s\n\n%s%s" % [i + 1, pd.name, pd.desc, "\n\n(you have %d: they stack)" % owned if owned > 0 else ""], 13)
		b.custom_minimum_size = Vector2(216, 130)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_color_override("font_color", pd.color.lerp(UiStyle.BONE, 0.35))
		b.pressed.connect(choose.bind(i))
		_row.add_child(b)


func choose(i: int) -> void:
	if world.choose_at_altar(i):
		close()
