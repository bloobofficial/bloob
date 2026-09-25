class_name Cards
extends RefCounted
## The start, death and pause cards (prototype: #start, #death, #paused in page.html).


static func start_card() -> ModalPanel:
	var c := ModalPanel.new("Bloob", "", 640)
	c.closable = false
	var t := UiStyle.rich(13)
	t.text = "You wake in the [b]Sanctum[/b]. The world spreads out from here: the [b]Forge[/b] west, the [b]Lounge[/b] east, the [b]Hollow[/b] north and beyond it the Wayshrine, the Mire, the Ridge, the Thornwood, the Barrow and the Overlook. The map in the corner fills in as you go.\n\n" \
		+ "Wild areas [b]seal their passages[/b] until you beat the monsters inside, about four at a time, and each one takes real work: roughly two full combos. Clearing an area drops loot and sometimes a [b]weapon[/b]. Walk up to racks, wells, shrines and locals and press [b]T[/b].\n\n" \
		+ "Five weapons so far: Goo Paws, Thorn Sword, Bone Spear, Grave Hammer and Twin Fangs. Each has its own reach, speed and combo. [b]Space[/b] jumps, [b]Shift[/b] dodges (dive slam in the air), a dodge as a hit lands is a [b]perfect dodge[/b]. Press [b]`[/b] for the dev menu.\n\n" \
		+ "[color=#9a93a8]Keyboard and mouse, or a controller (left stick move, right stick aim, X attack, A jump, B dodge, RB spit, LB / LT skills, Y use, Start menu).[/color]"
	c.body.add_child(t)
	var b := UiStyle.button("Wake up", 16)
	b.name = "Begin"
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.body.add_child(b)
	return c


static func death_card() -> ModalPanel:
	var c := ModalPanel.new("Overrun", "[b]R[/b] to restart · [b]1–4[/b] to jump to a room", 480)
	c.closable = false
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func pause_card() -> ModalPanel:
	var c := ModalPanel.new("Paused", "Press [b]P[/b] to resume.", 360)
	c.closable = false
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
