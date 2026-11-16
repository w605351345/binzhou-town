extends SceneTree
## 采集、钓鱼、烹饪、节日自测。
## 运行: godot --headless --script res://scripts/tests/test_activities.gd

var _passed := 0
var _failed := 0
var _game: Node = null

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== 《麦溪镇》四季活动自测 (activities test) ===")
	_test_forage()
	_test_fishing()
	_test_cooking()
	_test_festivals()
	_test_quests()
	_test_farm_expansion()
	await _test_panels_and_wiring()
	await _test_location_actions()
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

func _test_forage() -> void:
	print("\n[1] 四季采集与刷新")
	var summer_day := 180
	var map := MapDatabase.get_map("L10")
	var summer_cal := GameCalendar.new()
	summer_cal.from_absolute_day(summer_day)
	var points := ForageSystem.daily_points(map, summer_day)
	check("桦树林夏季有采集点", points.size() >= 2, "→ %d 个" % points.size())
	var mushroom := _find_point(points, "L10_mushroom")
	check("蘑菇点在夏季开放", not mushroom.is_empty())
	check("采集点带当日物品", not Array(mushroom.get("items", [])).is_empty())
	check("互动点能解析到季节采集点",
		ForageSystem.point_key_for(map, "forest_mushroom", summer_cal) == "L10_mushroom")
	var winter_cal := GameCalendar.new()
	winter_cal.from_absolute_day(30)
	check("冬季互动点不会误指向蘑菇",
		ForageSystem.point_key_for(map, "forest_mushroom", winter_cal) == "")

	var state := GameState.new()
	state.calendar.from_absolute_day(summer_day)
	var before := state.calendar.abs_day()
	var first := ForageSystem.collect(state, "L10_mushroom")
	check("采集成功", bool(first.get("ok", false)), String(first.get("message", "")))
	check("采集物进背包", int(state.player.inventory.get(String(first.get("item_id", "")), 0)) > 0)
	check("同一天不能重复采", not bool(ForageSystem.collect(state, "L10_mushroom").get("ok", true)))
	state.calendar.from_absolute_day(before + 3)
	check("过完刷新期又能采", bool(ForageSystem.collect(state, "L10_mushroom").get("ok", false)))

	var winter_points := ForageSystem.daily_points(MapDatabase.get_map("L10"), 30)
	check("冬季蘑菇点关闭", _find_point(winter_points, "L10_mushroom").is_empty())
	check("冬季仍有拾柴点", not _find_point(winter_points, "L10_wood").is_empty())

	var all_item_ids := {}
	for point in ForageSystem.all_points():
		for item in point.get("items", []):
			all_item_ids[String(item.get("id", ""))] = true
	check("山货达到设计数量 12 种", all_item_ids.size() >= 12,
		"→ %d 种" % all_item_ids.size())
	for season in ["spring", "summer", "autumn", "winter"]:
		var season_cal := GameCalendar.new()
		season_cal.advance_to_month(_month_for_season(season), 10)
		var active := 0
		for map_id in MapDatabase.all_ids():
			active += ForageSystem.daily_points(MapDatabase.get_map(map_id),
				season_cal.abs_day()).size()
		check("%s 季至少 3 个采集点" % season, active >= 3, "→ %d 个" % active)

func _month_for_season(season: String) -> int:
	match season:
		"spring": return 4
		"summer": return 7
		"autumn": return 9
		"winter": return 12
	return 4

func _find_point(points: Array, key: String) -> Dictionary:
	for point in points:
		if String(point.get("key", "")) == key:
			return point
	return {}

