extends Control
class_name DramaPanel

## 月桂剧场古戏面板：选幕、读戏页、做舞台选择、查看公演评价。
## 视觉使用奶油纸、深青幕布与蜂蜜木色，保持明亮西式剧场质感。

signal closed

const PARCHMENT := Color(0.94, 0.88, 0.72)
const INK := Color(0.20, 0.16, 0.12)
const DEEP_GREEN := Color(0.12, 0.25, 0.22)
const HONEY := Color(0.94, 0.72, 0.34)

var _act_list: VBoxContainer
var _body: Label
var _status: Label
var _choice_list: VBoxContainer
var _selected_act := ""

func _state_manager() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	return loop.root.get_node_or_null("GameStateManager")

func _game_state() -> GameState:
	var mgr := _state_manager()
	if mgr == null:
		return null
	return mgr.state

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.04, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(1080, 760)
	panel.position = Vector2(-540, -380)
	var style := StyleBoxFlat.new()
	style.bg_color = PARCHMENT
	style.border_width_left = 6
	style.border_width_right = 6
	style.border_width_top = 6
	style.border_width_bottom = 6
	style.border_color = Color(0.42, 0.27, 0.13)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.name = "Title"
	title.text = "月桂剧场 · 《%s》" % DramaSystem.title()
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", DEEP_GREEN)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = DramaSystem.subtitle() + " · 选择会改变公演评价与镇民关系"
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", Color(0.34, 0.30, 0.23))
	column.add_child(subtitle)
	var body_row := HBoxContainer.new()
	body_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_row.add_theme_constant_override("separation", 18)
	column.add_child(body_row)

	var act_scroll := ScrollContainer.new()
	act_scroll.custom_minimum_size = Vector2(280, 0)
	body_row.add_child(act_scroll)
	_act_list = VBoxContainer.new()
	_act_list.name = "ActList"
	_act_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_act_list.add_theme_constant_override("separation", 8)
	act_scroll.add_child(_act_list)

	var stage_panel := PanelContainer.new()
	stage_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stage_style := StyleBoxFlat.new()
	stage_style.bg_color = Color(0.10, 0.22, 0.20, 0.96)
	stage_style.corner_radius_top_left = 12
	stage_style.corner_radius_top_right = 12
	stage_style.corner_radius_bottom_left = 12
	stage_style.corner_radius_bottom_right = 12
	stage_panel.add_theme_stylebox_override("panel", stage_style)
	body_row.add_child(stage_panel)
	var stage_margin := MarginContainer.new()
	stage_margin.add_theme_constant_override("margin_left", 20)
	stage_margin.add_theme_constant_override("margin_right", 20)
	stage_margin.add_theme_constant_override("margin_top", 18)
	stage_margin.add_theme_constant_override("margin_bottom", 18)
	stage_panel.add_child(stage_margin)
	var stage_column := VBoxContainer.new()
	stage_column.add_theme_constant_override("separation", 10)
	stage_margin.add_child(stage_column)
	_body = Label.new()
	_body.name = "Body"
	_body.custom_minimum_size = Vector2(0, 245)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_body.add_theme_font_size_override("font_size", 21)
	_body.add_theme_color_override("font_color", Color(0.95, 0.90, 0.76))
	_body.add_theme_constant_override("line_spacing", 7)
	stage_column.add_child(_body)
	var choice_scroll := ScrollContainer.new()
	choice_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choice_scroll.follow_focus = true
	stage_column.add_child(choice_scroll)
	_choice_list = VBoxContainer.new()
	_choice_list.name = "ChoiceList"
	_choice_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice_list.add_theme_constant_override("separation", 7)
	choice_scroll.add_child(_choice_list)
	_status = Label.new()
	_status.name = "Status"
	_status.custom_minimum_size = Vector2(0, 58)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 17)
	_status.add_theme_color_override("font_color", Color(0.31, 0.27, 0.20))
	column.add_child(_status)
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "收起戏页（ESC）"
	close.pressed.connect(close_panel)
	column.add_child(close)

