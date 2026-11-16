extends SceneTree
## 可玩性回归:开局、HUD、近距离 E 交互、地块上下文农作与时间/体力消耗。

const Guidance = preload("res://scripts/core/guidance_system.gd")

var _passed := 0
var _failed := 0
var _game: Node = null

func _initialize() -> void:
	_run()

func check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  ✅ %s %s" % [label, detail])
	else:
		_failed += 1
		print("  ❌ %s %s" % [label, detail])

func _run() -> void:
	print("=== 《麦溪镇》可玩性回归 (playability test) ===")
	_test_long_loop_guidance()
	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(_game)
	await create_timer(0.35).timeout
	var world: Node2D = _game.get_node("World")
	var farm := world.get_child(0)
	var mgr := root.get_node("GameStateManager")
	var state: GameState = mgr.state
	check("新游戏从自家农场开始", String(farm.name) == "Farm", "→ %s" % farm.name)
	check("新游戏从春季第 1 天开始",
		state.calendar.get_season() == "spring" and state.calendar.get_season_day() == 1,
		"→ %s" % state.calendar.date_string())
	check("开局背包有种子", int(state.player.inventory.get("seed_corn", 0)) >= 6,
		"→ %s" % str(state.player.inventory))
	check("开局 HUD 文本含春季", String(_game.get_node("HUD/HBox/HudLabel").text).contains("春季"))
	var almanac_text := String(_game.get_node("HUD/HBox/AlmanacLabel").text)
	check("农事统计不重复显示可收", almanac_text.count("可收") <= 1,
		"→ %s" % almanac_text.replace("\n", " / "))
	check("精简 HUD 仍保留可读的农时倒计时",
		almanac_text.contains("初霜") and almanac_text.contains("播种窗"),
		"→ %s" % almanac_text)

	var farm_map := MapDatabase.get_map("L01")
	var farm_spawn := MapDatabase.spawn_point(farm_map)
	var house_door: Dictionary = {}
	var south_door: Dictionary = {}
	for door in farm_map.get("doors", []):
		if String(door.get("id", "")) == "farm_house":
			house_door = door
		elif String(door.get("id", "")) == "farm_south":
			south_door = door
	check("出生点就在农舍门前", not house_door.is_empty()
		and farm_spawn.distance_to(MapDatabase.door_rect(house_door).get_center()) < 520.0,
		"→ 出生 %s / 农舍门 %s" % [farm_spawn, MapDatabase.door_rect(house_door).get_center()])
	check("南门移到院内栅栏出口", not south_door.is_empty()
		and MapDatabase.door_rect(south_door).position.y <= 1840.0,
		"→ %s" % MapDatabase.door_rect(south_door))
	check("从出生点可走到南门", not south_door.is_empty()
		and MapDatabase.is_reachable(farm_map, farm_spawn,
			MapDatabase.door_rect(south_door).get_center()))

	var views: Array = farm._views
	check("农场有地块视图", views.size() >= 9, "→ %d" % views.size())
	var player: Node2D = farm.get_node("Player")
	var first: Node2D = views[0]
	player.global_position = first.global_position + Vector2(0, 24)
	await process_frame
	await process_frame
	check("靠近地块能识别目标", farm._plot_near_player() == 0,
		"→ %d" % farm._plot_near_player())
	check("地点提示包含 E 农作",
		String(farm.prompt_label.text).contains("E / A") and String(farm.prompt_label.text).contains("翻土"),
		"→ %s" % farm.prompt_label.text)
	check("统一 HUD 收到农作提示",
		String(_game.get_node("HUD/BottomBox/ContextLabel").text).contains("号地"),
		"→ %s" % _game.get_node("HUD/BottomBox/ContextLabel").text)

	var energy_before: int = state.player.energy
	var minute_before: int = state.clock.minute_of_day
	farm._interact()
	await process_frame
	check("E 靠近荒地直接翻土", state.farm.get_plot(0).state == FarmPlot.State.TILLED,
		"→ %d" % state.farm.get_plot(0).state)
	check("翻土消耗体力", state.player.energy < energy_before,
		"→ %d → %d" % [energy_before, state.player.energy])
	check("翻土推进游戏时间", state.clock.minute_of_day > minute_before,
		"→ %d → %d" % [minute_before, state.clock.minute_of_day])

	farm._interact()
	await process_frame
	check("再次 E 自动播种", state.farm.get_plot(0).crop_id != "",
		"→ %s" % state.farm.get_plot(0).crop_id)
	check("播种消耗了背包种子", int(state.player.inventory.get("seed_corn", 0)) < 6,
		"→ %s" % str(state.player.inventory))

	var tip: Control = _game.get_node("HUD/BottomBox/TipLabel")
	var key_hint: Control = _game.get_node("HUD/BottomBox/KeyHint")
	var context: Control = _game.get_node("HUD/BottomBox/ContextLabel")
	check("常驻提示与按键条隐藏", not tip.visible and not key_hint.visible,
		"→ tip=%s key=%s" % [tip.visible, key_hint.visible])
	player.global_position = Vector2(120, 120)
	await process_frame
	await process_frame
	check("离开目标后接近提示收起", not context.visible and String(farm.prompt_label.text) == "",
		"→ context=%s prompt=%s" % [context.visible, farm.prompt_label.text])

	# 玩家视角:靠近 NPC 按 E 必须打开可见对话,不能靠朝向或碰撞把自己卡住。
	_game._travel_to("L03")
	await create_timer(0.3).timeout
	var town := world.get_child(0)
	check("镇中心有可见 NPC 节点", town._npc_nodes.size() >= 1,
		"→ %d" % town._npc_nodes.size())
	state.clock.minute_of_day = 12 * 60 + 10
	town._refresh_npcs(true)
	await process_frame
	check("正午镇中心仍有可交谈 NPC", town._npc_nodes.size() >= 1,
		"→ %d" % town._npc_nodes.size())
	state.clock.minute_of_day = 8 * 60
	await process_frame
	await process_frame
	var npc_node = town._npc_nodes[0]
	check("NPC 有名字与实体碰撞",
		npc_node.label.text != "" and npc_node.get_node_or_null("NamePlate") != null
		and npc_node.get_node_or_null("Solid") != null,
		"→ %s" % npc_node.label.text)
	var far_npc = town._npc_nodes[0]
	town.player.global_position = far_npc.global_position + Vector2(360, 0)
	await process_frame
	await process_frame
	await process_frame
	far_npc = town._npc_nodes[0]
	check("远处 NPC 名字牌收起", not far_npc.nameplate_visible())
	var near_target: Vector2 = far_npc.global_position + Vector2(0, 48)
	town.player.global_position = near_target
	await process_frame
	await process_frame
	await process_frame
	var near_npc = town._npc_nodes[0]
	check("靠近 NPC 才显示名字牌", near_npc.nameplate_visible())
	check("靠近 NPC 能识别交互目标", not town._nearest_npc().is_empty())
	town._interact()
	await process_frame
	var dialogue: Control = _game.get_node("UI/OverlayRoot/DialogueBox")
	check("按 E 后对话可见且可继续", dialogue.is_open() and dialogue.option_buttons().size() > 0,
		"→ open=%s options=%d" % [dialogue.is_open(), dialogue.option_buttons().size()])
	dialogue.close()
	await process_frame
	check("关闭对话后归还世界输入", not mgr.input_locked)

	# 功能 NPC 同样用 E 直接进入服务面板,画面应有明确可操作内容。
	_game._travel_to("L08")
	await create_timer(0.3).timeout
	var workshop := world.get_child(0)
	var smith = null
	for candidate in workshop._npc_nodes:
		if candidate.npc != null and candidate.npc.service_type == "blacksmith":
			smith = candidate
			break
	check("木工房出现石铁山", smith != null,
		"→ %d 个 NPC" % workshop._npc_nodes.size())
	if smith == null:
		quit(1)
		return
	workshop.player.global_position = smith.global_position + Vector2(0, 48)
	await process_frame
	workshop._interact()
	await process_frame
	var service: Control = _game.get_node("UI/OverlayRoot/ServicePanel")
	check("功能 NPC 的 E 打开服务面板", service.is_open(),
		"→ %s" % service.service_type())
	check("服务面板有可点击操作", service.action_buttons().size() > 0,
		"→ %d 个按钮" % service.action_buttons().size())
	var pause_menu: CanvasLayer = _game.get_node("PauseMenu")
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	pause_menu._unhandled_input(escape)
	check("覆盖面板打开时 ESC 不会叠加暂停菜单", not pause_menu.visible)
	service.close_panel()
	await process_frame
	check("关闭服务后游戏继续", not mgr.input_locked)

	print("--------------------------------------------------")
	print("结果: %d 通过 / %d 失败" % [_passed, _failed])
	if _failed > 0:
		quit(1)
	else:
		quit(0)

