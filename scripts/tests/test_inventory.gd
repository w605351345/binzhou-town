extends SceneTree
## headless 背包自测:清单逻辑 + Tab 开合
##
## 运行: godot --headless --script res://scripts/tests/test_inventory.gd
##
## 背包是玩家唯一的"收成总账" —— 麦溪镇一年一熟,一季的粮卖没卖掉、
## 剩多少种,全得在这一格里看得见。

var _passed := 0
var _failed := 0
var _game: Node = null

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== 《麦溪镇》背包自测 (inventory test) ===")
	print("设定:一年一熟,一季的收成全在这一格里")
	print("--------------------------------------------------")
	await _test_list_entries()
	await _test_panel_opens()
	print("--------------------------------------------------")
	print("结果: %d 通过 / %d 失败" % [_passed, _failed])
	if _failed > 0:
		print("❌ TEST FAILED")
		quit(1)
	else:
		print("✅ ALL TESTS PASSED")
		quit(0)

func check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  ✅ %s %s" % [label, detail])
	else:
		_failed += 1
		print("  ❌ %s %s" % [label, detail])

func _mgr() -> Node:
	return root.get_node("GameStateManager")

func _panel(panel_name: String) -> Node:
	return _game.find_child(panel_name, true, false)

func _check_inner_visible(panel: Node, label: String) -> void:
	var inner := panel.get_node_or_null("Panel") as Control
	var viewport_rect := Rect2(Vector2.ZERO, _game.get_viewport_rect().size)
	check("%s面板完整落在视口内" % label,
		inner != null and viewport_rect.encloses(inner.get_global_rect()),
		"→ %s / %s" % [inner.get_global_rect() if inner != null else "缺失", viewport_rect])

# --- 清单逻辑 ---
func _test_list_entries() -> void:
	print("\n[1] 背包清单逻辑")
	var inv := {"corn": 4, "seed_corn": 2, "food_sour_cabbage": 1}
	var entries: Array = Inventory.list_entries(inv)
	check("清单有 3 项", entries.size() == 3, "→ %d 项" % entries.size())

	var corn: Dictionary = {}
	for e in entries:
		if String(e.get("id", "")) == "corn":
			corn = e
	check("玉米有中文名", String(corn.get("name", "")) == "玉米",
		"→ " + String(corn.get("name", "")))
	check("玉米数量对", int(corn.get("count", 0)) == 4)
	check("作物归到『庄稼』栏", String(corn.get("kind", "")) == "crop",
		"→ " + String(corn.get("kind", "")))

	var seed: Dictionary = {}
	for e in entries:
		if String(e.get("id", "")) == "seed_corn":
			seed = e
	check("种子有中文名", String(seed.get("name", "")) == "玉米种",
		"→ " + String(seed.get("name", "")))
	check("种子归到『物件』栏", String(seed.get("kind", "")) == "item",
		"→ " + String(seed.get("kind", "")))

	# 空背包 / 数量为 0 的不占位
	check("空背包是空清单", Inventory.list_entries({}).is_empty())
	var zero: Array = Inventory.list_entries({"corn": 0})
	check("数量为 0 的不占位", zero.is_empty(), "→ %d 项" % zero.size())

	# 未知 id 也要显示,不能凭空消失(数据表漏了一条就看得出来)
	var unknown: Array = Inventory.list_entries({"mystery_item": 2})
	check("未知道具也列出", unknown.size() == 1)
	check("未知道具用 id 当名字", String(unknown[0].get("name", "")) == "mystery_item")

	# 作物与物件分开
	check("作物栏与物件栏分开数",
		Inventory.entries_of_kind(inv, "crop").size() == 1)
	check("物件栏只统计物件",
		Inventory.entries_of_kind(inv, "item").size() == 2)

