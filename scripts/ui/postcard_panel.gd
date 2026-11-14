extends Control
class_name PostcardPanel

## 老邮局面板:寄信、查看在途信件、翻明信片收藏册。
##
## 显示层只转发动作,寄信与投递规则全部在 PostcardSystem 里,
## 因此"寄出 → 次日收到 → 收藏"能在 headless 下完整自测。

signal closed

const PANEL_COLOR := Color(0.16, 0.14, 0.11, 0.97)
const TEXT_COLOR := Color(0.96, 0.92, 0.82)
const TITLE_COLOR := Color(0.96, 0.80, 0.45)
const DIM_COLOR := Color(0.62, 0.60, 0.55)
const STAMP_COLOR := Color(0.85, 0.62, 0.32)

var _panel: PanelContainer
var _status_label: Label
var _message_label: Label
var _send_box: VBoxContainer
var _body_label: Label

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build_ui()

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -390.0
	_panel.offset_right = 390.0
	_panel.offset_top = -355.0
	_panel.offset_bottom = 355.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)

	var title := Label.new()
	title.text = "老邮局 · 明信片"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	column.add_child(title)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.add_theme_font_size_override("font_size", 17)
	_status_label.add_theme_color_override("font_color", DIM_COLOR)
	column.add_child(_status_label)

	_message_label = Label.new()
	_message_label.name = "Message"
	_message_label.add_theme_font_size_override("font_size", 17)
	_message_label.add_theme_color_override("font_color", TEXT_COLOR)
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.custom_minimum_size = Vector2(0, 24)
	column.add_child(_message_label)

	var send_title := Label.new()
	send_title.text = "【写一封信】"
	send_title.add_theme_font_size_override("font_size", 18)
	send_title.add_theme_color_override("font_color", STAMP_COLOR)
	column.add_child(send_title)

	_send_box = VBoxContainer.new()
	_send_box.name = "Recipients"
	_send_box.add_theme_constant_override("separation", 5)
	column.add_child(_send_box)

	var collection_title := Label.new()
	collection_title.text = "【明信片收藏册】"
	collection_title.add_theme_font_size_override("font_size", 18)
	collection_title.add_theme_color_override("font_color", STAMP_COLOR)
	column.add_child(collection_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 260)
	column.add_child(scroll)

	_body_label = Label.new()
	_body_label.name = "Body"
	_body_label.add_theme_font_size_override("font_size", 16)
	_body_label.add_theme_color_override("font_color", TEXT_COLOR)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(700, 0)
	scroll.add_child(_body_label)

	var close_button := Button.new()
	close_button.text = "合上邮册(ESC)"
	close_button.add_theme_font_size_override("font_size", 17)
	close_button.pressed.connect(close_panel)
	column.add_child(close_button)

func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_top = 2
	style.border_color = Color(0.55, 0.42, 0.25, 0.85)
	return style

func open_panel() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameStateManager.set_postcard_open(true)
	_refresh()

func close_panel() -> void:
	if not visible:
		return
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStateManager.set_postcard_open(false)
	closed.emit()

func is_open() -> bool:
	return visible

func body_text() -> String:
	return _body_label.text if _body_label != null else ""

func status_text() -> String:
	return _status_label.text if _status_label != null else ""

## 寄信按钮 —— 供自测按真实按钮路径验证,而不是只调纯逻辑。
func send_buttons() -> Array:
	var out: Array = []
	if _send_box == null:
		return out
	for child in _send_box.get_children():
		if child is Button:
			out.append(child)
	return out

func send_to(recipient_id: String) -> Dictionary:
	var res := PostcardSystem.send(
		GameStateManager.state, GameStateManager.state.calendar, recipient_id)
	_message_label.text = String(res.get("message", ""))
	_refresh()
	return res

func refresh() -> void:
	_refresh()

func _refresh() -> void:
	if _status_label == null:
		return
	var state := GameStateManager.state
	var calendar := state.calendar
	_status_label.text = PostcardSystem.status_text(state, calendar)

	for child in _send_box.get_children():
		_send_box.remove_child(child)
		child.queue_free()
	var can_send := state.postcards_pending.is_empty()
	for recipient in PostcardData.all_recipients():
		var recipient_id := String(recipient.get("id", ""))
		var button := Button.new()
		var received := PostcardSystem.received_count(state, recipient_id)
		var total := PostcardData.reply_ids(recipient_id).size()
		var next_card := PostcardSystem.next_postcard_for(state, recipient_id)
		if next_card.is_empty():
			button.text = "%s · 故事听全了(%d/%d)" % [recipient.get("name", ""), received, total]
			button.disabled = true
		elif not can_send:
			button.text = "%s · 等回信(%d/%d)" % [recipient.get("name", ""), received, total]
			button.disabled = true
		else:
			button.text = "寄给%s · %s(%d/%d)" % [
				recipient.get("name", ""), recipient.get("relation", ""), received, total]
			button.pressed.connect(func(): send_to(recipient_id))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 17)
		_send_box.add_child(button)

	var cards := PostcardSystem.collected_postcards(state)
	var total_cards := PostcardData.all_postcards().size()
	var lines: Array = ["已收 %d/%d 张" % [cards.size(), total_cards], ""]
	if cards.is_empty():
		lines.append("册子还是空的。去柜台寄一封信,等邮差把远方的回信捎回来。")
	else:
		for card in cards:
			var recipient := PostcardData.get_recipient(String(card.get("recipient_id", "")))
			lines.append("《%s》 —— %s" % [
				card.get("title", ""), recipient.get("name", "远方")])
			lines.append(String(card.get("body", "")))
			lines.append("")
	_body_label.text = "\n".join(lines)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()
