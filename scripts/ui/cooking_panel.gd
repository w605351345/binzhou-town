extends Control
class_name CookingPanel

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
	dim.color = Color(0.05, 0.03, 0.02, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(720, 540)
	_panel.position = Vector2(-360, -270)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.12, 0.07, 0.97)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.62, 0.42, 0.2, 0.9)
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
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.text = "灶台 · 家常菜"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.98, 0.82, 0.48))
	column.add_child(title)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 54)
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color(0.92, 0.89, 0.78))
	column.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	var close := Button.new()
	close.text = "离开灶台（ESC）"
	close.pressed.connect(close_panel)
	column.add_child(close)

func open_panel() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameStateManager.set_cooking_open(true)
	_status.text = "看看家里有什么，能下锅的就做一口热的。"
	_refresh()

func close_panel() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStateManager.set_cooking_open(false)
	closed.emit()

func is_open() -> bool:
	return visible

func recipe_buttons() -> Array:
	var out: Array = []
	for child in _list.get_children():
		if child is Button:
			out.append(child)
	return out

func _refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for recipe in CookingSystem.all_recipes():
		var recipe_id := String(recipe.get("id", ""))
		var button := Button.new()
		button.text = "%s · %s" % [recipe.get("name", recipe_id),
			_ingredient_text(recipe)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not CookingSystem.can_cook(GameStateManager.state, recipe_id)
		button.pressed.connect(_cook.bind(recipe_id))
		_list.add_child(button)

func _ingredient_text(recipe: Dictionary) -> String:
	var parts: Array = []
	for need in recipe.get("ingredients", []):
		var item := ItemDatabase.get_item(String(need.get("id", "")))
		parts.append("%s×%d" % [item.get("name", need.get("id", "")), int(need.get("count", 1))])
	return "、".join(parts)

func _cook(recipe_id: String) -> void:
	var result := CookingSystem.cook(GameStateManager.state, recipe_id)
	_status.text = String(result.get("message", ""))
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()