# --- 背包面板 ---
func _test_panel_opens() -> void:
	print("\n[2] Tab 开合背包面板")
	root.size = Vector2i(1920, 1080)
	await process_frame
	var packed: PackedScene = load("res://scenes/game.tscn")
	_game = packed.instantiate()
	root.add_child(_game)
	await create_timer(0.3).timeout

	var player_state: PlayerProfile = _mgr().state.player
	player_state.inventory["corn"] = 4
	player_state.inventory["seed_corn"] = 2

	# 刻意不写类型标注:在 --script 主脚本里引用 UI class 会让它在
	# autoload 注册之前被编译(那时 GameStateManager 还不是全局标识符)
	var ui: Node = _game.get_node_or_null("UI")
	var overlay_root: Control = ui.get_node_or_null("OverlayRoot") if ui != null else null
	check("所有弹层在独立 UI CanvasLayer", ui is CanvasLayer)
	check("UI 有全屏 OverlayRoot", overlay_root != null)

	var panel: Node = _panel("InventoryPanel")
	check("游戏外壳里有背包面板", panel != null)
	check("背包面板挂在 OverlayRoot 下", panel != null and panel.get_parent() == overlay_root)
	check("背包一开始是关的", not panel.is_open())
	check("背包长清单有滚动区",
		panel.find_child("BodyScroll", true, false) is ScrollContainer)

	# UI 根节点挂在 Node2D 下时不会自动继承视口尺寸。根节点一旦是 0×0,
	# 居中的面板会整块缩到左上角,真实窗口里只剩一块黑边。
	var viewport_size: Vector2 = _game.get_viewport_rect().size
	var overlays := [
		"InventoryPanel", "DialogueBox", "ShopPanel", "GiftPanel",
		"FishingPanel", "CookingPanel", "QuestPanel", "ServicePanel",
		"PostcardPanel",
	]
	for overlay_name in overlays:
		var overlay: Control = _panel(overlay_name)
		check("%s 根节点覆盖视口" % overlay_name,
			overlay != null and overlay.size.distance_to(viewport_size) < 1.0,
			"→ %s / %s" % [overlay.size if overlay != null else "缺失", viewport_size])
	var inner: Control = panel.get_node_or_null("Panel")
	check("背包面板在视口内居中", inner != null and inner.position.x > 0.0
		and inner.position.y > 0.0,
		"→ %s %s" % [inner.position if inner != null else "缺失",
			inner.size if inner != null else "缺失"])

	panel.toggle()
	await create_timer(0.1).timeout
	check("打开后背包可见", panel.is_open())
	check("背包里显示玉米", panel.body_text().contains("玉米"),
		"→ " + panel.body_text().substr(0, 40))
	check("背包里显示种子", panel.body_text().contains("玉米种"))
	check("背包里显示数量", panel.body_text().contains("×4"),
		"→ " + panel.body_text().substr(0, 40))
	check("打开背包时锁住移动", _mgr().input_locked)

	panel.toggle()
	await create_timer(0.1).timeout
	check("再开一次就关上", not panel.is_open())
	check("关上后归还输入", not _mgr().input_locked)

	# 背包内容变了要能刷新
	player_state.inventory["corn"] = 9
	panel.toggle()
	await create_timer(0.1).timeout
	check("刷新后显示新数量", panel.body_text().contains("×9"),
		"→ " + panel.body_text().substr(0, 40))
	panel.toggle()

	print("\n[3] 其余常驻面板的窗口内布局")
	var panel_cases := [
		["商店", "ShopPanel"], ["送礼", "GiftPanel"], ["钓鱼", "FishingPanel"],
		["烹饪", "CookingPanel"], ["公告板", "QuestPanel"],
		["功能服务", "ServicePanel"], ["明信片", "PostcardPanel"],
	]
	var shop := _panel("ShopPanel")
	shop.open_shop(null, 0)
	await process_frame
	_check_inner_visible(shop, "商店")
	check("商店打开后键盘焦点可用", _game.get_viewport().gui_get_focus_owner() is Button)
	check("商店长清单有滚动区",
		shop.find_child("ListScroll", true, false) is ScrollContainer)
	shop.close_shop()

	var gift := _panel("GiftPanel")
	gift.open_for(NpcRegistry.get_npc("zhang_xiaofang"), true)
	await process_frame
	_check_inner_visible(gift, "送礼")
	check("送礼打开后键盘焦点可用", _game.get_viewport().gui_get_focus_owner() is Button)
	gift.close_panel()

	var fishing := _panel("FishingPanel")
	fishing.open_round(123, "winter")
	await process_frame
	_check_inner_visible(fishing, "钓鱼")
	check("钓鱼打开后收线按钮有焦点",
		_game.get_viewport().gui_get_focus_owner() is Button)
	fishing.close_panel()

	var cooking := _panel("CookingPanel")
	cooking.open_panel()
	await process_frame
	_check_inner_visible(cooking, "烹饪")
	check("烹饪打开后键盘焦点可用", _game.get_viewport().gui_get_focus_owner() is Button)
	cooking.close_panel()

	var quests := _panel("QuestPanel")
	quests.open_panel()
	await process_frame
	_check_inner_visible(quests, "公告板")
	check("公告板打开后键盘焦点可用", _game.get_viewport().gui_get_focus_owner() is Button)
	quests.close_panel()

	var services := _panel("ServicePanel")
	services.open_service("crafting")
	await process_frame
	_check_inner_visible(services, "功能服务")
	check("功能服务打开后键盘焦点可用", _game.get_viewport().gui_get_focus_owner() is Button)
	services.close_panel()

	var postcard := _panel("PostcardPanel")
	postcard.open_panel()
	await process_frame
	_check_inner_visible(postcard, "明信片")
	check("明信片打开后键盘焦点可用", _game.get_viewport().gui_get_focus_owner() is Button)
	postcard.close_panel()
	for case in panel_cases:
		check("面板节点存在:%s" % case[0], _panel(case[1]) != null)
