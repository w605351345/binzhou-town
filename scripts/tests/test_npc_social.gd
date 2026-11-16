extends SceneTree
## NPC 注册表与日程自测。
## 运行: godot --headless --script res://scripts/tests/test_npc_social.gd

var _passed := 0
var _failed := 0
var _game: Node = null

const EXPECTED_IDS := [
	"zhang_xiaofang", "han_shouyi", "sun_yumei",
	"zhao_changhe", "lin_xiaoman", "zhou_deshun",
	"shi_tieshan", "jiang_muyun", "he_shuigen",
	"su_wenbo", "lang_sanshun",
]

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== 《麦溪镇》NPC 社交自测 (npc social test) ===")
	_test_registry()
	_test_cross_location_schedule()
	_test_season_weather_night_variants()
	_test_lunch_positions_do_not_overlap()
	await _test_location_refresh()
	_test_relationship_actions()
	_test_gifts_and_birthday()
	_test_event_gating()
	_test_all_events_reachable()
	_test_event_chains_complete_and_persist()
	_test_extended_dialogue_conditions()
	_test_event_choice_writes_flag()
	await _test_gift_panel_in_game()
	await _test_event_opens_in_game()
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

func _clock(minutes: int) -> GameClock:
	return GameClock.new(minutes)

func _calendar(day_of_year: int) -> GameCalendar:
	var cal := GameCalendar.new()
	cal.day_of_year = day_of_year
	return cal

func _resolve(npc_id: String, day: int, minutes: int, weather_id: String = "sunny") -> Dictionary:
	var data := NpcRegistry.get_npc(npc_id)
	return NpcScheduleSystem.resolve(data, _calendar(day), _clock(minutes), weather_id)

func _test_registry() -> void:
	print("\n[1] 十一名 NPC 注册完整")
	var all := NpcRegistry.all_npcs()
	check("注册表有 11 人", all.size() == 11, "→ %d 人" % all.size())
	for npc_id in EXPECTED_IDS:
		var data := NpcRegistry.get_npc(npc_id)
		check("%s 存在" % npc_id, not data.is_empty())
		check("%s 有姓名与身份" % npc_id,
			String(data.get("name", "")) != "" and String(data.get("title", "")) != "")
		check("%s 有生日" % npc_id,
			int(data.get("birthday_month", 0)) in range(1, 13)
			and int(data.get("birthday_day", 0)) in range(1, 31))
		check("%s 有喜恶礼物" % npc_id,
			not Array(data.get("likes", [])).is_empty()
			and not Array(data.get("dislikes", [])).is_empty())
		check("%s 有日程与立绘" % npc_id,
			not Array(data.get("schedules", [])).is_empty()
			and String(data.get("portrait_path", "")).begins_with("res://"))
		check("%s 有精灵图路径" % npc_id,
			String(data.get("sprite_path", "")).begins_with("res://"))

func _test_cross_location_schedule() -> void:
	print("\n[2] 日程跨地点")
	var zhang_morning := _resolve("zhang_xiaofang", 120, 9 * 60)
	check("张晓芳上午在镇中心", zhang_morning.get("location_id") == "L03",
		"→ %s" % zhang_morning.get("location_id"))
	check("张晓芳上午可交谈", bool(zhang_morning.get("available", false)))
	var zhang_lunch := _resolve("zhang_xiaofang", 120, 12 * 60 + 20)
	check("张晓芳午饭留在集市看摊", zhang_lunch.get("location_id") == "L03",
		"→ %s" % zhang_lunch.get("location_id"))
	check("午饭活动写明吃饭", String(zhang_lunch.get("activity", "")).contains("午饭"),
		"→ %s" % zhang_lunch.get("activity", ""))

	var han_morning := _resolve("han_shouyi", 120, 9 * 60)
	check("韩守义上午在邮局", han_morning.get("location_id") == "L05",
		"→ %s" % han_morning.get("location_id"))
	var han_night := _resolve("han_shouyi", 180, 19 * 60)
	check("韩守义晚上去剧场", han_night.get("location_id") == "L11",
		"→ %s" % han_night.get("location_id"))

	var zhao_morning := _resolve("zhao_changhe", 120, 9 * 60)
	check("赵长河上午在木工房", zhao_morning.get("location_id") == "L08",
		"→ %s" % zhao_morning.get("location_id"))
	var lin_morning := _resolve("lin_xiaoman", 180, 9 * 60)
	check("林小满上午在卫生所", lin_morning.get("location_id") == "L07",
		"→ %s" % lin_morning.get("location_id"))
	var zhou_morning := _resolve("zhou_deshun", 180, 9 * 60)
	check("周德顺上午在剧场", zhou_morning.get("location_id") == "L11",
		"→ %s" % zhou_morning.get("location_id"))

