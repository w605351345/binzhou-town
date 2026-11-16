extends Control
class_name ServicePanel

## 功能性玩法统一面板：一处 UI 覆盖制造、铁匠、畜牧、渔具、博物馆、
## 旅行货郎、运输箱、矿洞和公共工程。所有结算仍交给纯逻辑系统。

signal closed
signal gift_requested(npc_data: Dictionary)

const TEXT_COLOR := Color(0.94, 0.90, 0.80)
const TITLE_COLOR := Color(0.98, 0.82, 0.48)
const DIM_COLOR := Color(0.60, 0.57, 0.50)

var _panel: PanelContainer
var _title_label: Label
var _subtitle_label: Label
var _status_label: Label
var _list: VBoxContainer
var _service_type := ""
var _npc: NpcBase = null

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.02, 0.52)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(900, 720)
	_panel.position = Vector2(-450, -360)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.12, 0.08, 0.98)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.66, 0.46, 0.24, 0.92)
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
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", TITLE_COLOR)
	column.add_child(_title_label)
	_subtitle_label = Label.new()
	_subtitle_label.name = "Subtitle"
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.add_theme_font_size_override("font_size", 18)
	_subtitle_label.add_theme_color_override("font_color", Color(0.82, 0.78, 0.68))
	column.add_child(_subtitle_label)
	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0, 52)
	_status_label.add_theme_font_size_override("font_size", 19)
	_status_label.add_theme_color_override("font_color", TEXT_COLOR)
	column.add_child(_status_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 7)
	scroll.add_child(_list)
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "离开（ESC）"
	close.pressed.connect(close_panel)
	column.add_child(close)

func open_service(service_type: String, npc: NpcBase = null) -> void:
	_service_type = service_type
	_npc = npc
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameStateManager.set_service_open(true)
	if service_type == "mine":
		MiningSystem.enter(GameStateManager.state)
	_status_label.text = _intro_text(service_type)
	_refresh()
	_focus_first_button.call_deferred()

func close_panel() -> void:
	if not visible:
		return
	if _service_type == "mine":
		MiningSystem.retreat(GameStateManager.state)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStateManager.set_service_open(false)
	closed.emit()

func is_open() -> bool:
	return visible

func service_type() -> String:
	return _service_type

func action_buttons() -> Array:
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

func _intro_text(service_type: String) -> String:
	match service_type:
		"crafting": return "工作台上的工具按深浅排好，缺什么就补什么。"
		"blacksmith": return "炉火正旺。把农具递过去，石铁山先看刃口。"
		"livestock": return "草槽里有新添的料，牲口在棚里轻轻挪步。"
		"fishmonger": return "何水根把鱼篓翻过来，等你先开口。"
		"museum": return "展柜擦得发亮，标签纸还带着墨味。"
		"merchant": return "郎三顺拍拍担子：今天的货就这些，卖完就走。"
		"shipping": return "运输箱盖板结实，晚上会有人来拉货。"
		"mine": return "矿灯照出湿漉漉的石壁，深处有风。"
		"community": return "工程板上钉着镇上人凑出来的材料清单。"
	return "这里暂时没有可办的事。"

func _refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_title_label.text = _title_for(_service_type)
	_subtitle_label.text = _subtitle_for(_service_type)
	if _npc != null:
		_fill_npc_social()
	match _service_type:
		"crafting": _fill_crafting()
		"blacksmith": _fill_blacksmith()
		"livestock": _fill_livestock()
		"fishmonger": _fill_fishmonger()
		"museum": _fill_museum()
		"merchant": _fill_merchant()
		"shipping": _fill_shipping()
		"mine": _fill_mine()
		"community": _fill_community()
		_: _add_line("这里还没有可操作的内容。", DIM_COLOR)

func _fill_npc_social() -> void:
	var data := NpcRegistry.get_npc(_npc.id)
	if data.is_empty():
		return
	var rel := RelationshipSystem.relationship(GameStateManager.state, _npc.id)
	var affection := int(rel.get("affection", 0))
	var talked := bool(rel.get("talked_today", false))
	var gifted := bool(rel.get("gifted_today", false))
	_add_line("%s\n好感 %d/100 · %s" % [
		String(data.get("flavor", _npc.service_title)), affection,
		"今天聊过了" if talked else "还没好好说话"], TEXT_COLOR)
	_add_action("聊两句 · 听听%s的近况" % _npc.name, _talk_to_npc, talked)
	_add_action("送份礼 · 今天还没送过" if not gifted else "送份礼 · 今天已经送过了",
		_open_gift, gifted)

