extends Control
class_name FishingPanel

signal closed

var _panel: PanelContainer
var _status: Label
var _button: Button
var _fishing: FishingSystem = null

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	set_process(true)

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.06, 0.48)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(640, 340)
	_panel.position = Vector2(-320, -170)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.15, 0.16, 0.97)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.36, 0.58, 0.56, 0.9)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var title := Label.new()
	title.text = "河湾垂钓"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.72, 0.94, 0.86))
	column.add_child(title)
	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 120)
	_status.add_theme_font_size_override("font_size", 21)
	_status.add_theme_color_override("font_color", Color(0.92, 0.94, 0.86))
	column.add_child(_status)
	_button = Button.new()
	_button.text = "收线（E）"
	_button.pressed.connect(_reel)
	column.add_child(_button)
	var close := Button.new()
	close.text = "收竿（ESC）"
	close.pressed.connect(close_panel)
	column.add_child(close)

func open_round(seed: int, season: String = "spring") -> void:
	_fishing = FishingSystem.new()
	var bait_bonus := 0.0
	var state := GameStateManager.state
	if state != null and int(state.player.inventory.get("bait_worm", 0)) > 0:
		state.player.inventory["bait_worm"] = int(state.player.inventory["bait_worm"]) - 1
		if int(state.player.inventory["bait_worm"]) <= 0:
			state.player.inventory.erase("bait_worm")
		bait_bonus = 0.35
	_fishing.start(seed, season, bait_bonus)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameStateManager.set_fishing_open(true)
	_status.text = "浮漂落进水里。%s别急，等它沉下去。" % ("鱼饵散开，水下有动静。" if bait_bonus > 0.0 else "")
	_button.disabled = false
	_button.grab_focus.call_deferred()

func close_panel() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStateManager.set_fishing_open(false)
	closed.emit()

func is_open() -> bool:
	return visible

func status_text() -> String:
	return _status.text if _status != null else ""

func _process(delta: float) -> void:
	if not visible or _fishing == null or _fishing.is_finished():
		return
	var state := _fishing.tick(delta)
	match state:
		"waiting":
			_status.text = "浮漂轻轻晃，水底下有东西在试探。"
		"bite":
			_status.text = "咬钩了！现在收线！"
		"missed":
			_status.text = "水面一圈涟漪散开，鱼跑了。"
			_button.disabled = true

func _reel() -> void:
	if _fishing == null:
		return
	var result := _fishing.reel()
	_status.text = String(result.get("message", ""))
	if bool(result.get("ok", false)):
		var fish_id := String(result.get("fish_id", ""))
		GameStateManager.state.player.inventory[fish_id] = \
			int(GameStateManager.state.player.inventory.get(fish_id, 0)) + 1
		QuestSystem.progress(GameStateManager.state, "fish", 1)
		SkillSystem.add_xp(GameStateManager.state.player, "fishing", 8)
	_button.disabled = true

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_reel()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()
