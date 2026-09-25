class_name UiStyle
extends RefCounted
## The prototype's "ink and candle" HUD look (src/page.html CSS variables), as Godot styles.

const DUSK := Color("#0b0a0f")
const PANEL := Color(18 / 255.0, 16 / 255.0, 26 / 255.0, 0.84)
const LINE := Color(239 / 255.0, 230 / 255.0, 210 / 255.0, 0.12)
const BONE := Color("#efe6d2")
const ASH := Color("#9a93a8")
const CANDLE := Color("#d9a74a")
const BLOOD := Color("#e0453a")
const FROST := Color("#8fd1e0")
const OK := Color("#7fc48a")


static func panel_box(alpha: float = 0.84, radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(PANEL, alpha)
	sb.border_color = LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func panel(alpha: float = 0.84) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_box(alpha))
	return p


static func label(text: String, size: int = 12, color: Color = BONE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func rich(size: int = 12) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", BONE)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func button(text: String, size: int = 13) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", BONE)
	b.add_theme_color_override("font_disabled_color", ASH)
	var n := panel_box(0.9, 4)
	n.bg_color = Color(0.13, 0.12, 0.18, 0.95)
	var h := n.duplicate() as StyleBoxFlat
	h.border_color = CANDLE
	var d := n.duplicate() as StyleBoxFlat
	d.bg_color = Color(0.09, 0.085, 0.12, 0.8)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", h)
	b.add_theme_stylebox_override("disabled", d)
	return b


## a keycap label ("T", "Esc")
static func kbd(text: String) -> String:
	return "[bgcolor=#2a2633][color=#efe6d2] %s [/color][/bgcolor]" % text


static func hex(c: Color) -> String:
	return "#" + c.to_html(false)


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
