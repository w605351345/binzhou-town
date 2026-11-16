extends Control
class_name QuestPanel

## 公告板任务面板：接取、查看进度、交付。

signal closed

var _panel: PanelContainer
var _status: Label
var _list: VBoxContainer

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.02, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(900, 660)
	_panel.position = Vector2(-450, -330)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.12, 0.08, 0.98)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.62, 0.43, 0.21, 0.95)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = "镇中心 · 公告板"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.98, 0.82, 0.48))
	column.add_child(title)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 54)
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color(0.92, 0.88, 0.76))
	column.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 9)
	scroll.add_child(_list)
	var close := Button.new()
	close.text = "离开公告板（ESC）"
	close.pressed.connect(close_panel)
	column.add_child(close)

func open_panel() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameStateManager.set_quest_open(true)
	_status.text = "纸角被风掀着。接一条活，或者把办完的交上去。"
	_refresh()
	_focus_first_button.call_deferred()

func close_panel() -> void:
	if not visible:
		return
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStateManager.set_quest_open(false)
	closed.emit()

func is_open() -> bool:
	return visible

func status_text() -> String:
	return _status.text if _status != null else ""

func quest_buttons() -> Array:
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

func accept_quest(quest_id: String) -> Dictionary:
	var result := QuestSystem.accept(GameStateManager.state, quest_id)
	_status.text = String(result.get("message", ""))
	_refresh()
	return result

func turn_in_quest(quest_id: String) -> Dictionary:
	var result := QuestSystem.turn_in(GameStateManager.state, quest_id)
	_status.text = String(result.get("message", ""))
	_refresh()
	return result

func _refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var state := GameStateManager.state
	var any_active := false
	for entry in QuestSystem.active_entries(state):
		var quest_id := String(entry.get("id", ""))
		var quest := QuestSystem.get_quest(quest_id)
		if quest.is_empty():
			continue
		any_active = true
		var active := Button.new()
		var progress := QuestSystem.progress_text(state, quest_id)
		if QuestSystem.can_turn_in(state, quest_id):
			active.text = "交付 · %s · %s" % [quest.get("title", quest_id), progress]
			active.pressed.connect(turn_in_quest.bind(quest_id))
		else:
			active.text = "进行中 · %s · %s" % [quest.get("title", quest_id), progress]
			active.disabled = true
		active.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_list.add_child(active)
	for quest in QuestSystem.available_quests(state, state.calendar):
		var quest_id := String(quest.get("id", ""))
		var giver := NpcRegistry.get_npc(String(quest.get("giver", "")))
		var button := Button.new()
		button.text = "接取 · %s · %s" % [quest.get("title", quest_id),
			giver.get("name", quest.get("giver", ""))]
		button.tooltip_text = _quest_detail(quest)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(accept_quest.bind(quest_id))
		_list.add_child(button)
	if not any_active and _list.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "今天的活都办完了。明天再来看看。"
		empty.add_theme_color_override("font_color", Color(0.78, 0.73, 0.63))
		_list.add_child(empty)

func _quest_detail(quest: Dictionary) -> String:
	var reqs: Array = []
	for req in quest.get("requirements", []):
		reqs.append(QuestSystem.requirement_text(req))
	var rewards: Dictionary = quest.get("rewards", {})
	var reward_cn := "%d 文" % int(rewards.get("gold", 0))
	if int(rewards.get("affection", 0)) > 0:
		reward_cn += " · 好感 +%d" % int(rewards.get("affection", 0))
	return "%s\n要求：%s\n报酬：%s" % [quest.get("summary", ""), "、".join(reqs), reward_cn]

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()