func _test_season_weather_night_variants() -> void:
	print("\n[3] 冬季、雨天、暴风雪与夜间变体")
	var zhang_spring_pm := _resolve("zhang_xiaofang", 120, 16 * 60, "sunny")
	var zhang_winter_pm := _resolve("zhang_xiaofang", 0, 16 * 60, "clear_cold")
	check("张晓芳冬季下午改去木工房", zhang_winter_pm.get("location_id") == "L08",
		"→ %s" % zhang_winter_pm.get("location_id"))
	check("张晓芳冬夏日程确实不同",
		zhang_spring_pm.get("location_id") != zhang_winter_pm.get("location_id"))

	var zhang_rain := _resolve("zhang_xiaofang", 120, 16 * 60, "rain")
	check("张晓芳雨天回仓库", String(zhang_rain.get("activity", "")).contains("仓"),
		"→ %s" % zhang_rain.get("activity", ""))

	var han_winter_night := _resolve("han_shouyi", 0, 19 * 60, "snow")
	check("韩守义冬夜不跑剧场", han_winter_night.get("location_id") != "L11",
		"→ %s" % han_winter_night.get("location_id"))
	check("韩守义冬夜回邮局", han_winter_night.get("location_id") == "L05",
		"→ %s" % han_winter_night.get("location_id"))

	var lin_blizzard := _resolve("lin_xiaoman", 30, 9 * 60, "blizzard")
	check("林小满暴风雪天出诊", bool(lin_blizzard.get("available", false)))
	check("暴风雪改变了她的活动", String(lin_blizzard.get("activity", "")).contains("出诊"),
		"→ %s" % lin_blizzard.get("activity", ""))

	var zhou_winter_evening := _resolve("zhou_deshun", 0, 19 * 60, "snow")
	check("周德顺冬夜早睡", not bool(zhou_winter_evening.get("available", true)),
		"→ available=%s" % zhou_winter_evening.get("available"))

func _test_lunch_positions_do_not_overlap() -> void:
	print("\n[4] 饭馆午饭不叠人")
	var positions: Array = []
	for npc_id in EXPECTED_IDS:
		var result := _resolve(npc_id, 120, 12 * 60 + 20)
		if result.get("location_id") == "L06" and bool(result.get("available", false)):
			positions.append(result.get("position", Vector2.ZERO))
	check("至少 5 人午饭在饭馆", positions.size() >= 5, "→ %d 人" % positions.size())
	var closest := INF
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			closest = minf(closest, Vector2(positions[i]).distance_to(Vector2(positions[j])))
	check("午饭座位互不重叠", closest >= 44.0, "→ 最近 %.1f px" % closest)

