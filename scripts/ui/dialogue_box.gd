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

const PANEL_COLOR := Color(0.16, 0.11, 0.07, 0.96)
const TEXT_COLOR := Color(0.96, 0.92, 0.82)
const SPEAKER_COLOR := Color(0.96, 0.80, 0.45)
const OPTION_COLOR := Color(0.86, 0.88, 0.92)
const OPTION_HOVER_COLOR := Color(1.0, 0.90, 0.62)

## 逐字字幕速度(字/秒)
const CHARS_PER_SEC := 26.0
## 语音音量
const VOICE_VOLUME_DB := -4.0
const VOICE_ENABLED := false

var _runner: DialogueRunner = null
var _npc: NpcBase = null

var _panel: PanelContainer
var _portrait_frame: PanelContainer
var _portrait: TextureRect
var _speaker_label: Label
var _text_label: Label
var _option_scroll: ScrollContainer
var _option_box: VBoxContainer
var _voice_player: AudioStreamPlayer

## 完整台词(自测读这个);打字机只影响屏幕上显示的那部分
var _full_text: String = ""
var _shown_chars: int = 0
var _type_accum: float = 0.0

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
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	_layout_panel()

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Content"
	column.add_theme_constant_override("separation", 12)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var content_row := HBoxContainer.new()
	content_row.name = "ContentRow"
	content_row.add_theme_constant_override("separation", 20)
	content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(content_row)

	_portrait_frame = PanelContainer.new()
	_portrait_frame.name = "PortraitFrame"
	_portrait_frame.custom_minimum_size = Vector2(204, 204)
	_portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_portrait_frame.add_theme_stylebox_override("panel", _make_portrait_style())
	_portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_row.add_child(_portrait_frame)

	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	_portrait.custom_minimum_size = Vector2(188, 188)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.clip_contents = true
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.visible = false
	_portrait_frame.add_child(_portrait)

	content_row.add_child(column)

	_speaker_label = Label.new()
	_speaker_label.name = "Speaker"
	_speaker_label.add_theme_font_size_override("font_size", 24)
	_speaker_label.add_theme_color_override("font_color", SPEAKER_COLOR)
	_speaker_label.add_theme_color_override("font_shadow_color", Color(0.04, 0.03, 0.02, 0.9))
	_speaker_label.add_theme_constant_override("shadow_offset_x", 2)
	_speaker_label.add_theme_constant_override("shadow_offset_y", 2)
	column.add_child(_speaker_label)

	_text_label = Label.new()
	_text_label.name = "Body"
	_text_label.add_theme_font_size_override("font_size", 20)
	_text_label.add_theme_color_override("font_color", TEXT_COLOR)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(0, 96)
	column.add_child(_text_label)

	# 七个默认话题在 1080p 下能完整展示；窗口更矮或事件台词更长时，
	# 选项区自己滚动，不能把最后几个按钮裁出屏幕外。
	_option_scroll = ScrollContainer.new()
	_option_scroll.name = "OptionScroll"
	_option_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_option_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_option_scroll.custom_minimum_size = Vector2(0, 150)
	_option_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_option_scroll)

	_option_box = VBoxContainer.new()
	_option_box.name = "Options"
	_option_box.add_theme_constant_override("separation", 6)
	_option_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option_scroll.add_child(_option_box)

	# NPC 语音:普通话语音包,可在暂停菜单静音
	_voice_player = AudioStreamPlayer.new()
	_voice_player.name = "Voice"
	_voice_player.volume_db = VOICE_VOLUME_DB
	add_child(_voice_player)

## 对话框贴着视口底边，但高度随窗口自适应。固定 -320 的旧值只够
## 三四个选项，真实窗口里第七个选项会被裁掉。
func _layout_panel() -> void:
	if _panel == null or not is_inside_tree():
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var side := clampf(viewport_size.x * 0.06, 24.0, 120.0)
	var bottom_margin := clampf(viewport_size.y * 0.035, 20.0, 40.0)
	var desired_height := clampf(viewport_size.y * 0.48, 380.0, 540.0)
	desired_height = minf(desired_height, maxf(280.0, viewport_size.y - 120.0))
	_panel.offset_left = side
	_panel.offset_right = -side
	_panel.offset_top = -desired_height - bottom_margin
	_panel.offset_bottom = -bottom_margin

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _panel != null:
		_layout_panel()

func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.63, 0.48, 0.27, 0.9)
	style.shadow_color = Color(0.02, 0.01, 0.0, 0.35)
	style.shadow_size = 10
	style.content_margin_left = 0
	style.content_margin_right = 0
	return style

func _make_portrait_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.20, 0.14, 0.08, 0.98)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.91, 0.72, 0.39, 0.96)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.shadow_color = Color(0.02, 0.01, 0.0, 0.42)
	style.shadow_size = 8
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

## 接入一位 NPC 与一份对话运行时
func setup(npc: NpcBase, runner: DialogueRunner) -> void:
	_npc = npc
	_runner = runner
	_apply_portrait(npc)
	_refresh()

