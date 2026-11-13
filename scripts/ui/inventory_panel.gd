extends Control
class_name InventoryPanel

## 背包面板:玩家随身的东西 —— 庄稼、种子、工具、兜里的钱。
##
## 只做显示,清单逻辑在 Inventory(纯逻辑)里,所以格子怎么排能 headless 自测。
## 交互:Tab 开合。

signal closed

const PANEL_COLOR := Color(0.16, 0.14, 0.11, 0.96)
const TEXT_COLOR := Color(0.96, 0.92, 0.82)
const TITLE_COLOR := Color(0.96, 0.80, 0.45)
const SECTION_COLOR := Color(0.78, 0.82, 0.88)
const HINT_COLOR := Color(0.62, 0.64, 0.68)

var _panel: PanelContainer
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
	_panel.offset_left = -320.0
	_panel.offset_right = 320.0
	_panel.offset_top = -240.0
	_panel.offset_bottom = 240.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var title := Label.new()
	title.text = "背包"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	column.add_child(title)

	_body_label = Label.new()
	_body_label.name = "Body"
	_body_label.add_theme_font_size_override("font_size", 18)
	_body_label.add_theme_color_override("font_color", TEXT_COLOR)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(0, 320)
	column.add_child(_body_label)

func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_top = 2
	style.border_color = Color(0.55, 0.42, 0.25, 0.8)
	return style

## 开合背包
func toggle() -> void:
	if is_open():
		close()
	else:
		open()

func open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameStateManager.set_inventory_open(true)
	_refresh()

func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStateManager.set_inventory_open(false)
	closed.emit()

func is_open() -> bool:
	return visible

## 背包内容(文字)
func body_text() -> String:
	return _body_label.text if _body_label != null else ""

## 重新读一次背包 —— 随时可能被买卖改动
func refresh() -> void:
	_refresh()

func _refresh() -> void:
	if _body_label == null:
		return
	var player: PlayerProfile = GameStateManager.state.player
	if player == null:
		_body_label.text = ""
		return
	var lines: Array = []
	var crops := Inventory.entries_of_kind(player.inventory, Inventory.KIND_CROP)
	var items := Inventory.entries_of_kind(player.inventory, Inventory.KIND_ITEM)

	lines.append("【庄稼】(能卖给张晓芳)")
	if crops.is_empty():
		lines.append("  · 还没收着粮")
	for entry in crops:
		lines.append("  · %s ×%d" % [entry.get("name", ""), int(entry.get("count", 0))])

	lines.append("【物件】(种子 / 工具 / 吃食)")
	if items.is_empty():
		lines.append("  · 兜里空着")
	for entry in items:
		lines.append("  · %s ×%d" % [entry.get("name", ""), int(entry.get("count", 0))])

	lines.append("兜里的钱:%d 文" % player.gold)
	lines.append("(Tab 关)")
	_body_label.text = "\n".join(lines)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_inventory") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
