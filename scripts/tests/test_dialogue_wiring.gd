extends SceneTree
## headless 对话接线自测:E 键 → 对话框 → 选项 → 商店 → 好感度/标记写回
##
## 运行: godot --headless --script res://scripts/tests/test_dialogue_wiring.gd
##
## 这组测试守住一条底线:**对话系统必须在游戏里真的能打开**。
## 对话逻辑写得再漂亮,没接进 E 键就等于没做。

var _passed := 0
var _failed := 0
var _game: Node = null

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== 《宾州小镇》对话接线自测 (dialogue wiring test) ===")
	print("设定:黑龙江的黑土地上,张婶的话是玩家学会种地的主要途径")
	print("--------------------------------------------------")
	await _test_dialogue_opens()
	await _test_option_navigation()
	await _test_flag_persists()
	await _test_shop_wiring()
	await _test_affection_persists()
	await _test_movement_locked()
	await _test_npc_daily_position()
	print("--------------------------------------------------")
	print("结果: %d 通过 / %d 失败" % [_passed, _failed])
	if _failed > 0:
		print("❌ TEST FAILED")
		quit(1)
	else:
		print("✅ ALL TESTS PASSED")
		quit(0)

## headless --script 模式下 autoload 不是全局标识符,只能按节点路径取
## (和 scripts/tests/test_core.gd 同一个约定)
func _mgr() -> Node:
	return root.get_node("GameStateManager")

func check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  ✅ %s %s" % [label, detail])
	else:
		_failed += 1
		print("  ❌ %s %s" % [label, detail])

## 造一个游戏外壳并走进镇大街
func _boot_to_town() -> void:
	var packed: PackedScene = load("res://scenes/game.tscn")
	_game = packed.instantiate()
	root.add_child(_game)
	await create_timer(0.3).timeout
	var world: Node2D = _game.get_node("World")
	world.get_child(0)._go_to_town()
	await create_timer(0.3).timeout

func _town() -> Node:
	var world: Node2D = _game.get_node("World")
	return world.get_child(0)

## 刻意不写类型标注:在 --script 主脚本里引用这些 class 会让它们在 autoload
## 注册之前被编译(那时 GameStateManager 还不是全局标识符)。
func _dialogue_box() -> Node:
	return _game.get_node_or_null("DialogueBox")

func _shop_panel() -> Node:
	return _game.get_node_or_null("ShopPanel")

## 把玩家挪到张婶正上方(默认朝下 = 面朝她)
func _stand_next_to_npc() -> void:
	var town := _town()
	var npc_node: Node2D = town.get_node("NpcContainer").get_child(0)
	var player: Node2D = town.get_node("Player")
	player.global_position = npc_node.global_position + Vector2(0, -40)

## 触发 E 键对话
func _talk() -> void:
	_stand_next_to_npc()
	_town()._interact()
	await create_timer(0.1).timeout

## 点某个选项(按文字)
func _press(text: String) -> bool:
	var box := _dialogue_box()
	if box == null:
		return false
	for button in box.option_buttons():
		if String(button.text).replace("· ", "") == text:
			button.pressed.emit()
			await create_timer(0.1).timeout
			return true
	return false

# --- [1] 对话框能打开 ---
func _test_dialogue_opens() -> void:
	print("\n[1] E 键打开对话框")
	await _boot_to_town()
	check("游戏外壳里有对话框节点", _dialogue_box() != null)
	check("游戏外壳里有商店面板节点", _shop_panel() != null)
	check("对话框一开始是关的", not _dialogue_box().is_open())

	await _talk()
	var box := _dialogue_box()
	check("按 E 后对话框打开", box.is_open())
	check("说话人是张婶", box.speaker_name() == "张婶", "→ %s" % box.speaker_name())
	check("有台词", box.body_text() != "", "→ " + box.body_text().substr(0, 18) + "…")
	# 1 月是猫冬季,台词必须对得上农时
	check("台词跟着农时走(1 月说猫冬)", box.body_text().contains("猫冬"),
		"→ " + box.body_text().substr(0, 24) + "…")
	var texts: Array = box.option_texts()
	check("有选项", texts.size() >= 7, "→ %d 个" % texts.size())
	check("有卖粮选项", texts.has("卖粮"))
	check("有收尾选项", texts.has("没别的了,走了"))
	check("对话时标记为打开", _mgr().dialogue_open)

# --- [2] 选项推进 ---
func _test_option_navigation() -> void:
	print("\n[2] 选项推进(问一句答一句)")
	await _talk()
	var box := _dialogue_box()
	check("点了『啥叫秋翻地?』", await _press("啥叫秋翻地?"))
	check("答的是秋翻地", box.body_text().contains("秋翻地"),
		"→ " + box.body_text().substr(0, 20) + "…")
	check("话题里能回到开场白", await _press("今年我也翻"))
	check("回到开场白", box.body_text().contains("猫冬"),
		"→ " + box.body_text().substr(0, 18) + "…")
	check("点了『没别的了,走了』", await _press("没别的了,走了"))
	check("对话结束,对话框关闭", not box.is_open())
	check("关闭后标记为不占用输入", not _mgr().dialogue_open)