func _test_long_loop_guidance() -> void:
	print("\n[0] 农事与古戏长线指引")
	var state := GameState.new()
	for i in Guidance.TARGET_PLOTS:
		var plot := state.farm.get_plot(i)
		plot.state = FarmPlot.State.PLANTED
		plot.crop_id = "corn"
		plot.last_watered_abs_day = state.calendar.abs_day()
		plot.last_watered_day = state.calendar.abs_day()
	state.flags["tutorial_talked"] = true
	state.flags["run_started_abs_day"] = state.calendar.abs_day() - 1
	state.flags["harvested_total"] = 3
	var drama_step := Guidance.current_step(state)
	check("收满三份作物后指引去月桂剧场",
		String(drama_step.get("title", "")).contains("月桂剧场"),
		"→ %s" % drama_step.get("title", ""))
	state.drama_progress = {
		"acts_completed": ["act1", "act2", "act3"],
		"node_index": {}, "choices": {}, "reputation": 30, "current_act": "",
	}
	state.flags["harvested_total"] = 8
	var postcard_step := Guidance.current_step(state)
	check("三幕结束后指引寄一封明信片",
		String(postcard_step.get("title", "")).contains("邮局"),
		"→ %s" % postcard_step.get("title", ""))
	state.flags["postcard_sent_once"] = true
	var daily_step := Guidance.current_step(state)
	check("完成旅行青蛙目标后回到日常经营",
		String(daily_step.get("title", "")).contains("日子"),
		"→ %s" % daily_step.get("title", ""))