func _test_location_refresh() -> void:
	print("\n[5] 地点内按日程动态刷新")
	var mgr := _mgr()
	mgr.new_session()
	await process_frame
	mgr.state.calendar.day_of_year = 120
	mgr.state.clock.minute_of_day = 9 * 60
	mgr.state.weather.today = "sunny"

	var packed: PackedScene = load(SceneRouter.scene_path("L06"))
	if packed == null:
		check("L06 场景可加载", false)
		return
	var location: Node = packed.instantiate()
	root.add_child(location)
	await create_timer(0.15).timeout
	var container: Node = location.get_node_or_null("NpcContainer")
	check("饭馆有 NPC 容器", container != null)
	var morning_count := container.get_child_count() if container != null else 0
	check("上午饭馆里只有孙玉梅", morning_count == 1,
		"→ %d 人" % morning_count)
	if morning_count == 1:
		check("上午容器里确实是孙玉梅", String(container.get_child(0).npc.id) == "sun_yumei")

	mgr.state.clock.minute_of_day = 12 * 60 + 20
	mgr.clock_changed.emit(mgr.state.clock.minute_of_day)
	await create_timer(0.15).timeout
	var lunch_count := container.get_child_count() if container != null else 0
	check("午饭时段饭馆自动聚人", lunch_count >= 5, "→ %d 人" % lunch_count)
	if lunch_count >= 5:
		var ids := {}
		for child in container.get_children():
			ids[String(child.npc.id)] = true
		check("刷新后没有重复 NPC", ids.size() == lunch_count,
			"→ %d 个唯一 id" % ids.size())

	mgr.state.clock.minute_of_day = 21 * 60 + 45
	mgr.clock_changed.emit(mgr.state.clock.minute_of_day)
	await create_timer(0.15).timeout
	var night_ids := {}
	for child in container.get_children():
		night_ids[String(child.npc.id)] = true
	check("打烊后饭馆不再留下幽灵 NPC", not night_ids.has("zhao_changhe"),
		"→ %s" % str(night_ids.keys()))

	var zhang := NpcRegistry.get_npc("zhang_xiaofang")
	var node: NpcNode = load("res://scenes/npc_zhangxiaofang.tscn").instantiate()
	root.add_child(node)
	await process_frame
	node.setup(NpcBase.from_data(zhang))
	check("NPC 节点使用数据里的精灵路径",
		node.resolved_sprite_path() == String(zhang.get("sprite_path", "")),
		"→ %s" % node.resolved_sprite_path())
	check("NPC 节点保留数据里的立绘路径",
		node.npc.portrait_path == String(zhang.get("portrait_path", "")))
	node.queue_free()
	location.queue_free()
	await create_timer(0.1).timeout

func _test_relationship_actions() -> void:
	print("\n[6] 每日交谈与关系写档")
	var state := GameState.new()
	var first := RelationshipSystem.talk(state, "zhang_xiaofang")
	check("首次交谈加好感", int(first.get("gain", 0)) == 2,
		"→ %s" % first.get("gain"))
	check("交谈写进关系表", int(state.npc_affection("zhang_xiaofang")) == 2)
	var second := RelationshipSystem.talk(state, "zhang_xiaofang")
	check("同一天重复交谈不再刷好感", int(second.get("gain", -1)) == 0)
	state.calendar.advance_day()
	check("跨天可以再交谈",
		int(RelationshipSystem.talk(state, "zhang_xiaofang").get("gain", 0)) == 2)

