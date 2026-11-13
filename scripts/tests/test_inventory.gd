extends SceneTree
## headless 背包自测:清单逻辑 + Tab 开合
##
## 运行: godot --headless --script res://scripts/tests/test_inventory.gd
##
## 背包是玩家唯一的"收成总账" —— 黑龙江一年一熟,一季的粮卖没卖掉、
## 剩多少种,全得在这一格里看得见。

var _passed := 0
var _failed := 0
var _game: Node = null

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== 《宾州小镇》背包自测 (inventory test) ===")
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
	var packed: PackedScene = load("res://scenes/game.tscn")
	_game = packed.instantiate()
	root.add_child(_game)
	await create_timer(0.3).timeout

	var player_state: PlayerProfile = _mgr().state.player
	player_state.inventory["corn"] = 4
	player_state.inventory["seed_corn"] = 2

	# 刻意不写类型标注:在 --script 主脚本里引用 UI class 会让它在
	# autoload 注册之前被编译(那时 GameStateManager 还不是全局标识符)
	var panel: Node = _game.get_node_or_null("InventoryPanel")
	check("游戏外壳里有背包面板", panel != null)
	check("背包一开始是关的", not panel.is_open())

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
