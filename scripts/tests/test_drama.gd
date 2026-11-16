extends SceneTree
## 古戏剧本自测:三幕解锁、九次选择、关系/奖励、存档与剧场面板接线。

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== 《月桂谣》古戏剧本自测 (drama test) ===")
	_test_data()
	_test_progression()
	_test_panel()
	await _test_theater_wiring()
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

func _test_data() -> void:
	print("\n[1] 三幕剧本数据")
	var acts := DramaSystem.all_acts()
	check("剧本共三幕", acts.size() == 3, "→ %d" % acts.size())
	var node_count := 0
	var choice_count := 0
	for act in acts:
		check("%s 有三场" % act.get("title", ""),
			Array(act.get("nodes", [])).size() == 3)
		for node in act.get("nodes", []):
			node_count += 1
			var choices: Array = node.get("choices", [])
			choice_count += choices.size()
			check("%s 提供三个分支" % node.get("id", ""), choices.size() == 3)
	check("共九个选择节点", node_count == 9, "→ %d" % node_count)
	check("共二十七个分支", choice_count == 27, "→ %d" % choice_count)

func _test_progression() -> void:
	print("\n[2] 选择推进、农事解锁与结局")
	var state := GameState.new()
	check("第一幕开局可演", DramaSystem.is_unlocked(state, "act1"))
	check("第二幕未完成农事时锁定", not DramaSystem.is_unlocked(state, "act2"))
	var begin := DramaSystem.begin_act(state, "act1")
	check("能翻开第一幕", bool(begin.get("ok", false)), begin.get("message", ""))
	var first_node := DramaSystem.current_node(state, "act1")
	check("当前戏页是第一场", first_node.get("id") == "a1_1")
	var option_id := String(Array(first_node.get("choices", []))[0].get("id", ""))
	var chosen := DramaSystem.choose(state, "act1", option_id)
	check("选择后推进到下一场", bool(chosen.get("ok", false)), chosen.get("message", ""))
	check("选择提升周德顺好感", state.npc_affection("zhou_deshun") >= 3,
		"→ %d" % state.npc_affection("zhou_deshun"))
	for i in 2:
		var node := DramaSystem.current_node(state, "act1")
		var choices: Array = node.get("choices", [])
		DramaSystem.choose(state, "act1", String(choices[0].get("id", "")))
	check("第一幕演完", DramaSystem.is_completed(state, "act1"))
	check("第一幕奖励到账", state.player.gold >= 80, "→ %d 文" % state.player.gold)
	check("第一幕完成也算公演评价", DramaSystem.reputation(state) >= 6,
		"→ %d" % DramaSystem.reputation(state))
	check("未累计三份作物时第二幕仍锁定", not DramaSystem.is_unlocked(state, "act2"))
	var progress_hint := DramaSystem.farm_progress_text(state)
	check("农事进度明确提示古戏解锁差距",
		progress_hint.contains("累计收获") and progress_hint.contains("还差")
		and progress_hint.contains("第二幕"), "→ %s" % progress_hint)

	state.flags["harvested_total"] = 3
	check("累计三份作物解锁第二幕", DramaSystem.is_unlocked(state, "act2"))
	DramaSystem.begin_act(state, "act2")
	for i in 3:
		var node := DramaSystem.current_node(state, "act2")
		var choices: Array = node.get("choices", [])
		DramaSystem.choose(state, "act2", String(choices[1].get("id", "")))
	check("第二幕演完", DramaSystem.is_completed(state, "act2"))
	check("未累计八份作物时第三幕锁定", not DramaSystem.is_unlocked(state, "act3"))

	state.flags["harvested_total"] = 8
	check("累计八份作物解锁终幕", DramaSystem.is_unlocked(state, "act3"))
	DramaSystem.begin_act(state, "act3")
	for i in 3:
		var node := DramaSystem.current_node(state, "act3")
		var choices: Array = node.get("choices", [])
		DramaSystem.choose(state, "act3", String(choices[0].get("id", "")))
	check("三幕全部完成", DramaSystem.all_completed(state))
	var ending := DramaSystem.ending(state)
	check("结局按公演评价给出", not ending.is_empty() and String(ending.get("title", "")) != "",
		String(ending.get("title", "")))

	var encoded := JSON.stringify(state.to_dict())
	var parsed: Variant = JSON.parse_string(encoded)
	var loaded := GameState.from_dict(parsed)
	check("选择进度写入存档", DramaSystem.completed_count(loaded) == 3,
		"→ %d" % DramaSystem.completed_count(loaded))
	check("公演评价写入存档", DramaSystem.reputation(loaded) == DramaSystem.reputation(state),
		"→ %d" % DramaSystem.reputation(loaded))
	check("人物关系写入存档", loaded.npc_affection("zhou_deshun") > 0,
		"→ %d" % loaded.npc_affection("zhou_deshun"))

func _test_panel() -> void:
	print("\n[3] 剧场面板")
	var mgr: Node = root.get_node_or_null("GameStateManager")
	if mgr == null:
		check("GameStateManager 已挂载", false)
		return
	mgr.new_session()
	var panel: Control = (load("res://scripts/ui/drama_panel.gd") as GDScript).new()
	root.add_child(panel)
	panel.open_panel()
	check("面板打开", panel.is_open())
	check("面板列出三幕", panel.act_buttons().size() == 3,
		"→ %d" % panel.act_buttons().size())
	check("第一幕可用、后两幕锁定",
		not panel.act_buttons()[0].disabled and panel.act_buttons()[1].disabled
		and panel.act_buttons()[2].disabled)
	panel.select_act("act1")
	check("选幕后出现三个分支", panel.choice_buttons().size() == 3,
		"→ %d" % panel.choice_buttons().size())
	check("面板正文包含戏页", panel.body_text().contains("月桂"),
		panel.body_text().substr(0, 40))
	var choice_id := String(Array(DramaSystem.current_node(mgr.state, "act1")
		.get("choices", []))[0].get("id", ""))
	panel.choose(choice_id)
	check("点击后推进剧情", DramaSystem.current_node(mgr.state, "act1").get("id") != "a1_1")
	panel.close_panel()
	check("关闭面板归还移动", not mgr.input_locked)
	panel.queue_free()
	mgr.new_session()

func _test_theater_wiring() -> void:
	print("\n[4] 月桂剧场交互接线")
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await create_timer(0.3).timeout
	game._travel_to("L11")
	await create_timer(0.3).timeout
	var world: Node = game.get_node("World")
	var theater: Node = world.get_child(0)
	var item := {"action": "theater", "label": "看戏", "id": "theater_stage"}
	theater._handle_interactable(item)
	await process_frame
	await process_frame
	var panel: Control = game.get_node("UI/OverlayRoot/DramaPanel")
	check("剧场互动打开古戏面板", panel.is_open())
	check("剧场面板可操作", panel.choice_buttons().size() + panel.act_buttons().size() > 0)
	panel.close_panel()
	await process_frame
	check("收戏后恢复世界输入", not root.get_node("GameStateManager").input_locked)
	game.queue_free()
	await process_frame