func _test_gifts_and_birthday() -> void:
	print("\n[7] 礼物、喜恶与生日三倍")
	var zhang := NpcRegistry.get_npc("zhang_xiaofang")
	var state := GameState.new()
	state.player.inventory["food_sticky_bean_bun"] = 3
	var liked := RelationshipSystem.give_gift(state, zhang, "food_sticky_bean_bun")
	check("喜欢的礼物成功送出", bool(liked.get("ok", false)), String(liked.get("message", "")))
	check("喜欢礼物加 30 好感", int(liked.get("gain", 0)) == 30,
		"→ %d" % int(liked.get("gain", 0)))
	check("礼物从背包扣除", int(state.player.inventory.get("food_sticky_bean_bun", 0)) == 2)
	check("一天只能送一次", not bool(RelationshipSystem.give_gift(
		state, zhang, "food_sticky_bean_bun").get("ok", true)))

	var birthday_state := GameState.new()
	birthday_state.calendar.advance_to_month(9, 18)
	birthday_state.player.inventory["food_sticky_bean_bun"] = 1
	check("9/18 是张晓芳生日", RelationshipSystem.is_birthday(birthday_state, zhang))
	var birthday_gift := RelationshipSystem.give_gift(
		birthday_state, zhang, "food_sticky_bean_bun")
	check("生日礼物三倍好感", int(birthday_gift.get("gain", 0)) == 90,
		"→ %d" % int(birthday_gift.get("gain", 0)))

	var picky := zhang.duplicate(true)
	picky["likes"] = []
	picky["dislikes"] = ["蜂蜜燕麦面包"]
	var dislike_state := GameState.new()
	dislike_state.set_npc_affection("zhang_xiaofang", 50)
	dislike_state.player.inventory["food_sticky_bean_bun"] = 1
	var disliked := RelationshipSystem.give_gift(
		dislike_state, picky, "food_sticky_bean_bun")
	check("讨厌的礼物扣好感", int(disliked.get("gain", 0)) < 0,
		"→ %d" % int(disliked.get("gain", 0)))
	check("扣好感后不会低于 0", dislike_state.npc_affection("zhang_xiaofang") >= 0)

func _test_event_gating() -> void:
	print("\n[8] 好感门槛、时段与事件顺序")
	var state := GameState.new()
	state.calendar.advance_to_month(4, 20)
	state.clock.minute_of_day = 19 * 60 + 30
	state.weather.today = "sunny"
	state.set_npc_affection("zhang_xiaofang", 19)
	check("好感不足不触发一段事件",
		EventSystem.available_event(state, "L03", state.calendar, state.clock,
			state.weather).is_empty())
	state.set_npc_affection("zhang_xiaofang", 20)
	var event := EventSystem.available_event(state, "L03", state.calendar,
		state.clock, state.weather)
	check("好感 20 触发张晓芳一段", String(event.get("id", "")) == "zhang_e1",
		"→ %s" % event.get("id", "无"))
	state.clock.minute_of_day = 18 * 60 + 30
	check("时段外不触发", not bool(EventSystem.can_trigger(state, "zhang_e1",
		"L03", state.calendar, state.clock, state.weather)))

	var started := EventSystem.start_event(state, "zhang_e1")
	check("事件开始后进入 active", EventSystem.active_event_id(state) == "zhang_e1")
	check("同一时间只开一个事件", EventSystem.available_event(state, "L03",
		state.calendar, state.clock, state.weather).is_empty())
	EventSystem.finish_event(state, "zhang_e1")
	check("事件完成后写 done", Array(state.events.get("done", [])).has("zhang_e1"))
	check("事件完成写进关系", Array(state.relationships.get("zhang_xiaofang", {})
		.get("events_done", [])).has("zhang_e1"))
	check("完成后释放 active", EventSystem.active_event_id(state) == "")

	state.calendar.advance_to_month(9, 10)
	state.clock.minute_of_day = 18 * 60 + 30
	state.set_npc_affection("zhang_xiaofang", 50)
	check("二段事件在春/秋初霜窗前可触发", EventSystem.can_trigger(state, "zhang_e2",
		"L03", state.calendar, state.clock, state.weather))
	check("未完成一段时二段不能抢先触发",
		not bool(EventSystem.can_trigger(_fresh_state(50), "zhang_e2", "L03",
			state.calendar, state.clock, state.weather)))

func _fresh_state(affection: int) -> GameState:
	var s := GameState.new()
	s.set_npc_affection("zhang_xiaofang", affection)
	return s