func open_panel() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var mgr := _state_manager()
	if mgr != null:
		mgr.call("set_drama_open", true)
	var state := _game_state()
	if state == null:
		return
	_selected_act = DramaSystem.current_act_id(state)
	_status.text = "周德顺把灯芯捻亮：“戏页在这儿，怎么演由你。”"
	_refresh()
	_focus_first_button.call_deferred()

func close_panel() -> void:
	if not visible:
		return
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mgr := _state_manager()
	if mgr != null:
		mgr.call("set_drama_open", false)
	closed.emit()

func is_open() -> bool:
	return visible

func body_text() -> String:
	return _body.text if _body != null else ""

func act_buttons() -> Array:
	var out: Array = []
	for child in _act_list.get_children():
		if child is Button:
			out.append(child)
	return out

func choice_buttons() -> Array:
	var out: Array = []
	for child in _choice_list.get_children():
		if child is Button:
			out.append(child)
	return out

func select_act(act_id: String) -> Dictionary:
	var state := _game_state()
	if state == null:
		return {"ok": false, "message": "找不到游戏状态。"}
	var result := DramaSystem.begin_act(state, act_id)
	if bool(result.get("ok", false)):
		_selected_act = act_id
	_status.text = String(result.get("message", ""))
	_refresh()
	return result

func choose(choice_id: String) -> Dictionary:
	var state := _game_state()
	if state == null:
		return {"ok": false, "message": "找不到游戏状态。"}
	var result := DramaSystem.choose(state, _selected_act, choice_id)
	_status.text = String(result.get("message", ""))
	if bool(result.get("finished", false)):
		var acts := DramaSystem.all_acts()
		for i in acts.size():
			if String(acts[i].get("id", "")) == _selected_act and i + 1 < acts.size():
				var next_id := String(acts[i + 1].get("id", ""))
				if DramaSystem.is_unlocked(state, next_id):
					_selected_act = next_id
				break
	_refresh()
	return result

func _refresh() -> void:
	if _act_list == null or _choice_list == null:
		return
	for child in _act_list.get_children():
		_act_list.remove_child(child)
		child.queue_free()
	for child in _choice_list.get_children():
		_choice_list.remove_child(child)
		child.queue_free()
	var state := _game_state()
	if state == null:
		_body.text = "戏页暂时找不到。"
		return
	for act in DramaSystem.all_acts():
		var act_id := String(act.get("id", ""))
		var button := Button.new()
		button.text = "%s\n%s" % [act.get("title", act_id),
			DramaSystem.act_state_text(state, act)]
		button.custom_minimum_size = Vector2(0, 74)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not DramaSystem.is_unlocked(state, act_id)
		button.pressed.connect(select_act.bind(act_id))
		_act_list.add_child(button)

	var act := DramaSystem.get_act(_selected_act)
	if act.is_empty():
		_body.text = DramaSystem.premise()
		return
	var node := DramaSystem.current_node(state, _selected_act)
	if DramaSystem.is_completed(state, _selected_act):
		var ending := DramaSystem.ending(state)
		_body.text = "%s\n\n【本幕已完成】\n%s" % [act.get("summary", ""),
			ending.get("text", "这一幕已经收进戏册。") if not ending.is_empty() else "这一幕已经收进戏册。"]
		return
	if node.is_empty():
		_body.text = String(act.get("summary", "")) + "\n\n这一幕还没有戏页。"
		return
	var rep := DramaSystem.reputation(state)
	_body.text = "%s\n\n【%s】%s\n\n公演评价：%d · 累计收获：%d" % [
		act.get("summary", ""), node.get("speaker", "旁白"), node.get("text", ""),
		rep, DramaSystem.harvested_total(state)]
	for option in node.get("choices", []):
		var button := Button.new()
		button.text = "▶ " + String(option.get("label", "选这一句"))
		button.custom_minimum_size = Vector2(0, 48)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(choose.bind(String(option.get("id", ""))))
		_choice_list.add_child(button)

func _focus_first_button() -> void:
	if not visible:
		return
	for node in find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and not button.disabled:
			button.grab_focus()
			return

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()