func _test_fishing() -> void:
	print("\n[2] 鱼种季节池与收线窗口")
	check("鱼种达到设计数量 8 种", FishingSystem.all_fish().size() >= 8,
		"→ %d 种" % FishingSystem.all_fish().size())
	var spring := FishingSystem.new()
	spring.start(12345, "spring")
	var fish_spring := spring.target_fish()
	check("春季有目标鱼", not fish_spring.is_empty(), str(fish_spring))
	check("春季只出春季鱼", String(fish_spring.get("season", "")) in ["spring", ""],
		"→ %s" % fish_spring.get("season"))
	var same := FishingSystem.new()
	same.start(12345, "spring")
	check("同种子目标鱼稳定", same.target_fish().get("id") == fish_spring.get("id"))

	var state := "waiting"
	var guard := 0
	while state == "waiting" and guard < 100:
		state = spring.tick(0.1)
		guard += 1
	check("等待后出现咬钩", state == "bite", "→ %s" % state)
	var caught := spring.reel()
	check("窗口内收线成功", bool(caught.get("ok", false)), String(caught.get("message", "")))
	check("钓到鱼后结束", spring.is_finished())

	var missed := FishingSystem.new()
	missed.start(777, "autumn")
	guard = 0
	while not missed.is_finished() and guard < 200:
		missed.tick(0.1)
		guard += 1
	check("错过窗口会跑鱼", missed.is_finished() and String(missed.result().get("reason", "")) == "missed",
		"→ %s" % missed.result())
	var miss_result := missed.reel()
	check("跑鱼后收线失败", not bool(miss_result.get("ok", true)))

	var winter := FishingSystem.new()
	winter.start(999, "winter")
	check("冬季有冰钓鱼", not winter.target_fish().is_empty())
	check("冬季不会混入夏季鱼", String(winter.target_fish().get("id", "")) != "fish_mandarin")

func _test_cooking() -> void:
	print("\n[3] 菜谱与扣料")
	check("菜谱达到设计数量 12 个", CookingSystem.all_recipes().size() >= 12,
		"→ %d 个" % CookingSystem.all_recipes().size())
	var state := GameState.new()
	state.player.inventory["forage_mushroom"] = 2
	state.player.inventory["food_sour_cabbage"] = 1
	check("材料齐时可以下锅", CookingSystem.can_cook(state, "mushroom_stew"))
	var result := CookingSystem.cook(state, "mushroom_stew")
	check("烹饪成功", bool(result.get("ok", false)), String(result.get("message", "")))
	check("产出进背包", int(state.player.inventory.get("food_mushroom_stew", 0)) == 1)
	check("蘑菇被扣除", int(state.player.inventory.get("forage_mushroom", 0)) == 0)
	check("腌菜被扣除", int(state.player.inventory.get("food_sour_cabbage", 0)) == 0)
	check("无材料时不能做", not CookingSystem.can_cook(state, "mushroom_stew"))
	check("强行烹饪失败", not bool(CookingSystem.cook(state, "mushroom_stew").get("ok", true)))

func _test_festivals() -> void:
	print("\n[4] 四大节日")
	check("节日数量不少于 2 个", FestivalSystem.all_festivals().size() >= 2,
		"→ %d 个" % FestivalSystem.all_festivals().size())
	var cal := GameCalendar.new()
	cal.advance_to_month(4, 18)
	check("春耕节在今天", String(FestivalSystem.is_today(cal).get("id", "")) == "spring_plow")
	cal.advance_to_month(7, 15)
	check("河灯节在今天", String(FestivalSystem.is_today(cal).get("id", "")) == "summer_river")
	cal.advance_to_month(9, 25)
	check("秋收节在今天", String(FestivalSystem.is_today(cal).get("id", "")) == "autumn_harvest")
	cal.advance_to_month(2, 15)
	check("上元灯节在今天", String(FestivalSystem.is_today(cal).get("id", "")) == "winter_lantern")
	var acts := FestivalSystem.available_activities("autumn_harvest")
	check("秋收节有活动", acts.size() >= 3, "→ %d 项" % acts.size())
	check("秋收节能看古戏", _has_activity(acts, "古戏"))

func _has_activity(acts: Array, keyword: String) -> bool:
	for act in acts:
		if String(act.get("name", "")).contains(keyword):
			return true
	return false