func _test_all_events_reachable() -> void:
	print("\n[9] 十一人三十三段事件全部可达")
	var events := EventSystem.all_events()
	check("事件表共 33 段", events.size() == 33, "→ %d 段" % events.size())
	var counts := {}
	for event in events:
		counts[String(event.get("npc_id", ""))] = int(counts.get(
			String(event.get("npc_id", "")), 0)) + 1
	for npc_id in EXPECTED_IDS:
		check("%s 有 3 段事件" % npc_id, int(counts.get(npc_id, 0)) == 3,
			"→ %d 段" % int(counts.get(npc_id, 0)))

	var unreachable: Array = []
	for event in events:
		var event_id := String(event.get("id", ""))
		var state := GameState.new()
		state.set_npc_affection(String(event.get("npc_id", "")),
			int(event.get("affection_min", 0)))
		var seasons: Array = event.get("seasons", [])
		var month := 4
		if not seasons.is_empty():
			month = {"spring": 4, "summer": 6, "autumn": 9, "winter": 12}[
				String(seasons[0])]
		state.calendar.advance_to_month(month, 15)
		state.clock.minute_of_day = _hhmm(String(event.get("time_from", "06:00"))) + 20
		var weathers: Array = event.get("weather", [])
		state.weather.today = String(weathers[0]) if not weathers.is_empty() else "sunny"
		state.events["done"] = Array(event.get("requires_events", [])).duplicate()
		for req in event.get("requires_events", []):
			state.events["done_days"][String(req)] = state.calendar.abs_day() - 5
		if not EventSystem.can_trigger(state, event_id,
			String(event.get("location_id", "")), state.calendar, state.clock,
			state.weather):
			unreachable.append(event_id)
	check("33 段都能在指定条件下触发", unreachable.is_empty(), "→ %s" % str(unreachable))

func _test_event_chains_complete_and_persist() -> void:
	print("\n[10] 三十三段事件完整链路与存档")
	var events := EventSystem.all_events()
	for npc_id in EXPECTED_IDS:
		var chain: Array = []
		for event in events:
			if String(event.get("npc_id", "")) == npc_id:
				chain.append(event)
		chain.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("affection_min", 0)) < int(b.get("affection_min", 0)))
		check("%s 事件链为 20→50→80" % npc_id,
			chain.map(func(e: Dictionary) -> int: return int(e.get("affection_min", 0)))
			== [20, 50, 80], "→ %s" % str(chain.map(
				func(e: Dictionary) -> int: return int(e.get("affection_min", 0)))))

		var gate_state := GameState.new()
		gate_state.set_npc_affection(npc_id, 50)
		_align_state_to_event(gate_state, chain[1])
		check("%s 不能跳过第一段直接触发第二段" % npc_id,
			not EventSystem.can_trigger(gate_state, String(chain[1].get("id", "")),
				String(chain[1].get("location_id", "")), gate_state.calendar,
				gate_state.clock, gate_state.weather))

		gate_state.set_npc_affection(npc_id, 80)
		gate_state.events["done"] = [String(chain[0].get("id", ""))]
		gate_state.events["done_days"] = {String(chain[0].get("id", "")): 0}
		_align_state_to_event(gate_state, chain[2])
		check("%s 不能跳过第二段直接触发第三段" % npc_id,
			not EventSystem.can_trigger(gate_state, String(chain[2].get("id", "")),
				String(chain[2].get("location_id", "")), gate_state.calendar,
				gate_state.clock, gate_state.weather))

		var state := GameState.new()
		for event in chain:
			var event_id := String(event.get("id", ""))
			state.set_npc_affection(npc_id, int(event.get("affection_min", 0)))
			_align_state_to_event(state, event)
			if int(event.get("days_since_event_min", 0)) > 0:
				for req in event.get("requires_events", []):
					state.events["done_days"][String(req)] = state.calendar.abs_day() - 5
			check("%s 条件满足后可触发" % event_id,
				EventSystem.can_trigger(state, event_id,
					String(event.get("location_id", "")), state.calendar,
					state.clock, state.weather))
			var started := EventSystem.start_event(state, event_id)
			check("%s 能进入 active" % event_id, not started.is_empty())
			var finished := _walk_event_first_choices(state, started)
			check("%s 首条选择分支能走完" % event_id, finished)
			EventSystem.finish_event(state, event_id)
			check("%s 完成后释放 active" % event_id,
				EventSystem.active_event_id(state) == "")

		var done: Array = state.events.get("done", [])
		check("%s 三段事件全部完成" % npc_id, done.size() == 3, "→ %d" % done.size())
		check("%s 三段完成日均已记录" % npc_id,
			Dictionary(state.events.get("done_days", {})).size() == 3)
		check("%s 事件选择至少写下一个 flag" % npc_id, not state.flags.is_empty(),
			"→ %s" % str(state.flags.keys()))

		var loaded := GameState.from_dict(state.to_dict())
		check("%s 存档恢复全部事件" % npc_id,
			Array(loaded.events.get("done", [])).size() == 3)
		check("%s 存档恢复完成日" % npc_id,
			Dictionary(loaded.events.get("done_days", {})).size() == 3)
		check("%s 存档恢复事件 flag" % npc_id,
			loaded.flags == state.flags, "→ %s" % str(loaded.flags.keys()))