func _talk_to_npc() -> void:
	if _npc == null:
		return
	var result := RelationshipSystem.talk(GameStateManager.state, _npc.id)
	_status_label.text = "%s\n%s" % [_daily_line(), String(result.get("message", ""))]
	_refresh()

func _open_gift() -> void:
	if _npc == null:
		return
	var data := NpcRegistry.get_npc(_npc.id)
	if not data.is_empty():
		gift_requested.emit(data)

func _daily_line() -> String:
	if _npc == null:
		return ""
	var data := NpcRegistry.get_npc(_npc.id)
	var lines: Dictionary = data.get("daily_lines", {})
	var season := GameStateManager.state.calendar.get_season()
	return String(lines.get(season, data.get("flavor", _npc.service_title)))

func _title_for(service_type: String) -> String:
	if _npc != null and _npc.service_title != "":
		return _npc.service_title
	match service_type:
		"crafting": return "农具工作台 · 制造"
		"blacksmith": return "石铁山 · 农具升级"
		"livestock": return "牧云牧场 · 畜棚"
		"fishmonger": return "何水根 · 渔具与收鱼"
		"museum": return "麦溪镇史馆 · 捐赠"
		"merchant": return "郎三顺 · 今日货担"
		"shipping": return "农场运输箱"
		"mine": return "北山矿洞"
		"community": return "公共工程板"
	return "麦溪镇"

func _subtitle_for(service_type: String) -> String:
	var player: PlayerProfile = GameStateManager.state.player
	var gold_text := "金币 %d · 体力 %d" % [player.gold, player.energy]
	if service_type == "mine":
		return "%s\n%s" % [gold_text, MiningSystem.summary(GameStateManager.state)]
	if service_type == "livestock":
		return "%s\n%s" % [gold_text, LivestockSystem.summary(GameStateManager.state)]
	if service_type == "museum":
		return "%s · %s" % [gold_text, MuseumSystem.progress_text(GameStateManager.state)]
	if service_type == "community":
		return "%s · %s" % [gold_text, CommunityProjectSystem.progress_text(GameStateManager.state)]
	if service_type == "shipping":
		return "%s · 箱内待结 %d 文" % [gold_text,
			ShippingSystem.pending_value(GameStateManager.state)]
	return gold_text

func _fill_crafting() -> void:
	for recipe in CraftingSystem.all_recipes():
		var recipe_id := String(recipe.get("id", ""))
		var can := CraftingSystem.can_craft(GameStateManager.state, recipe_id)
		var text := "%s ×%d · %s\n%s" % [recipe.get("name", recipe_id),
			int(recipe.get("count", 1)), _ingredients_text(recipe), recipe.get("desc", "")]
		_add_action(text, func(): _craft(recipe_id), not can)

func _fill_blacksmith() -> void:
	for tool in ToolUpgradeSystem.all_tools():
		var tool_id := String(tool.get("id", ""))
		var level := ToolUpgradeSystem.current_level(GameStateManager.state.player, tool_id)
		var next := ToolUpgradeSystem.next_upgrade(GameStateManager.state.player, tool_id)
		if next.is_empty():
			_add_line("%s · 已到 %d 级，石铁山说再打就伤铁了。" % [
				tool.get("name", tool_id), level], DIM_COLOR)
			continue
		var can := ToolUpgradeSystem.can_upgrade(GameStateManager.state.player, tool_id)
		var text := "%s Lv.%d → %s · %d 文 · %s" % [tool.get("name", tool_id), level,
			next.get("name", "下一级"), int(next.get("cost", 0)),
			_materials_text(Dictionary(next.get("ingredients", {})))]
		_add_action(text, func(): _upgrade_tool(tool_id), not can)

