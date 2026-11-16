extends SceneTree
## headless 明信片自测:寄信 → 在途 → 次日投递 → 收藏 → 存档。
##
## 运行: godot --headless --script res://scripts/tests/test_postcard.gd
##
## T02 的自动化守门测试:邮局必须能进、信必须真寄出去、回信必须在次日到、
## 收藏册必须显示,而且存档往返不能把在途信件弄丢。

var _passed := 0
var _failed := 0
var _game: Node = null

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== 《麦溪镇》明信片自测 (postcard test) ===")
	print("设定:一封信走一天,邮差把远方的回信捎回来")
	print("--------------------------------------------------")
	_test_data()
	_test_send_and_delivery()
	_test_cross_year_delivery()
	_test_save_roundtrip()
	_test_cloud_mirror()
	await _test_post_office_wiring()
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

func _panel(panel_name: String) -> Node:
	return _game.find_child(panel_name, true, false)

func _mgr() -> Node:
	return root.get_node("GameStateManager")

# --- [1] 数据表 ---
func _test_data() -> void:
	print("\n[1] 明信片数据")
	var recipients := PostcardData.all_recipients()
	var cards := PostcardData.all_postcards()
	check("有 3 位远方联系人", recipients.size() == 3, "→ %d 位" % recipients.size())
	check("有 6 张回信明信片", cards.size() == 6, "→ %d 张" % cards.size())
	check("投递间隔为 1 天", PostcardData.delivery_days() == 1,
		"→ %d 天" % PostcardData.delivery_days())

	var recipient_ids := {}
	for recipient in recipients:
		recipient_ids[String(recipient.get("id", ""))] = true
		check("联系人%s有名字" % recipient.get("id", "?"), String(recipient.get("name", "")) != "")
		check("联系人%s有 2 段回信" % recipient.get("id", "?"),
			PostcardData.reply_ids(String(recipient.get("id", ""))).size() == 2)

	var all_have_body := true
	for card in cards:
		if String(card.get("title", "")) == "" or String(card.get("body", "")) == "":
			all_have_body = false
		if not recipient_ids.has(String(card.get("recipient_id", ""))):
			all_have_body = false
	check("每张明信片都有标题、正文和真实联系人", all_have_body)

# --- [2] 寄信与次日投递 ---
func _test_send_and_delivery() -> void:
	print("\n[2] 寄信与次日投递")
	var state := GameState.new()
	var cal := state.calendar
	cal.advance_to_month(4, 1)
	check("初始没有在途信件", PostcardSystem.pending_count(state) == 0)
	check("初始收藏册为空", PostcardSystem.collected_postcards(state).is_empty())
	check("状态行提示可以寄信",
		PostcardSystem.status_text(state, cal).contains("可以寄一封"))

	var bad := PostcardSystem.send(state, cal, "no_such_recipient")
	check("错误地址寄不出去", not bool(bad.get("ok", true)))

	var sent := PostcardSystem.send(state, cal, "aunt_inland")
	check("寄给远方姑妈成功", bool(sent.get("ok", false)),
		"→ " + String(sent.get("message", "")))
	check("信进入在途队列", PostcardSystem.pending_count(state) == 1)
	check("在途时还没收到明信片", PostcardSystem.collected_postcards(state).is_empty())
	check("状态行显示在途", PostcardSystem.status_text(state, cal).contains("在途"),
		"→ " + PostcardSystem.status_text(state, cal))

	var again := PostcardSystem.send(state, cal, "uncle_hills")
	check("邮车走了不能再寄第二封", not bool(again.get("ok", true)),
		"→ " + String(again.get("message", "")))

	var same_day := PostcardSystem.deliver_due(state, cal)
	check("当天不会提前到信", same_day.is_empty(), "→ %d 封" % same_day.size())
	cal.advance_day()
	var delivered := PostcardSystem.deliver_due(state, cal)
	check("第二天收到 1 张明信片", delivered.size() == 1, "→ %d 张" % delivered.size())
	check("收到的是第一段回信", String(delivered[0].get("id", "")) == "pc_wheat_field")
	check("明信片进入收藏册", PostcardSystem.collected_postcards(state).size() == 1)
	check("在途队列已清空", PostcardSystem.pending_count(state) == 0)

	var next_send := PostcardSystem.send(state, cal, "aunt_inland")
	check("同一联系人可以继续写第二封信", bool(next_send.get("ok", false)),
		"→ " + String(next_send.get("message", "")))
	check("下一张是第二段回信",
		String(next_send.get("card_id", "")) == "pc_paper_kite")
	cal.advance_day()
	PostcardSystem.deliver_due(state, cal)
	var exhausted := PostcardSystem.send(state, cal, "aunt_inland")
	check("这一路故事收齐后不再重复",
		not bool(exhausted.get("ok", true)),
		"→ " + String(exhausted.get("message", "")))
	check("收藏册现在有 2 张", PostcardSystem.collected_postcards(state).size() == 2)

# --- [3] 跨年投递 ---
func _test_cross_year_delivery() -> void:
	print("\n[3] 跨年投递")
	var state := GameState.new()
	var cal := state.calendar
	cal.year = 1
	cal.day_of_year = GameCalendar.DAYS_PER_YEAR - 1
	var sent := PostcardSystem.send(state, cal, "penpal_south")
	check("年末寄信成功", bool(sent.get("ok", false)))
	cal.advance_day()
	check("日期跨到第 2 年", cal.year == 2 and cal.day_of_year == 0,
		"→ 第 %d 年 %d 天" % [cal.year, cal.day_of_year])
	var delivered := PostcardSystem.deliver_due(state, cal)
	check("跨年后仍能收到回信", delivered.size() == 1)