func _align_state_to_event(state: GameState, event: Dictionary) -> void:
	var seasons: Array = event.get("seasons", [])
	var month := 4
	if not seasons.is_empty():
		month = {"spring": 4, "summer": 6, "autumn": 9, "winter": 12}[
			String(seasons[0])]
	state.calendar.advance_to_month(month, 15)
	state.clock.minute_of_day = _hhmm(String(event.get("time_from", "06:00"))) + 20
	var weathers: Array = event.get("weather", [])
	state.weather.today = String(weathers[0]) if not weathers.is_empty() else "sunny"

func _walk_event_first_choices(state: GameState, event: Dictionary) -> bool:
	var runner := DialogueRunner.new()
	runner.setup(Array(event.get("lines", [])), state.player, state.calendar,
		NpcBase.from_data(NpcRegistry.get_npc(String(event.get("npc_id", "")))),
		state.flags, state.events, state.clock, state.weather)
	runner.start()
	var guard := 0
	while not runner.is_finished() and guard < 40:
		guard += 1
		var options := runner.current_options()
		if options.is_empty():
			runner.advance()
		else:
			runner.choose(0)
	return runner.is_finished()

func _hhmm(value: String) -> int:
	var parts := value.split(":")
	return int(parts[0]) * 60 + int(parts[1])

func _test_extended_dialogue_conditions() -> void:
	print("\n[10] 对话条件扩展")
	var state := GameState.new()
	state.calendar.advance_to_month(4, 20)
	state.clock.minute_of_day = 19 * 60 + 15
	state.weather.today = "rain"
	state.events["done"] = ["zhang_e1"]
	var ctx := {
		"calendar": state.calendar, "player": state.player,
		"npc": NpcBase.from_data(NpcRegistry.get_npc("zhang_xiaofang")),
		"flags": state.flags, "events": state.events, "clock": state.clock,
		"weather": state.weather,
	}
	check("time_from/time_to 条件生效", DialogueConditions.evaluate(
		{"time_from": "19:00", "time_to": "21:00"}, ctx))
	check("时段外条件不满足", not DialogueConditions.evaluate(
		{"time_from": "20:00", "time_to": "21:00"}, ctx))
	check("weather 类条件支持降雨组", DialogueConditions.evaluate(
		{"weather": ["rain"]}, ctx))
	check("event_done 条件生效", DialogueConditions.evaluate(
		{"event_done": "zhang_e1"}, ctx))
	check("not_event_done 条件生效", DialogueConditions.evaluate(
		{"not_event_done": "zhang_e2"}, ctx))
	check("weekday 条件生效", DialogueConditions.evaluate(
		{"weekday": [state.calendar.abs_day() % 7]}, ctx))

