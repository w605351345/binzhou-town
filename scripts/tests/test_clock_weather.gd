extends SceneTree
## M0 时间/日期/输入地基自测。运行:
## godot --headless --script res://scripts/tests/test_clock_weather.gd

var _passed := 0
var _failed := 0

func _initialize() -> void:
	await process_frame
	print("=== M0 时间/日期/输入地基自测 ===")
	test_absolute_day()
	test_game_clock()
	test_modal_stack()
	test_cross_year_water()
	test_harvest_resets_water()
	test_weather_determinism()
	test_weather_weights()
	test_weather_effects()
	test_weather_stamina_usage()
	test_female_sprite_wiring()
	print("--------------------------------------------------")
	print("结果: %d 通过 / %d 失败" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  ✅ %s %s" % [label, detail])
	else:
		_failed += 1
		print("  ❌ %s %s" % [label, detail])

func test_absolute_day() -> void:
	print("\n[1] 绝对日跨年单调递增")
	var cal := GameCalendar.new()
	cal.from_absolute_day(GameCalendar.DAYS_PER_YEAR - 1)
	check("跨年前最后一天", cal.year == 1 and cal.day_of_year == 359, cal.date_string())
	var before := cal.abs_day()
	cal.advance_day()
	check("绝对日 +1", cal.abs_day() == before + 1, "→ %d" % cal.abs_day())
	check("进入第二年", cal.year == 2 and cal.day_of_year == 0, cal.date_string())
	cal.from_absolute_day(before)
	check("可从绝对日还原", cal.year == 1 and cal.day_of_year == 359, cal.date_string())

func test_game_clock() -> void:
	print("\n[2] 游戏时钟")
	var clock := GameClock.new()
	check("06:00 起床", clock.time_string() == "06:00", clock.time_string())
	check("清晨时段", clock.phase() == "dawn", clock.phase())
	clock.advance_minutes(360)
	check("推进 6 小时到 12:00", clock.time_string() == "12:00", clock.time_string())
	check("正午时段", clock.phase() == "noon", clock.phase())
	clock.minute_of_day = GameClock.DAY_END_MINUTE
	check("02:00 强制睡觉", clock.should_force_sleep(), clock.time_string())
	var restored := GameClock.from_dict(clock.to_dict())
	check("时钟可序列化", restored.minute_of_day == clock.minute_of_day)

func test_modal_stack() -> void:
	print("\n[3] 模态栈")
	var stack := ModalStack.new()
	check("空栈不锁", stack.depth() == 0)
	stack.push("dialogue")
	stack.push("shop")
	check("嵌套两层", stack.depth() == 2)
	check("锁住世界", stack.is_locked())
	stack.pop("shop")
	check("弹出一层仍锁", stack.depth() == 1 and stack.is_locked())
	stack.pop("dialogue")
	check("全部关闭归还输入", stack.depth() == 0 and not stack.is_locked())
	stack.push("dialogue")
	stack.push("dialogue")
	check("同 token 不重复压栈", stack.depth() == 1)
	stack.clear()
	check("clear 清空", stack.depth() == 0)

func test_cross_year_water() -> void:
	print("\n[4] 跨年浇水差值为正")
	var plot := FarmPlot.new(0)
	plot.state = FarmPlot.State.GROWING
	plot.crop_id = "corn"
	plot.days_grown = 1.0
	plot.last_watered_abs_day = GameCalendar.DAYS_PER_YEAR - 1
	plot.advance_day(GameCalendar.DAYS_PER_YEAR + 2, 4)
	check("跨年后连续缺水会枯死", plot.state == FarmPlot.State.DEAD and plot.dead_reason == "缺水",
		plot.dead_reason)

func test_harvest_resets_water() -> void:
	print("\n[5] 收获后同日补种可浇水")
	var plot := FarmPlot.new(0)
	plot.state = FarmPlot.State.READY
	plot.crop_id = "corn"
	plot.days_grown = 150.0
	plot.last_watered_abs_day = 20
	plot.last_watered_day = 20
	var harvested := plot.harvest()
	check("收获成功", not harvested.is_empty())
	check("收获清空上一茬浇水日", plot.last_watered_abs_day == -1 and plot.last_watered_day == -1)
	check("收获清空浇水次数", plot.days_watered == 0)
	check("收获后可当天浇水", plot.water(20))

func test_weather_determinism() -> void:
	print("\n[6] 天气抽签与预报")
	var cal := GameCalendar.new()
	cal.advance_to_month(4, 1)
	var same := true
	for offset in 30:
		var day := cal.abs_day() + offset
		var a := WeatherSystem.weather_for_day(cal, 2468, offset)
		var b := WeatherSystem.weather_for_day(cal, 2468, offset)
		if a != b or WeatherSystem.weather_cn(a) == "未知":
			same = false
	check("同种子同日天气稳定", same)
	var weather := WeatherSystem.new()
	weather.refresh(cal, 2468)
	check("当天天气已生成", weather.today != "" and weather.today == WeatherSystem.weather_for_day(cal, 2468, 0))
	check("天气预报可读", weather.forecast != ""
		and WeatherSystem.weather_cn(weather.forecast) != "未知",
		"%s → %s" % [WeatherSystem.weather_cn(weather.today), WeatherSystem.weather_cn(weather.forecast)])
	var before := weather.to_dict()
	weather.refresh(cal, 2468)
	check("重复刷新不改同一天天气", weather.to_dict() == before)
	check("冬季预报更可靠", WeatherSystem.forecast_accuracy("winter")
		> WeatherSystem.forecast_accuracy("spring"))
	var mismatch := 0
	for offset in 80:
		var actual := WeatherSystem.weather_for_day(cal, 2468, offset + 1)
		var predicted := WeatherSystem.forecast_for_day(cal, 2468, offset)
		if predicted != actual:
			mismatch += 1
	check("春季预报并非永远准确", mismatch > 0 and mismatch < 30, "→ %d/80 次偏差" % mismatch)

func test_weather_weights() -> void:
	print("\n[7] 四季天气权重表")
	for season in ["spring", "summer", "autumn", "winter"]:
		var weights := WeatherSystem.weights_for(season)
		var total := 0
		for weather_id in weights.keys():
			total += int(weights[weather_id])
			check("%s/%s 有中文名" % [season, weather_id],
				WeatherSystem.weather_cn(String(weather_id)) != "未知")
		check("%s 权重合计 100" % season, total == 100, "→ %d" % total)

func test_weather_effects() -> void:
	print("\n[8] 天气对农场与体力的影响")
	var cal := GameCalendar.new()
	cal.advance_to_month(4, 1)
	var farm := FarmSystem.new(cal)
	farm.till_plot(0)
	check("晴天不自动浇水", farm.apply_weather("sunny", cal.abs_day()) == 0)
	var watered := farm.apply_weather("rain", cal.abs_day())
	check("雨天自动浇一块地", watered == 1, "→ %d 块" % watered)
	check("雨天写入绝对浇水日", farm.get_plot(0).last_watered_abs_day == cal.abs_day())
	check("雨天不重复浇同一块", farm.apply_weather("rain", cal.abs_day()) == 0)
	check("雨天判定", WeatherSystem.waters_crops("rain")
		and WeatherSystem.waters_crops("thunderstorm")
		and not WeatherSystem.waters_crops("sunny"))
	check("暴风雪户外体力倍率更高",
		WeatherSystem.outdoor_stamina_multiplier("blizzard") > 1.5)
	check("晴天体力倍率为 1", WeatherSystem.outdoor_stamina_multiplier("sunny") == 1.0)

func test_weather_stamina_usage() -> void:
	print("\n[9] 暴风雪实际增加农活体力消耗")
	var state := GameState.new()
	state.calendar.advance_to_month(1, 10)
	state.farm.till_plot(0)
	state.player.energy = 100
	var result := ToolBar.apply_tool(ToolBar.Tool.WATER, state.farm, 0, state.player, "",
		WeatherSystem.outdoor_stamina_multiplier("blizzard"))
	check("暴风雪农活仍可执行", bool(result.get("ok", false)), String(result.get("message", "")))
	var expected := 100 - int(ceil(float(StaminaSystem.COST_WATER)
		* WeatherSystem.outdoor_stamina_multiplier("blizzard")))
	check("暴风雪按倍率扣体力", state.player.energy == expected,
		"→ %d" % state.player.energy)

func test_female_sprite_wiring() -> void:
	print("\n[10] 女性主角立绘接线")
	var mgr: Node = root.get_node_or_null("GameStateManager")
	check("GameStateManager 已挂载", mgr != null)
	if mgr == null:
		return
	mgr.new_session()
	mgr.state.player.gender = PlayerProfile.Gender.FEMALE
	var packed: PackedScene = load("res://scenes/player.tscn")
	var node: CharacterBody2D = packed.instantiate()
	get_root().add_child(node)
	check("场景节点已加载", node != null)
	check("女性精灵已应用", bool(node.get("_female")))
	node.queue_free()
	mgr.new_session()
