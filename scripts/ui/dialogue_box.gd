extends Control
class_name DialogueBox

## 对话框:显示 NPC 台词与玩家选项。
##
## 只做"显示 + 转发点击",对话走向由 DialogueRunner(纯逻辑)决定,
## 所以整套对话可以在 headless 下自测,UI 不用背逻辑。
##
## 交互:E / 空格 往下推进,鼠标点选项。

signal closed
## 需要外部执行的动作(如打开商店)
signal action_triggered(action: String, data: Dictionary)

const PANEL_COLOR := Color(0.18, 0.13, 0.09, 0.94)
const TEXT_COLOR := Color(0.96, 0.92, 0.82)
const SPEAKER_COLOR := Color(0.96, 0.80, 0.45)
const OPTION_COLOR := Color(0.86, 0.88, 0.92)
const OPTION_HOVER_COLOR := Color(1.0, 0.90, 0.62)

var _runner: DialogueRunner = null
var _npc: NpcBase = null

var _panel: PanelContainer
var _speaker_label: Label
var _text_label: Label
var _option_box: VBoxContainer

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build_ui()

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 120.0
	_panel.offset_right = -120.0
	_panel.offset_top = -320.0
	_panel.offset_bottom = -40.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	_speaker_label = Label.new()
	_speaker_label.name = "Speaker"
	_speaker_label.add_theme_font_size_override("font_size", 22)
	_speaker_label.add_theme_color_override("font_color", SPEAKER_COLOR)
	column.add_child(_speaker_label)

	_text_label = Label.new()
	_text_label.name = "Body"
	_text_label.add_theme_font_size_override("font_size", 19)
	_text_label.add_theme_color_override("font_color", TEXT_COLOR)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(0, 96)
	column.add_child(_text_label)

	_option_box = VBoxContainer.new()
	_option_box.name = "Options"
	_option_box.add_theme_constant_override("separation", 6)
	column.add_child(_option_box)

func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_top = 2
	style.border_color = Color(0.55, 0.42, 0.25, 0.8)
	style.content_margin_left = 0
	style.content_margin_right = 0
	return style

## 接入一位 NPC 与一份对话运行时
func setup(npc: NpcBase, runner: DialogueRunner) -> void:
	_npc = npc
	_runner = runner
	_refresh()

func open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh()

func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed.emit()

func is_open() -> bool:
	return visible

## 当前说话人
func speaker_name() -> String:
	return _speaker_label.text if _speaker_label != null else ""

## 当前台词
func body_text() -> String:
	return _text_label.text if _text_label != null else ""

## 当前可见选项的文字(给自测与 UI 用)
func option_texts() -> Array:
	var out: Array = []
	for button in option_buttons():
		out.append(String(button.text).replace("· ", ""))
	return out

## 当前可见选项的按钮(给自测点按钮用)
func option_buttons() -> Array:
	var out: Array = []
	if _option_box == null:
		return out
	for child in _option_box.get_children():
		if child is Button:
			out.append(child)
	return out

## 商店等子面板盖上来时暂时收起(对话本身没结束,收摊后还要接着聊)
func hide_temporarily() -> void:
	visible = false

## 商店收摊后把对话放回来
func show_again() -> void:
	if _runner == null or _runner.is_finished():
		return
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh()

## 重画台词与选项
func refresh() -> void:
	_refresh()

func _refresh() -> void:
	if _runner == null:
		return
	if _npc != null and _speaker_label != null:
		_speaker_label.text = _npc.name
	if _text_label != null:
		_text_label.text = _runner.current_text()
	_rebuild_options()

func _rebuild_options() -> void:
	if _option_box == null:
		return
	for child in _option_box.get_children():
		# 先摘出树再释放:queue_free 的节点在当帧还留在树里,
		# 还能被点到 —— 旧按钮会用旧索引触发选择,点一下就选错了
		_option_box.remove_child(child)
		child.queue_free()
	var options := _runner.current_options()
	if options.is_empty():
		# 没有选项 —— 提示继续
		var hint := Button.new()
		hint.text = "继续 ▸"
		hint.alignment = HORIZONTAL_ALIGNMENT_LEFT
		hint.add_theme_font_size_override("font_size", 17)
		hint.add_theme_color_override("font_color", OPTION_HOVER_COLOR)
		hint.pressed.connect(_on_advance)
		_option_box.add_child(hint)
		return
	for i in options.size():
		var option: Dictionary = options[i]
		var button := Button.new()
		button.text = "· " + String(option.get("text", ""))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 17)
		button.add_theme_color_override("font_color", OPTION_COLOR)
		button.add_theme_color_override("font_hover_color", OPTION_HOVER_COLOR)
		button.pressed.connect(_on_option_pressed.bind(i))
		_option_box.add_child(button)

func _on_advance() -> void:
	if _runner == null:
		return
	if not _runner.advance():
		close()
		return
	_refresh()

func _on_option_pressed(index: int) -> void:
	if _runner == null:
		return
	var result := _runner.choose(index)
	match String(result.get("type", "")):
		"line":
			_refresh()
		"action":
			var action := String(result.get("action", ""))
			var data: Dictionary = result.get("data", {})
			action_triggered.emit(action, data)
			_refresh()
		_:
			close()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		if _runner != null and _runner.current_options().is_empty():
			_on_advance()
		elif _runner != null:
			# 有选项时按 E 不代替玩家选,只提示
			if _text_label != null:
				_text_label.text = _runner.current_text()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
