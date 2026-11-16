extends Control
class_name GiftPanel

## 送礼面板：只列玩家背包里现有的东西，送完立即结算喜恶/生日。

signal closed

var _npc_data: Dictionary = {}
var _panel: PanelContainer
var _title: Label
var _list: VBoxContainer
var _result: Label
var _locks_input := false

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.05, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(720, 560)
	_panel.position = Vector2(-360, -280)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.17, 0.12, 0.08, 0.97)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.62, 0.47, 0.25, 0.9)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Color(0.98, 0.83, 0.48))
	column.add_child(_title)
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size = Vector2(0, 64)
	_result.add_theme_font_size_override("font_size", 18)
	_result.add_theme_color_override("font_color", Color(0.92, 0.88, 0.76))
	column.add_child(_result)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 7)
	scroll.add_child(_list)
	var close := Button.new()
	close.text = "收起来（ESC）"
	close.pressed.connect(close_panel)
	column.add_child(close)

func open_for(npc_data: Dictionary, lock_input: bool = false) -> void:
	_npc_data = npc_data.duplicate(true)
	_locks_input = lock_input
	if _locks_input:
		GameStateManager.set_gift_open(true)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_result.text = "挑一件合适的。对方喜欢什么、今天是什么日子，都会影响心意。"
	_refresh()
	_focus_first_button.call_deferred()

func close_panel() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _locks_input:
		_locks_input = false
		GameStateManager.set_gift_open(false)
	closed.emit()

func is_open() -> bool:
	return visible

func gift_buttons() -> Array:
	var out: Array = []
	for child in _list.get_children():
		if child is Button:
			out.append(child)
	return out

func _focus_first_button() -> void:
	if not visible:
		return
	for node in find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and not button.disabled:
			button.grab_focus()
			return

func _refresh() -> void:
	_title.text = "给%s送点东西" % _npc_data.get("name", "对方")
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var inventory: Dictionary = GameStateManager.state.player.inventory
	var keys := inventory.keys()
	keys.sort()
	for item_id in keys:
		var count := int(inventory[item_id])
		if count <= 0:
			continue
		var item := ItemDatabase.get_item(String(item_id))
		var button := Button.new()
		button.text = "%s ×%d" % [item.get("name", item_id), count]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_gift.bind(String(item_id)))
		_list.add_child(button)
	if gift_buttons().is_empty():
		var empty := Label.new()
		empty.text = "背包里没有能送的东西。"
		empty.add_theme_color_override("font_color", Color(0.78, 0.74, 0.65))
		_list.add_child(empty)

func _on_gift(item_id: String) -> void:
	var result := RelationshipSystem.give_gift(GameStateManager.state, _npc_data, item_id)
	_result.text = String(result.get("message", "这份礼物没送成。"))
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()
