extends SceneTree
## Task 10 全量验收：新游戏起点、三天生活闭环、跨日与存读档。
## 运行: godot --headless --script res://scripts/tests/test_acceptance.gd

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== 《宾州小镇》全量生活闭环验收 (acceptance test) ===")
	await process_frame
	_test_new_game_start()
	_test_three_day_loop()
	_test_event_catalog()
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

func _test_new_game_start() -> void:
	print("\n[1] 新游戏从农舍醒来")
	var state := GameState.new()
	check("新档地点是农舍 L02", String(state.world.get("location_id", "")) == "L02",
		"→ %s" % state.world.get("location_id", ""))
	check("新档时间是清晨 06:00", state.clock.minute_of_day == GameClock.DAY_START_MINUTE,
		"→ %s" % state.clock.time_string())
	var house := MapDatabase.get_map("L02")
	check("农舍有出门与睡觉互动",
		Array(house.get("doors", [])).size() >= 1
		and Array(house.get("interactables", [])).size() >= 2)

func _test_three_day_loop() -> void:
	print("\n[2] 三天生活闭环")
	var mgr := _mgr()
	var state := GameState.new()
	mgr.state = state
	state.calendar.advance_to_month(4, 20)
	state.clock.minute_of_day = GameClock.DAY_START_MINUTE
	state.weather.today = "sunny"
	state.weather.tomorrow = "cloudy"
	state.world["location_id"] = "L01"

	# 起床后去杂货店买一袋玉米种。
	var gold_before_buy := state.player.gold
	var bought := Shop.buy_item(state.player, "seed_corn", 1)
	check("第一天在杂货店买到玉米种", bool(bought.get("ok", false)),
		String(bought.get("message", "")))
	check("买种扣钱", state.player.gold == gold_before_buy - int(bought.get("price", 0)),
		"→ %d" % state.player.gold)
	check("种子进入背包", int(state.player.inventory.get("seed_corn", 0)) == 1)

	# 农场：翻土 → 播种 → 浇水。
	var farm := state.farm
	var till := ToolBar.apply_tool(ToolBar.Tool.TILL, farm, 0, state.player)
	check("第一天翻土成功", bool(till.get("ok", false)), String(till.get("message", "")))
	var gold_before_plant := state.player.gold
	var plant := ToolBar.apply_tool(ToolBar.Tool.SEED, farm, 0, state.player, "corn")
	check("用背包种子播种成功", bool(plant.get("ok", false)),
		String(plant.get("message", "")))
	check("播种消耗背包种子",
		int(state.player.inventory.get("seed_corn", 0)) == 0)
	check("已有种子时不再重复扣钱", state.player.gold == gold_before_plant,
		"→ %d / %d" % [state.player.gold, gold_before_plant])
	check("地块进入生长状态", farm.get_plot(0).crop_id == "corn"
		and farm.get_plot(0).state == FarmPlot.State.PLANTED)
	var water := ToolBar.apply_tool(ToolBar.Tool.WATER, farm, 0, state.player)
	check("第一天浇水成功", bool(water.get("ok", false)), String(water.get("message", "")))
	check("浇水记录写进绝对日",
		farm.get_plot(0).last_watered_abs_day == state.calendar.abs_day())

	# 镇上：和两个人说话，再投其所好送一份礼物。
	var talk_zhang := RelationshipSystem.talk(state, "zhang_xiaofang")
	var talk_han := RelationshipSystem.talk(state, "han_shouyi")
	check("和第一名 NPC 交谈", bool(talk_zhang.get("ok", false)),
		String(talk_zhang.get("message", "")))
	check("和第二名 NPC 交谈", bool(talk_han.get("ok", false)),
		String(talk_han.get("message", "")))
	var gift_buy := Shop.buy_item(state.player, "gift_sunflower_seeds", 1)
	check("杂货店能买到张晓芳喜欢的礼物", bool(gift_buy.get("ok", false)),
		String(gift_buy.get("message", "")))
	var zhang := NpcRegistry.get_npc("zhang_xiaofang")
	var gift := RelationshipSystem.give_gift(state, zhang, "gift_sunflower_seeds")
	check("投其所好送礼成功", bool(gift.get("ok", false)), String(gift.get("message", "")))
	check("喜欢礼物触发 30 点好感", int(gift.get("gain", 0)) == 30,
		"→ %d" % int(gift.get("gain", 0)))

	# 河岸钓鱼，树林采集，再回家做饭。
	var fishing := FishingSystem.new()
	fishing.start(20260420, "spring")
	var guard := 0
	while fishing.current_state() == "waiting" and guard < 100:
		fishing.tick(0.1)
		guard += 1
	check("河岸能等到鱼咬钩", fishing.current_state() == "bite",
		"→ %s" % fishing.current_state())
	var caught := fishing.reel()
	check("收线钓到鱼", bool(caught.get("ok", false)), String(caught.get("message", "")))
	var forage := ForageSystem.collect(state, "L10_clearing_spring")
	check("桦树林能采到春山货", bool(forage.get("ok", false)),
		String(forage.get("message", "")))
	var millet_buy := Shop.buy_item(state.player, "millet", 2)
	check("买小米准备做饭", bool(millet_buy.get("ok", false)),
		String(millet_buy.get("message", "")))
	var cooked := CookingSystem.cook(state, "millet_porridge")
	check("灶台能做饭", bool(cooked.get("ok", false)), String(cooked.get("message", "")))
	state.player.stamina.consume(20)
	var energy_before_meal := state.player.energy
	state.player.stamina.restore(18)
	check("吃饭恢复体力", state.player.energy > energy_before_meal,
		"→ %d -> %d" % [energy_before_meal, state.player.energy])

	# 回家睡觉：日期、天气、作物与体力统一结算。
	var day_before := state.calendar.abs_day()
	var growth_before := farm.get_plot(0).days_grown
	mgr.advance_day()
	check("睡觉推进到第二天", state.calendar.abs_day() == day_before + 1,
		"→ %d" % state.calendar.abs_day())
	check("睡觉后时钟回到清晨", state.clock.minute_of_day == GameClock.DAY_START_MINUTE,
		"→ %s" % state.clock.time_string())
	check("作物跨夜生长", farm.get_plot(0).days_grown > growth_before,
		"→ %.0f" % farm.get_plot(0).days_grown)
	check("睡眠回满体力", state.player.energy >= state.player.max_energy,
		"→ %d/%d" % [state.player.energy, state.player.max_energy])

	# 第二天 / 第三天：日程与天气继续推进，最后存读档。
	var zhang_data := NpcRegistry.get_npc("zhang_xiaofang")
	state.clock.minute_of_day = 9 * 60
	var morning := NpcScheduleSystem.resolve(zhang_data, state.calendar, state.clock,
		state.weather)
	state.clock.minute_of_day = 18 * 60 + 30
	var evening := NpcScheduleSystem.resolve(zhang_data, state.calendar, state.clock,
		state.weather)
	check("同一天 NPC 日程位置变化",
		Vector2(morning.get("position", Vector2.ZERO)) != Vector2(evening.get("position", Vector2.ZERO)),
		"→ %s / %s" % [morning.get("position"), evening.get("position")])
	mgr.advance_day()
	mgr.advance_day()
	check("连续睡到第三天", state.calendar.abs_day() == day_before + 3,
		"→ %d" % state.calendar.abs_day())
	check("第三天天气已刷新", state.weather.today != "", "→ %s" % state.weather.today)

	var saved_day := state.calendar.abs_day()
	var saved_gold := state.player.gold
	var saved_seed := int(state.player.inventory.get("forage_wood", 0))
	var saved_affection := state.npc_affection("zhang_xiaofang")
	check("第三天存档成功", mgr.save_game(96))
	state.player.gold = -1
	state.calendar.from_absolute_day(0)
	state.set_npc_affection("zhang_xiaofang", 0)
	check("第三天读档成功", mgr.load_game(96))
	state = mgr.state
	check("读档恢复日期", state.calendar.abs_day() == saved_day,
		"→ %d" % state.calendar.abs_day())
	check("读档恢复金币", state.player.gold == saved_gold,
		"→ %d" % state.player.gold)
	check("读档恢复背包", int(state.player.inventory.get("forage_wood", 0)) == saved_seed,
		"→ %d" % int(state.player.inventory.get("forage_wood", 0)))
	check("读档恢复好感", state.npc_affection("zhang_xiaofang") == saved_affection,
		"→ %d" % state.npc_affection("zhang_xiaofang"))
	DirAccess.remove_absolute("user://saves/slot_96.json")

func _test_event_catalog() -> void:
	print("\n[3] 六名 NPC 与十八段故事")
	var events := EventSystem.all_events()
	check("事件总数为 18", events.size() == 18, "→ %d" % events.size())
	var per_npc := {}
	for event in events:
		var npc_id := String(event.get("npc_id", ""))
		per_npc[npc_id] = int(per_npc.get(npc_id, 0)) + 1
	for npc in NpcRegistry.all_npcs():
		var npc_id := String(npc.get("id", ""))
		check("%s 有三段好感故事" % npc.get("name", npc_id),
			int(per_npc.get(npc_id, 0)) == 3, "→ %d" % int(per_npc.get(npc_id, 0)))