func _test_event_opens_in_game() -> void:
	print("\n[11] 进入地点自动开启好感事件")
	var mgr := _mgr()
	mgr.new_session()
	await process_frame
	mgr.state.calendar.advance_to_month(4, 20)
	mgr.state.clock.minute_of_day = 19 * 60 + 30
	mgr.state.weather.today = "sunny"
	mgr.state.set_npc_affection("zhang_xiaofang", 20)
	var packed: PackedScene = load("res://scenes/game.tscn")
	_game = packed.instantiate()
	root.add_child(_game)
	await create_timer(0.3).timeout
	var world: Node2D = _game.get_node("World")
	world.get_child(0)._go_to_town()
	await create_timer(0.5).timeout
	var box = _panel("DialogueBox")
	check("事件对话框自动打开", box != null and box.is_open())
	if box != null and box.is_open():
		check("事件说话人是张晓芳", box.speaker_name() == "张晓芳",
			"→ %s" % box.speaker_name())
		check("事件台词不是普通寒暄", box.body_text().contains("秤"),
			"→ %s" % box.body_text().substr(0, 30))
	_game.queue_free()
	await create_timer(0.1).timeout

func _test_event_choice_writes_flag() -> void:
	print("\n[12] 事件选择写 flag")
	var state := GameState.new()
	var event := EventSystem.start_event(state, "zhang_e1")
	var runner := DialogueRunner.new()
	runner.setup(Array(event.get("lines", [])), state.player,
		state.calendar, NpcBase.from_data(NpcRegistry.get_npc("zhang_xiaofang")),
		state.flags, state.events, state.clock, state.weather)
	runner.start()
	var result := runner.choose(1)
	check("选择推进到帮忙分支", String(result.get("type", "")) == "line",
		"→ %s" % result.get("type"))
	var result2 := runner.choose(1)
	check("分支选项结束事件", String(result2.get("type", "")) == "end")
	check("事件选择写进存档 flag", bool(state.flags.get("zhang_e1_helped", false)),
		"→ %s" % state.flags.get("zhang_e1_helped"))
	EventSystem.finish_event(state, "zhang_e1")

func _test_gift_panel_in_game() -> void:
	print("\n[13] 对话里打开送礼面板")
	var mgr := _mgr()
	mgr.new_session()
	await process_frame
	mgr.state.player.inventory["food_sticky_bean_bun"] = 2
	var packed: PackedScene = load("res://scenes/game.tscn")
	_game = packed.instantiate()
	root.add_child(_game)
	await create_timer(0.3).timeout
	var world: Node2D = _game.get_node("World")
	world.get_child(0)._go_to_town()
	await create_timer(0.3).timeout
	var town: Node = world.get_child(0)
	var npc_node: Node2D = town.get_node("NpcContainer").get_child(0)
	var player: Node2D = town.get_node("Player")
	player.global_position = npc_node.global_position + Vector2(0, -40)
	town._interact()
	await create_timer(0.1).timeout
	var box = _panel("DialogueBox")
	var opened := false
	for button in box.option_buttons():
		if String(button.text).replace("· ", "") == "送点东西":
			button.pressed.emit()
			opened = true
			break
	check("对话里有送礼选项", opened)
	await create_timer(0.1).timeout
	var gift = _panel("GiftPanel")
	check("送礼面板已打开", gift != null and gift.is_open())
	if gift != null and gift.is_open():
		var gifted := false
		for button in gift.gift_buttons():
			if String(button.text).begins_with("蜂蜜燕麦面包"):
				button.pressed.emit()
				gifted = true
				break
		check("蜂蜜燕麦面包出现在礼物列表", gifted)
		await create_timer(0.1).timeout
		check("面板送出后好感上升", mgr.state.npc_affection("zhang_xiaofang") >= 30,
			"→ %d" % mgr.state.npc_affection("zhang_xiaofang"))
		check("面板送出后背包减少",
			int(mgr.state.player.inventory.get("food_sticky_bean_bun", 0)) == 1)
		gift.close_panel()
		await create_timer(0.1).timeout
		check("收起礼物后回到对话", box.is_open())
	_game.queue_free()
	await create_timer(0.1).timeout