func _test_quests() -> void:
	print("\n[5] 公告板任务")
	check("任务达到设计数量 18 条", QuestSystem.all_quests().size() >= 18,
		"→ %d 条" % QuestSystem.all_quests().size())
	var state := GameState.new()
	var quest := QuestSystem.get_quest("q_zhang_grain")
	check("集市任务存在", not quest.is_empty())
	var accepted := QuestSystem.accept(state, "q_zhang_grain")
	check("能接取公告板任务", bool(accepted.get("ok", false)),
		String(accepted.get("message", "")))
	check("任务进入进行中", QuestSystem.is_active(state, "q_zhang_grain"))
	check("同一条任务不能重复接", not bool(QuestSystem.accept(state,
		"q_zhang_grain").get("ok", true)))
	state.player.inventory["food_dried_corn"] = 3
	check("库存满足后可交付", QuestSystem.can_turn_in(state, "q_zhang_grain"))
	var gold_before := state.player.gold
	var turned := QuestSystem.turn_in(state, "q_zhang_grain")
	check("交付成功", bool(turned.get("ok", false)), String(turned.get("message", "")))
	check("交付扣掉库存", int(state.player.inventory.get("food_dried_corn", 0)) == 0)
	check("交付发金币", state.player.gold > gold_before,
		"→ %d" % state.player.gold)
	check("交付完成登记", QuestSystem.is_completed(state, "q_zhang_grain"))
	check("交付后提升委托人好感", state.npc_affection("zhang_xiaofang") >= 4,
		"→ %d" % state.npc_affection("zhang_xiaofang"))
	check("当日不能重复刷日常委托", not bool(QuestSystem.accept(state,
		"q_zhang_grain").get("ok", true)))
	state.calendar.advance_day()
	check("次日日常委托刷新", bool(QuestSystem.accept(state,
		"q_zhang_grain").get("ok", false)))

	var cook_state := GameState.new()
	check("动作委托能接取", bool(QuestSystem.accept(cook_state, "q_sun_kitchen").get("ok", false)))
	QuestSystem.progress(cook_state, "cook", 2)
	check("做菜动作推进任务", QuestSystem.can_turn_in(cook_state, "q_sun_kitchen"))
	check("动作委托能交付", bool(QuestSystem.turn_in(cook_state,
		"q_sun_kitchen").get("ok", false)))

	var event_state := GameState.new()
	event_state.set_npc_affection("zhao_changhe", 80)
	check("剧情委托能接取", bool(QuestSystem.accept(event_state, "q_zhao_stage").get("ok", false)))
	check("剧情未完成时不能交付", not QuestSystem.can_turn_in(event_state, "q_zhao_stage"))
	event_state.events["done"].append("zhao_e3")
	check("事件完成后可交付", QuestSystem.can_turn_in(event_state, "q_zhao_stage"))

func _test_farm_expansion() -> void:
	print("\n[5b] 木工房扩建农场")
	var state := GameState.new()
	state.player.gold = 2000
	state.player.inventory["forage_wood"] = 20
	check("初始农场为 3×3", state.farm.width == 3 and state.farm.height == 3
		and state.farm.plots.size() == 9,
		"→ %d×%d / %d" % [state.farm.width, state.farm.height, state.farm.plots.size()])
	var gold_before := state.player.gold
	var wood_before := int(state.player.inventory.get("forage_wood", 0))
	var first := FarmExpansionSystem.expand(state)
	check("首次扩建成功", bool(first.get("ok", false)), String(first.get("message", "")))
	check("首次扩到 4×3 共 12 块", state.farm.width == 4 and state.farm.height == 3
		and state.farm.plots.size() == 12,
		"→ %d×%d / %d" % [state.farm.width, state.farm.height, state.farm.plots.size()])
	check("扩建扣金币", state.player.gold < gold_before,
		"→ %d -> %d" % [gold_before, state.player.gold])
	check("扩建扣木料", int(state.player.inventory.get("forage_wood", 0)) < wood_before,
		"→ %d -> %d" % [wood_before, int(state.player.inventory.get("forage_wood", 0))])
	while not FarmExpansionSystem.next_step(state.farm).is_empty():
		FarmExpansionSystem.expand(state)
	check("扩建上限为地图 6×4 共 24 块", state.farm.width == 6
		and state.farm.height == 4 and state.farm.plots.size() == 24,
		"→ %d×%d / %d" % [state.farm.width, state.farm.height, state.farm.plots.size()])
	var capped := FarmExpansionSystem.expand(state)
	check("满级后不会继续扩", not bool(capped.get("ok", true)), String(capped.get("message", "")))

	state.farm.get_plot(0).till()
	var loaded := GameState.from_dict(state.to_dict())
	check("扩建尺寸入档", loaded.farm.width == 6 and loaded.farm.height == 4
		and loaded.farm.plots.size() == 24,
		"→ %d×%d / %d" % [loaded.farm.width, loaded.farm.height, loaded.farm.plots.size()])
	check("旧地块状态保留", loaded.farm.get_plot(0).state == FarmPlot.State.TILLED)

	var poor := GameState.new()
	poor.player.gold = 0
	poor.player.inventory.clear()
	var denied := FarmExpansionSystem.expand(poor)
	check("钱料不够时拒绝扩建", not bool(denied.get("ok", true)), String(denied.get("message", "")))