func _fill_livestock() -> void:
	_add_action("买 5 捆草料 · %d 文" % (LivestockSystem.feed_price() * 5),
		func(): _buy_feed(5), false)
	_add_action("把棚里的牲口都喂一遍", func(): _feed_all(), false)
	for animal in LivestockSystem.all_animals():
		var animal_id := String(animal.get("id", ""))
		var text := "买 %s · %d 文\n%s" % [animal.get("name", animal_id),
			int(animal.get("cost", 0)), animal.get("desc", "")]
		_add_action(text, func(): _buy_animal(animal_id), false)
	_add_line(LivestockSystem.summary(GameStateManager.state), TEXT_COLOR)

func _fill_fishmonger() -> void:
	var cfg := ServiceCatalog.fishmonger()
	_add_action("买 %d 个鱼饵 · %d 文" % [int(cfg.get("bundle", 5)),
		int(cfg.get("bundle_price", 12))], func(): _buy_bait(), false)
	_add_action("把鱼篓里的鱼都卖给何水根", func(): _sell_fish(), false)
	_add_line("鱼饵会提高咬钩机会；越大的鱼越卖得上价。", DIM_COLOR)

func _fill_museum() -> void:
	for raw in MuseumSystem.all_collectibles():
		var item_id := String(raw.get("item_id", ""))
		var donated := MuseumSystem.is_donated(GameStateManager.state, item_id)
		var owned := int(GameStateManager.state.player.inventory.get(item_id, 0))
		var suffix := "已入柜" if donated else ("背包 ×%d" % owned if owned > 0 else "尚未收集")
		var text := "%s · %s\n%s" % [raw.get("name", item_id), suffix, raw.get("desc", "")]
		_add_action(text, func(): _donate_museum(item_id), not MuseumSystem.can_donate(GameStateManager.state, item_id))

func _fill_merchant() -> void:
	for entry in ServiceCatalog.merchant_stock(GameStateManager.state):
		var item_id := String(entry.get("item_id", ""))
		var text := "%s · %d 文\n%s" % [entry.get("name", item_id),
			int(entry.get("price", 0)), entry.get("desc", "")]
		_add_action(text, func(): _buy_merchant(item_id), false)

func _fill_shipping() -> void:
	var count := 0
	for entry in Inventory.list_entries(GameStateManager.state.player.inventory):
		var item_id := String(entry.get("id", ""))
		var amount := int(entry.get("count", 0))
		var unit := ShippingSystem.unit_price(GameStateManager.state, item_id)
		if unit <= 0 or amount <= 0:
			continue
		count += 1
		_add_action("放入全部 %s ×%d · 预计 %d 文" % [entry.get("name", item_id), amount,
			unit * amount], func(): _ship_item(item_id, amount), false)
	if count == 0:
		_add_line("背包里没有运输箱能收的东西。", DIM_COLOR)
	for entry in Array(GameStateManager.state.shipping.get("items", {}).keys()):
		var item_id := String(entry)
		_add_line("箱内：%s ×%d" % [ShippingSystem.display_name(item_id),
			int(GameStateManager.state.shipping["items"][entry])], TEXT_COLOR)

func _fill_mine() -> void:
	MiningSystem.ensure_state(GameStateManager.state)
	var mine: Dictionary = GameStateManager.state.mine
	var monster: Dictionary = mine.get("monster", {})
	_add_line("生命 %d/%d · 矿层 %d/%d · 已凿矿石 %d" % [
		int(mine.get("health", 100)), int(mine.get("max_health", 100)),
		int(mine.get("floor", 1)), MiningSystem.all_floors().size(),
		int(mine.get("ore_mined", 0))], TEXT_COLOR)
	if monster.is_empty():
		_add_action("抡镐凿矿（体力 -4）", func(): _mine_explore(), false)
		_add_action("沿石阶下一层", func(): _mine_descend(), false)
	else:
		_add_action("迎战 %s（生命 %d/%d）" % [monster.get("name", "守洞野兽"),
			int(monster.get("hp", 0)), int(monster.get("max_hp", 1))],
			func(): _mine_attack(), false)
	_add_action("收灯回洞口", func(): close_panel(), false)
	_add_line("战斗会消耗生命与体力；倒下只回洞口，不会丢档。", DIM_COLOR)