# --- [3] 标记写回 ---
func _test_flag_persists() -> void:
	print("\n[3] 对话标记写回存档")
	await _talk()
	await _press("啥叫秋翻地?")
	await _press("今年我也翻")
	check("标记写进了 GameState.flags",
		bool(_mgr().state.flags.get("will_plough_autumn", false)),
		"→ " + str(_mgr().state.flags))
	await _press("没别的了,走了")

	# 重开对话,标记门控的选项应该出现
	await _talk()
	var box := _dialogue_box()
	var texts: Array = box.option_texts()
	check("重开对话后出现标记门控的选项",
		texts.has("您上次说秋翻地,我记着呢"),
		"→ " + str(texts))
	await _press("没别的了,走了")

# --- [4] 商店接线 ---
func _test_shop_wiring() -> void:
	print("\n[4] 商店接线(卖粮)")
	var player_state: PlayerProfile = _mgr().state.player
	player_state.gold = 500
	player_state.inventory["corn"] = 4
	await _talk()
	check("点了『卖粮』", await _press("卖粮"))
	var panel := _shop_panel()
	check("商店面板打开了", panel.is_open())
	var res: Dictionary = panel.sell_crop("corn", 4)
	check("卖粮成功", bool(res.get("ok", false)), "→ " + String(res.get("message", "")))
	check("金币到账 92", player_state.gold == 592, "→ %d" % player_state.gold)
	check("背包清空", int(player_state.inventory.get("corn", 0)) == 0)

	# 点面板上的按钮(而不是直接调方法)—— 确认按钮绑的条目没串
	player_state.inventory["corn"] = 2
	player_state.inventory["potato"] = 3
	panel.refresh()
	var buttons: Array = panel.sell_buttons()
	check("商店面板列出了两种作物", buttons.size() == 2, "→ %d 个" % buttons.size())
	if buttons.size() == 2:
		buttons[1].pressed.emit()
		await create_timer(0.1).timeout
		check("点第二个按钮卖的是土豆", int(player_state.inventory.get("potato", 0)) == 0,
			"→ 土豆剩 %d" % int(player_state.inventory.get("potato", 0)))
		check("点第二个按钮没误卖玉米", int(player_state.inventory.get("corn", 0)) == 2,
			"→ 玉米剩 %d" % int(player_state.inventory.get("corn", 0)))
	panel.close_shop()
	check("商店面板关闭", not panel.is_open())
	await _press("没别的了,走了")

	# 买种子
	player_state.gold = 100
	await _talk()
	await _press("买种子")
	check("买种子时商店面板也打开", _shop_panel().is_open())
	var buy: Dictionary = _shop_panel().buy_item("seed_corn", 1)
	check("买种子成功", bool(buy.get("ok", false)), "→ " + String(buy.get("message", "")))
	check("金币扣了 30", player_state.gold == 70, "→ %d" % player_state.gold)
	check("背包里有种子", int(player_state.inventory.get("seed_corn", 0)) == 1)
	_shop_panel().close_shop()
	await _press("没别的了,走了")

# --- [5] 好感度写回 ---
func _test_affection_persists() -> void:
	print("\n[5] 好感度写回(跨场景不丢)")
	await _talk()
	var town := _town()
	var npc: NpcBase = town.get_node("NpcContainer").get_child(0).npc
	npc.affection = 7
	await _press("没别的了,走了")
	check("好感度写进了 npc_relationships",
		_mgr().state.npc_affection("zhang_shen") == 7,
		"→ %d" % _mgr().state.npc_affection("zhang_shen"))

	# 重新进镇大街,张婶的好感度应该还在
	_town()._go_to_farm()
	await create_timer(0.3).timeout
	_town()._go_to_town()
	await create_timer(0.3).timeout
	var npc2: NpcBase = _town().get_node("NpcContainer").get_child(0).npc
	check("换场景后好感度还在", npc2.affection == 7, "→ %d" % npc2.affection)

# --- [7] 张婶每日换位 ---
func _test_npc_daily_position() -> void:
	print("\n[7] 张婶每日换位(早市/晌午/傍晚)")
	var cal: GameCalendar = _mgr().state.calendar
	cal.day_of_year = 0
	await _reenter_town()
	var pos0 := _npc_position()
	cal.day_of_year = 1
	await _reenter_town()
	var pos1 := _npc_position()
	check("第二天张婶换了个位置", pos0 != pos1, "→ %s → %s" % [pos0, pos1])
	cal.day_of_year = 2
	await _reenter_town()
	var pos2 := _npc_position()
	check("第三天又换了个位置", pos2 != pos1 and pos2 != pos0, "→ %s" % pos2)

## 重进镇大街(场景会重建,NPC 重新生成)
func _reenter_town() -> void:
	_town()._go_to_farm()
	await create_timer(0.3).timeout
	_town()._go_to_town()
	await create_timer(0.3).timeout

func _npc_position() -> Vector2:
	var npc_node: Node2D = _town().get_node("NpcContainer").get_child(0)
	return npc_node.global_position

# --- [6] 对话时锁住移动 ---
func _test_movement_locked() -> void:
	print("\n[6] 对话时锁住移动")
	await _talk()
	check("对话时输入被占用", _mgr().dialogue_open)
	await _press("没别的了,走了")
	check("对话结束后输入归还", not _mgr().dialogue_open)
