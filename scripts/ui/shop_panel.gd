extends Control
class_name ShopPanel

## 商店面板:张晓芳的柜台 —— 买种子、卖粮食。
##
## 只做"显示 + 转发点击",结算全部交给 Shop(纯逻辑),所以买卖规则能 headless 自测。
## 交互:点按钮买卖,ESC / 关闭键退出。

signal closed

const PANEL_COLOR := Color(0.16, 0.14, 0.11, 0.96)
const TEXT_COLOR := Color(0.96, 0.92, 0.82)
const TITLE_COLOR := Color(0.96, 0.80, 0.45)
const ITEM_COLOR := Color(0.86, 0.88, 0.92)
const ITEM_DIM := Color(0.55, 0.55, 0.58)
const ITEM_HOVER := Color(1.0, 0.90, 0.62)

enum Mode { SELL, BUY }

var _npc: NpcBase = null
var _mode: int = Mode.SELL

var _panel: PanelContainer
var _title_label: Label
var _gold_label: Label
var _message_label: Label
var _list_box: VBoxContainer

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
	_panel.offset_left = -420.0
	_panel.offset_right = 420.0
	_panel.offset_top = -260.0
	_panel.offset_bottom = 260.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", TITLE_COLOR)
	column.add_child(_title_label)

	_gold_label = Label.new()
	_gold_label.name = "Gold"
	_gold_label.add_theme_font_size_override("font_size", 17)
	_gold_label.add_theme_color_override("font_color", TEXT_COLOR)
	column.add_child(_gold_label)

	_message_label = Label.new()
	_message_label.name = "Message"
	_message_label.add_theme_font_size_override("font_size", 17)
	_message_label.add_theme_color_override("font_color", TEXT_COLOR)
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.custom_minimum_size = Vector2(0, 24)
	column.add_child(_message_label)

	_list_box = VBoxContainer.new()
	_list_box.name = "List"
	_list_box.add_theme_constant_override("separation", 6)
	column.add_child(_list_box)

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

## 打开商店。mode 决定先展示哪一栏:Mode.SELL 卖粮 / Mode.BUY 买种子
func open_shop(npc: NpcBase, mode: int = Mode.SELL) -> void:
	_npc = npc
	_mode = mode
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh()

func close_shop() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed.emit()

func is_open() -> bool:
	return visible

func set_mode(mode: int) -> void:
	_mode = mode
	_refresh()

func mode() -> int:
	return _mode

## 卖粮(结算走 Shop,和对话里的『卖粮』同一套价格)
func sell_crop(crop_id: String, amount: int) -> Dictionary:
	var player: PlayerProfile = GameStateManager.state.player
	var res := Shop.sell_crop(player, _npc, crop_id, amount)
	_show_result(String(res.get("message", "")))
	_refresh()
	return res

## 买东西
func buy_item(item_id: String, count: int) -> Dictionary:
	var player: PlayerProfile = GameStateManager.state.player
	var res := Shop.buy_item(player, item_id, count)
	_show_result(String(res.get("message", "")))
	_refresh()
	return res

## 重新读一次背包与余额(买卖之后刷新)
func refresh() -> void:
	_refresh()

## 卖出按钮(给自测点按钮用 —— 确认按钮绑的作物没串)
func sell_buttons() -> Array:
	var out: Array = []
	if _list_box == null:
		return out
	for child in _list_box.get_children():
		if child is Button and not String(child.text).begins_with("收摊"):
			out.append(child)
	return out

func _show_result(text: String) -> void:
	if _message_label != null:
		_message_label.text = text

func _refresh() -> void:
	if _list_box == null:
		return
	for child in _list_box.get_children():
		# 先摘出树再释放 —— 留在树里的旧按钮还能被点到,会卖错作物
		_list_box.remove_child(child)
		child.queue_free()
	var player: PlayerProfile = GameStateManager.state.player
	if _gold_label != null:
		_gold_label.text = "兜里的钱:%d 文" % (player.gold if player != null else 0)
	if _title_label != null:
		var shop_name := _npc.name if _npc != null else "杂货铺"
		_title_label.text = "%s的柜台 —— 卖粮" % shop_name if _mode == Mode.SELL \
			else "%s的柜台 —— 买种子" % shop_name
	if _mode == Mode.SELL:
		_fill_sell_list(player)
	else:
		_fill_buy_list(player)

func _fill_sell_list(player: PlayerProfile) -> void:
	var entries := Shop.sellable_crops(player, _npc)
	if entries.is_empty():
		_add_line("兜里没有能卖的庄稼。", ITEM_DIM)
	for entry in entries:
		var crop_id := String(entry.get("crop_id", ""))
		var label := "卖 %d 个%s · 共 %d 文" % [
			int(entry.get("amount", 0)), entry.get("name", ""), int(entry.get("total", 0))]
		_add_button(label, func(): sell_crop(crop_id, int(entry.get("amount", 0))))
	_add_button("收摊(ESC)", func(): close_shop())

func _fill_buy_list(player: PlayerProfile) -> void:
	var entries := Shop.purchasable_items(player)
	for entry in entries:
		var item_id := String(entry.get("item_id", ""))
		var price := int(entry.get("price", 0))
		var affordable := bool(entry.get("affordable", false))
		var label := "买 %s · %d 文" % [entry.get("name", ""), price]
		if not affordable:
			_add_line(label + "(钱不够)", ITEM_DIM)
			continue
		_add_button(label, func(): buy_item(item_id, 1))
	_add_button("收摊(ESC)", func(): close_shop())

func _add_line(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", color)
	_list_box.add_child(label)

func _add_button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", ITEM_COLOR)
	button.add_theme_color_override("font_hover_color", ITEM_HOVER)
	button.pressed.connect(action)
	_list_box.add_child(button)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_shop()