func _fill_community() -> void:
	for project in CommunityProjectSystem.all_projects():
		var project_id := String(project.get("id", ""))
		var completed := CommunityProjectSystem.is_completed(GameStateManager.state, project_id)
		var available := CommunityProjectSystem.is_available(GameStateManager.state, project_id)
		var header := "【%s】%s" % ["已完成" if completed else ("可交材料" if available else "尚未解锁"),
			project.get("name", project_id)]
		_add_line(header + "\n" + String(project.get("desc", "")), TEXT_COLOR)
		if not available:
			continue
		var progress := CommunityProjectSystem.progress_for(GameStateManager.state, project_id)
		var needs: Dictionary = project.get("requirements", {})
		for raw_id in needs.keys():
			var item_id := String(raw_id)
			var have := int(progress.get(item_id, 0))
			var need := int(needs[raw_id])
			var text := "交 1 个%s · %d/%d" % [
				ItemDatabase.get_item(item_id).get("name", item_id), have, need]
			_add_action(text, func(): _donate_community(project_id, item_id),
				not CommunityProjectSystem.can_donate(GameStateManager.state, project_id, item_id))

func _craft(recipe_id: String) -> void:
	var result := CraftingSystem.craft(GameStateManager.state, recipe_id)
	_status_label.text = String(result.get("message", ""))
	_refresh()

func _upgrade_tool(tool_id: String) -> void:
	var result := ToolUpgradeSystem.upgrade(GameStateManager.state.player, tool_id)
	_status_label.text = String(result.get("message", ""))
	_refresh()

func _buy_animal(animal_id: String) -> void:
	var result := LivestockSystem.buy_animal(GameStateManager.state, animal_id)
	_status_label.text = String(result.get("message", ""))
	_refresh()

func _buy_feed(count: int) -> void:
	var result := LivestockSystem.buy_feed(GameStateManager.state, count)
	_status_label.text = String(result.get("message", ""))
	_refresh()

func _feed_all() -> void:
	var result := LivestockSystem.feed_all(GameStateManager.state)
	_status_label.text = String(result.get("message", ""))
	_refresh()

func _buy_bait() -> void:
	var result := ServiceCatalog.buy_bait(GameStateManager.state)
	_status_label.text = String(result.get("message", ""))
	_refresh()

func _sell_fish() -> void:
	var result := ServiceCatalog.sell_fish(GameStateManager.state)
	_status_label.text = String(result.get("message", ""))
	_refresh()

func _donate_museum(item_id: String) -> void:
	var result := MuseumSystem.donate(GameStateManager.state, item_id)
	_status_label.text = String(result.get("message", ""))
	_refresh()

func _buy_merchant(item_id: String) -> void:
	var result := ServiceCatalog.buy_merchant_item(GameStateManager.state, item_id)
	_status_label.text = String(result.get("message", ""))
	_refresh()

func _ship_item(item_id: String, count: int) -> void:
	var result := ShippingSystem.add(GameStateManager.state, item_id, count)
	_status_label.text = String(result.get("message", ""))
	_refresh()

func _mine_explore() -> void:
	var result := MiningSystem.explore(GameStateManager.state)
	_status_label.text = String(result.get("message", ""))
	_refresh()

func _mine_attack() -> void:
	var result := MiningSystem.attack(GameStateManager.state)
	_status_label.text = String(result.get("message", ""))
	if bool(result.get("collapsed", false)):
		close_panel()
		return
	_refresh()

func _mine_descend() -> void:
	var result := MiningSystem.descend(GameStateManager.state)
	_status_label.text = String(result.get("message", ""))
	_refresh()

func _donate_community(project_id: String, item_id: String) -> void:
	var result := CommunityProjectSystem.donate(GameStateManager.state, project_id, item_id)
	_status_label.text = String(result.get("message", ""))
	_refresh()

func _ingredients_text(recipe: Dictionary) -> String:
	return _materials_text(Dictionary(recipe.get("ingredients", {})))

func _materials_text(needs: Dictionary) -> String:
	var parts: Array = []
	for raw_id in needs.keys():
		var item_id := String(raw_id)
		var need := int(needs[raw_id])
		var have := int(GameStateManager.state.player.inventory.get(item_id, 0))
		parts.append("%s %d/%d" % [ItemDatabase.get_item(item_id).get("name", item_id), have, need])
	return " · ".join(parts)

func _add_line(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", color)
	_list.add_child(label)

func _add_action(text: String, action: Callable, disabled: bool) -> void:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 17)
	button.disabled = disabled
	button.pressed.connect(action)
	_list.add_child(button)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()