func open() -> void:
	_layout_panel()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh()
	_focus_first_option.call_deferred()

func close() -> void:
	if _voice_player != null:
		_voice_player.stop()
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and (focused == self or self.is_ancestor_of(focused)):
		focused.release_focus()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed.emit()

func is_open() -> bool:
	return visible

## 当前说话人
func speaker_name() -> String:
	return _speaker_label.text if _speaker_label != null else ""

## 当前台词(完整文本)
func body_text() -> String:
	return _full_text

## 当前显示到屏幕上的台词(逐字动画进行中会比 body_text 短)
func displayed_text() -> String:
	return _text_label.text if _text_label != null else ""

## 当前 NPC 立绘图；缺图或未开始对话时为 null。
func portrait_texture() -> Texture2D:
	return _portrait.texture if _portrait != null else null

## 立绘框是否可见(供接线测试与 UI 验收)。
func portrait_visible() -> bool:
	return _portrait_frame != null and _portrait_frame.visible and portrait_texture() != null

## 立即显示完整台词(玩家按键/点击时跳过打字机)
func reveal_all() -> void:
	_shown_chars = _full_text.length()
	if _text_label != null:
		_text_label.text = _full_text

## 逐字字幕推进
func _process(delta: float) -> void:
	if not visible or _text_label == null:
		return
	if _shown_chars >= _full_text.length():
		return
	_type_accum += delta
	var per_char := 1.0 / CHARS_PER_SEC
	while _type_accum >= per_char and _shown_chars < _full_text.length():
		_type_accum -= per_char
		_shown_chars += 1
	_text_label.text = _full_text.substr(0, _shown_chars)

## 显示一句新台词并播对应语音
func _show_line(text: String) -> void:
	_full_text = text
	_shown_chars = 0
	_type_accum = 0.0
	if _text_label != null:
		_text_label.text = ""
	_play_voice()

## 播放当前台词的语音(静音或缺文件就安静跳过)
func _play_voice() -> void:
	if not VOICE_ENABLED or _voice_player == null or _npc == null or _runner == null:
		return
	if GameStateManager.state != null and not GameStateManager.state.voice_enabled:
		return
	var key := VoiceBank.key_for(_npc.id, _runner.current_line_id(),
		_runner.current_variant_index())
	var stream := VoiceBank.stream_for(key)
	if stream == null:
		return
	_voice_player.stream = stream
	_voice_player.play()

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
	_layout_panel()
	if _npc != null and _speaker_label != null:
		_speaker_label.text = _npc.name
	_show_line(_runner.current_text())
	_rebuild_options()

func _apply_portrait(npc: NpcBase) -> void:
	if _portrait == null or _portrait_frame == null:
		return
	_portrait.texture = null
	_portrait_frame.visible = false
	if npc == null or npc.portrait_path == "":
		return
	if not ResourceLoader.exists(npc.portrait_path):
		return
	var texture := load(npc.portrait_path) as Texture2D
	if texture == null:
		return
	_portrait.texture = texture
	_portrait.visible = true
	_portrait_frame.visible = true

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
	if visible:
		_focus_first_option.call_deferred()

## 键盘/手柄焦点落在第一个可选项上。原先选项只能用鼠标点，
## 手柄玩家进了对话就选不了“卖粮”“送点东西”等长列表后半段。
func _focus_first_option() -> void:
	if not visible or _option_box == null:
		return
	for child in _option_box.get_children():
		if child is Button:
			child.grab_focus()
			_option_scroll.ensure_control_visible(child)
			return

## 用 ui_up / ui_down 在选项之间移动。按钮本身放在 ScrollContainer 里，
## 焦点移动后必须 ensure_control_visible，否则最后几项仍停在可视区外。
func _focus_relative(step: int) -> void:
	var buttons := option_buttons()
	if buttons.is_empty():
		return
	var focused := get_viewport().gui_get_focus_owner()
	var index := buttons.find(focused)
	if index < 0:
		index = 0 if step > 0 else buttons.size() - 1
	else:
		index = clampi(index + step, 0, buttons.size() - 1)
	var button: Button = buttons[index]
	button.grab_focus()
	_option_scroll.ensure_control_visible(button)

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

## 用 _input 而不是 _unhandled_input: ScrollContainer 会先消费方向键滚轮事件，
## 到 _unhandled_input 时已看不到，焦点就卡在第一个选项上。
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up"):
		get_viewport().set_input_as_handled()
		_focus_relative(1 if event.is_action_pressed("ui_down") else -1)
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		if _runner != null and _runner.current_options().is_empty():
			_on_advance()
		elif _runner != null:
			# 有选项时 E/Enter 确认当前高亮项；没有焦点就先把话显示完整。
			var focused := get_viewport().gui_get_focus_owner()
			if focused is Button and _option_box.is_ancestor_of(focused):
				focused.pressed.emit()
			else:
				reveal_all()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
