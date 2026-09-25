class_name ModalPanel
extends Control
## A dimmed full-screen card with a titled panel (the prototype's `.card` overlays).
## Click outside the panel to close (when closable).

signal closed

var box: PanelContainer
var body: VBoxContainer
var title_label: Label
var sub_label: RichTextLabel
var closable := true


func _init(title: String = "", subtitle: String = "", width: float = 640.0) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(UiStyle.DUSK, 0.75)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	box = UiStyle.panel(0.96)
	box.custom_minimum_size = Vector2(width, 0)
	center.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(width - 20, 0)
	box.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	title_label = UiStyle.label(title, 26)
	body.add_child(title_label)
	sub_label = UiStyle.rich(12)
	sub_label.text = subtitle
	body.add_child(sub_label)
	visible = false
	resized.connect(_fit)
	visibility_changed.connect(func(): if visible: _fit.call_deferred())


func _fit() -> void:
	var scroll := box.get_child(0) as ScrollContainer
	scroll.custom_minimum_size.y = minf(get_viewport_rect().size.y - 80.0, body.get_combined_minimum_size().y + 4.0)


func open() -> void:
	visible = true
	refresh()
	_fit.call_deferred()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func refresh() -> void:
	pass


func _gui_input(event: InputEvent) -> void:
	if closable and event is InputEventMouseButton and event.pressed and not box.get_global_rect().has_point(event.position):
		close()
		accept_event()


func section(text: String) -> Label:
	var l := UiStyle.label(text.to_upper(), 11, UiStyle.CANDLE)
	return l