func _test_panels_and_wiring() -> void:
	print("\n[6] 面板与互动点接线")
	var mgr := _mgr()
	mgr.new_session()
	await process_frame
	mgr.state.calendar.advance_to_month(6, 20)
	mgr.state.player.inventory["forage_mushroom"] = 2
	mgr.state.player.inventory["food_sour_cabbage"] = 1

	var packed: PackedScene = load("res://scenes/game.tscn")
	_game = packed.instantiate()
	root.add_child(_game)
	await create_timer(0.3).timeout
	var world: Node2D = _game.get_node("World")
	var fishing = _panel("FishingPanel")
	check("游戏外壳里有钓鱼面板", fishing != null)
	fishing.open_round(4242, mgr.state.calendar.get_season())
	check("钓鱼面板能开", fishing.is_open())
	check("钓鱼面板有状态文字", fishing.status_text() != "")
	fishing.close_panel()
	await process_frame

	var cooking = _panel("CookingPanel")
	check("游戏外壳里有烹饪面板", cooking != null)
	cooking.open_panel()
	check("烹饪面板能开", cooking.is_open())
	check("烹饪面板列出菜谱", cooking.recipe_buttons().size() >= 2,
		"→ %d 个" % cooking.recipe_buttons().size())
	var cooked := false
	for button in cooking.recipe_buttons():
		if String(button.text).contains("蘑菇"):
			button.pressed.emit()
			cooked = true
			break
	check("点菜谱能真正做菜", cooked)
	check("面板做菜后产出进背包",
		int(mgr.state.player.inventory.get("food_mushroom_stew", 0)) == 1)
	cooking.close_panel()
	await process_frame

	mgr.request_travel("L02")
	await create_timer(0.3).timeout
	var home: Node = world.get_child(0)
	check("已进入农舍", home.location_id == "L02", "→ %s" % home.location_id)
	var player: Node2D = home.get_node("Player")
	player.global_position = Vector2(990, 260)
	home._interact()
	await create_timer(0.2).timeout
	check("农舍灶台打开烹饪面板", _panel("CookingPanel").is_open())
	_panel("CookingPanel").close_panel()
	await create_timer(0.1).timeout

	mgr.request_travel("L09")
	await create_timer(0.3).timeout
	var river: Node = world.get_child(0)
	check("已进入河岸", river.location_id == "L09")
	player = river.get_node("Player")
	player.global_position = Vector2(1120, 690)
	river._interact()
	await create_timer(0.2).timeout
	check("河岸码头打开钓鱼面板", _panel("FishingPanel").is_open())
	check("钓鱼时锁住移动", mgr.input_locked)
	_panel("FishingPanel").close_panel()
	await create_timer(0.1).timeout
	check("收竿后解锁移动", not mgr.input_locked)

	mgr.request_travel("L10")
	await create_timer(0.3).timeout
	var forest: Node = world.get_child(0)
	check("已进入桦树林", forest.location_id == "L10")
	player = forest.get_node("Player")
	player.global_position = Vector2(1910, 900)
	var before_mushroom := int(mgr.state.player.inventory.get("forage_mushroom", 0))
	forest._interact()
	await create_timer(0.1).timeout
	check("树林采集点真的进背包",
		int(mgr.state.player.inventory.get("forage_mushroom", 0)) > before_mushroom,
		"→ %d" % int(mgr.state.player.inventory.get("forage_mushroom", 0)))
	check("采集后提示物品名", forest.message_label.text.contains("野蘑菇"),
		"→ %s" % forest.message_label.text)

	mgr.request_travel("L03")
	await create_timer(0.3).timeout
	var town: Node = world.get_child(0)
	player = town.get_node("Player")
	player.global_position = Vector2(1770, 880)
	town._interact()
	await create_timer(0.2).timeout
	var quest_panel = _panel("QuestPanel")
	check("公告板打开任务面板", quest_panel != null and quest_panel.is_open())
	check("公告板列任务", quest_panel.quest_buttons().size() >= 1,
		"→ %d 个" % quest_panel.quest_buttons().size())
	var accepted_from_panel := false
	for button in quest_panel.quest_buttons():
		if String(button.text).contains("接取"):
			button.pressed.emit()
			accepted_from_panel = true
			break
	check("能从面板接任务", accepted_from_panel)
	check("面板接取后任务进行中", QuestSystem.active_entries(mgr.state).size() >= 1)
	quest_panel.close_panel()
	await create_timer(0.1).timeout

	mgr.state.calendar.advance_to_month(9, 25)
	mgr.request_travel("L11")
	await create_timer(0.3).timeout
	var theater: Node = world.get_child(0)
	check("已进入月桂剧场", theater.location_id == "L11")
	theater._handle_interactable({"action": "theater", "label": "看戏"})
	await create_timer(0.1).timeout
	check("秋收戏剧节剧场显示节日活动",
		theater.message_label.text.contains("秋收戏剧节")
		and theater.message_label.text.contains("古戏"),
		"→ %s" % theater.message_label.text)
	_game.queue_free()
	await create_timer(0.1).timeout