# --- [4] 存档往返 ---
func _test_save_roundtrip() -> void:
	print("\n[4] 在途与收藏写进存档")
	var state := GameState.new()
	state.calendar.advance_to_month(5, 1)
	PostcardSystem.send(state, state.calendar, "uncle_hills")
	var copy := GameState.from_dict(state.to_dict())
	check("读档后在途信件还在", copy.postcards_pending.size() == 1)
	check("读档后在途明信片 id 正确",
		String(copy.postcards_pending[0].get("postcard_id", "")) == "pc_coal_stove")
	copy.calendar.advance_day()
	var delivered := PostcardSystem.deliver_due(copy, copy.calendar)
	check("读档后次日仍能投递", delivered.size() == 1)
	var copy2 := GameState.from_dict(copy.to_dict())
	check("收藏结果写进存档", copy2.postcards_collected.size() == 1)
	check("读档后收藏册能显示",
		PostcardSystem.collected_postcards(copy2).size() == 1)

# --- [5] 云存档镜像 ---
func _test_cloud_mirror() -> void:
	print("\n[5] 云存档镜像与本地回退")
	var old_cloud := OS.get_environment(SaveSync.CLOUD_DIR_ENV)
	OS.set_environment(SaveSync.CLOUD_DIR_ENV, "user://test_cloud")
	check("配置云目录后适配层启用", SaveSync.is_configured())

	var state := GameState.new()
	state.calendar.advance_to_month(6, 1)
	PostcardSystem.send(state, state.calendar, "penpal_south")
	_mgr().state = state
	check("写存档成功", _mgr().save_game(97))
	var cloud_path := SaveSync.slot_path(97)
	check("存档已镜像到云目录", FileAccess.file_exists(cloud_path),
		"→ " + cloud_path)

	DirAccess.remove_absolute("user://saves/slot_97.json")
	_mgr().state = GameState.new()
	check("只有云端档时主菜单仍显示可继续", _mgr().has_save(97))
	check("本地存档缺失时从云目录回退读档", _mgr().load_game(97))
	check("云存档读回后收藏/在途仍正确",
		_mgr().state.postcards_pending.size() == 1,
		"→ %d 封在途" % _mgr().state.postcards_pending.size())
	check("云存档读回后会写本地缓存",
		FileAccess.file_exists("user://saves/slot_97.json"))

	DirAccess.remove_absolute(cloud_path)
	DirAccess.remove_absolute("user://saves/slot_97.json")
	OS.set_environment(SaveSync.CLOUD_DIR_ENV, old_cloud)
	check("清理后用回原云目录配置",
		OS.get_environment(SaveSync.CLOUD_DIR_ENV) == old_cloud)

# --- [6] 场景与 UI 接线 ---
func _test_post_office_wiring() -> void:
	print("\n[6] 邮局场景与寄信按钮接线")
	check("场景路由已登记 L05", SceneRouter.is_implemented("L05"))
	check("L05 指向老邮局场景",
		SceneRouter.scene_path("L05") == "res://scenes/locations/L05.tscn")

	var packed: PackedScene = load("res://scenes/game.tscn")
	_game = packed.instantiate()
	root.add_child(_game)
	await create_timer(0.3).timeout

	var world: Node2D = _game.get_node("World")
	world.get_child(0)._go_to_town()
	await create_timer(0.3).timeout
	check("镇大街可前往邮局", world.get_child(0).has_method("_go_to_post_office"))
	world.get_child(0)._go_to_post_office()
	await create_timer(0.3).timeout
	check("已进入老邮局", String(world.get_child(0).name) == "PostOffice",
		"→ %s" % String(world.get_child(0).name))
	var key_hint: Label = _game.get_node_or_null("HUD/BottomBox/KeyHint")
	check("邮局按键提示写明寄信", key_hint != null and key_hint.text.contains("寄信"),
		"→ " + (key_hint.text if key_hint != null else "无"))

	var panel = _panel("PostcardPanel")
	check("游戏外壳里有邮册面板", panel != null)
	check("邮册一开始是关的", panel != null and not panel.is_open())
	world.get_child(0)._open_postbox()
	await create_timer(0.1).timeout
	check("按 E 后邮册打开", panel.is_open())
	check("打开邮册时锁住移动", _mgr().input_locked)
	check("面板显示收藏册进度", panel.body_text().contains("已收"),
		"→ " + panel.body_text().substr(0, 40))
	check("面板列出 3 位联系人", panel.send_buttons().size() == 3,
		"→ %d 个" % panel.send_buttons().size())

	var buttons: Array = panel.send_buttons()
	if buttons.size() == 3:
		buttons[0].pressed.emit()
		await create_timer(0.1).timeout
	check("点第一位联系人后信寄出",
		_mgr().state.postcards_pending.size() == 1,
		"→ %d 封在途" % _mgr().state.postcards_pending.size())
	check("寄出后面板显示在途", panel.status_text().contains("在途"),
		"→ " + panel.status_text())
	check("寄出后在途时按钮被禁用",
		panel.send_buttons().size() == 3 and panel.send_buttons()[0].disabled)

	world.get_child(0)._wait_one_day()
	await create_timer(0.1).timeout
	var collected: Array = _mgr().state.postcards_collected
	check("邮局里等一天后收到回信", collected.size() == 1,
		"→ %d 张" % collected.size())
	check("收藏册立刻显示新明信片",
		panel.body_text().contains(String(PostcardData.get_postcard(collected[0]).get("title", ""))),
		"→ " + panel.body_text().substr(0, 60))

	panel.close_panel()
	check("合上邮册后归还输入", not _mgr().input_locked)
	game_queue_free()
	await create_timer(0.1).timeout

func game_queue_free() -> void:
	if _game != null:
		_game.queue_free()
		_game = null