func _test_location_actions() -> void:
	print("\n[7] 场景互动动作全部可用")
	var mgr := _mgr()
	mgr.new_session()
	var seen := {}
	var shop_cb := func(): seen["shop"] = true
	var inventory_cb := func(): seen["inventory"] = true
	mgr.shop_requested.connect(shop_cb)
	mgr.inventory_requested.connect(inventory_cb)

	var shop_scene: Node = load("res://scenes/locations/L04.tscn").instantiate()
	root.add_child(shop_scene)
	await process_frame
	shop_scene._handle_interactable({"action": "shop", "label": "柜台"})
	check("杂货店柜台打开商店", bool(seen.get("shop", false)))
	shop_scene.queue_free()
	await process_frame

	seen.clear()
	var storage_scene: Node = load("res://scenes/locations/L02.tscn").instantiate()
	root.add_child(storage_scene)
	await process_frame
	storage_scene._handle_interactable({"action": "storage", "label": "储物柜"})
	check("农舍储物柜打开背包", bool(seen.get("inventory", false)))
	storage_scene.queue_free()
	await process_frame

	seen.clear()
	var market_scene: Node = load("res://scenes/locations/L03.tscn").instantiate()
	root.add_child(market_scene)
	await process_frame
	market_scene._handle_interactable({"action": "market", "label": "集市"})
	check("镇中心集市打开买卖面板", bool(seen.get("shop", false)))
	market_scene.queue_free()
	await process_frame

	mgr.state.player.gold = 1000
	mgr.state.player.inventory["forage_wood"] = 12
	var workshop: Node = load("res://scenes/locations/L08.tscn").instantiate()
	root.add_child(workshop)
	await process_frame
	var before_size: int = mgr.state.farm.plots.size()
	workshop._handle_interactable({"action": "workshop", "label": "扩建农场"})
	check("木工房扩建真实增加地块", mgr.state.farm.plots.size() > before_size,
		"→ %d -> %d" % [before_size, mgr.state.farm.plots.size()])
	check("木工房给出扩建结果", not workshop.message_label.text.contains("还没开放"),
		"→ %s" % workshop.message_label.text)
	workshop.queue_free()
	await process_frame

	mgr.state.calendar.advance_to_month(4, 20)
	var theater: Node = load("res://scenes/locations/L11.tscn").instantiate()
	root.add_child(theater)
	await process_frame
	theater._handle_interactable({"action": "theater", "label": "看戏"})
	check("剧场有独立演出内容", theater.message_label.text.contains("周德顺")
		or theater.message_label.text.contains("月桂谣"),
		"→ %s" % theater.message_label.text)
	theater.queue_free()
	await process_frame

	mgr.shop_requested.disconnect(shop_cb)
	mgr.inventory_requested.disconnect(inventory_cb)
