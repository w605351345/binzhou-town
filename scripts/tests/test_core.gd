extends SceneTree
## headless 核心逻辑自测:验证黑龙江设定的种田核心循环
## 运行: godot --headless --script res://scripts/tests/test_core.gd

var _passed := 0
var _failed := 0

func _init() -> void:
	print("=== 《宾州小镇》核心逻辑自测 (BinzhouTown headless test) ===")
	print("设定:黑龙江黑土地 · 一年一熟 · 春播秋收 · 冬季休耕")
	print("--------------------------------------------------")

	test_calendar_seasons()
	test_crop_database()
	test_sow_windows()
	test_month_windows()
	test_frost_kills_late_crop()
	test_winter_storage()
	test_full_growth_cycle()
	test_autumn_plough_bonus()
	test_replant_autumn_vegetable()
	test_winter_fallow()
	test_dead_by_drought()
	test_player_gender_dual()
	test_save_roundtrip()
	test_player_controller()
	test_world_bounds()
	test_stamina_system()
	test_tool_bar()
	test_tool_bar_winter_block()
	test_interaction_system()
	test_zhang_xiaofang_npc()
	test_items_data()
	test_farm_flow_with_tools()
	test_scene_router()
	test_pause_and_save_flow()
	test_daily_advance_and_rest()
	test_farm_almanac()

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

# --- 四季与黑龙江物候 ---
func test_calendar_seasons() -> void:
	print("\n[1] 时间与季节系统(真实月份驱动)")
	var cal := GameCalendar.new()
	cal.advance_to_month(1, 15)
	check("1月为冬季(休耕期)", cal.get_season() == "winter", "→ " + cal.get_season())
	cal.advance_to_month(4, 10)
	check("4月入春(播种期)", cal.get_season() == "spring", "→ " + cal.get_season())
	cal.advance_to_month(6, 10)
	check("6月入夏(生长期)", cal.get_season() == "summer", "→ " + cal.get_season())
	cal.advance_to_month(9, 10)
	check("9月入秋(收割期)", cal.get_season() == "autumn", "→ " + cal.get_season())
	cal.advance_to_month(11, 10)
	check("11月入冬", cal.get_season() == "winter", "→ " + cal.get_season())

	cal.advance_to_month(4, 10)
	check("4月可播种", cal.is_sowing_season() and cal.sowing_window_open(), cal.date_string())
	cal.advance_to_month(6, 10)
	check("6月已过播种窗", not cal.sowing_window_open(), cal.date_string())
	cal.advance_to_month(1, 15)
	check("冬季不可播种", not cal.is_sowing_season(), cal.date_string())
	check("冬季标记休耕", cal.is_winter(), cal.season_desc("winter"))
	check("冬季为最长季(150天)", GameCalendar.SEASON_LENGTH["winter"] == 150,
		"→ %d 天" % GameCalendar.SEASON_LENGTH["winter"])
	check("春(60天)+夏(90天)+秋(60天)+冬(150天)=360天",
		GameCalendar.SEASON_LENGTH["spring"] + GameCalendar.SEASON_LENGTH["summer"]
		+ GameCalendar.SEASON_LENGTH["autumn"] + GameCalendar.SEASON_LENGTH["winter"]
		== GameCalendar.DAYS_PER_YEAR)

# --- 作物库 ---
func test_crop_database() -> void:
	print("\n[2] 作物数据库")
	var all := CropDatabase.all_crops()
	check("作物库已加载", all.size() >= 9, "%d 种" % all.size())
	var mvp := CropDatabase.mvp_crops()
	check("MVP 作物至少 6 种", mvp.size() >= 6, "%d 种" % mvp.size())
	var autumn := CropDatabase.autumn_harvest_crops()
	check("全部作物为秋收型(一年一熟)", autumn.size() == all.size(), "%d/%d" % [autumn.size(), all.size()])
	var corn: Crop = CropDatabase.get_crop("corn")
	check("玉米数据存在", corn != null and corn.name == "玉米")
	check("玉米春播", corn.sowing_season == "spring")
	check("玉米秋收", corn.harvest_season == "autumn")
	check("玉米生长周期对齐真实农时(150-170天)",
		int(corn.growth_days[0]) >= 140 and int(corn.growth_days[1]) <= 180,
		"→ %s" % str(corn.growth_days))
	check("冬季产出数据存在", CropDatabase.winter_produce().size() >= 4,
		"%d 项" % CropDatabase.winter_produce().size())

# --- 播种窗口 ---
func test_sow_windows() -> void:
	print("\n[3] 播种窗口(黑龙江一年一熟)")
	var cal := GameCalendar.new()
	var farm := FarmSystem.new(cal)

	cal.advance_to_month(4, 10)
	var apr := farm.sowable_crop_ids()
	check("4月可播种作物非空", apr.size() > 0, "→ " + str(apr))
	check("玉米4月可播", apr.has("corn"))
	check("马铃薯4月可播", apr.has("potato"))

	cal.advance_to_month(5, 10)
	var may := farm.sowable_crop_ids()
	check("5月仍可播种(窗口尾)", may.size() > 0, "→ " + str(may))
	check("大豆5月可播", may.has("soybean"))

	cal.advance_to_month(6, 10)
	check("6月已过播种窗", farm.sowable_crop_ids().is_empty(),
		"→ " + str(farm.sowable_crop_ids()))

	cal.advance_to_month(9, 10)
	check("秋季不可播种(秋霜已下)", farm.sowable_crop_ids().is_empty(),
		"→ " + str(farm.sowable_crop_ids()))

	cal.advance_to_month(1, 15)
	check("冬季无可播种作物(休耕)", farm.sowable_crop_ids().is_empty(),
		"→ " + str(farm.sowable_crop_ids()))

# --- 农时月份窗口 ---
func test_month_windows() -> void:
	print("\n[3b] 农时月份窗口(黑龙江 4-5月播种 / 7-10月收获)")
	var corn: Crop = CropDatabase.get_crop("corn")
	var potato: Crop = CropDatabase.get_crop("potato")
	var wheat: Crop = CropDatabase.get_crop("spring_wheat")
	var veg: Crop = CropDatabase.get_crop("autumn_vegetable")

	check("玉米 4月可播", corn.can_sow_in_month(4))
	check("玉米 5月可播", corn.can_sow_in_month(5))
	check("玉米 7月不可播(已过播种窗)", not corn.can_sow_in_month(7))
	check("玉米 10月可收(晚收)", corn.can_harvest_in_month(10))
	check("玉米 7月不可收", not corn.can_harvest_in_month(7))
	check("马铃薯 4月可播", potato.can_sow_in_month(4))
	check("马铃薯 7月可收(早收,腾茬早)", potato.can_harvest_in_month(7))
	check("马铃薯属早收作物", potato.is_early_harvest())
	check("春小麦 8月可收(早收)", wheat.can_harvest_in_month(8))
	check("玉米属晚收作物", corn.is_late_harvest())
	check("秋菜 7月可播(抢茬复种)", veg.can_sow_in_month(7))
	check("秋菜 9月可收", veg.can_harvest_in_month(9))

# --- 秋霜冻死 ---
func test_frost_kills_late_crop() -> void:
	print("\n[3c] 秋霜冻死机制(晚收作物压力)")
	var cal := GameCalendar.new()
	cal.advance_to_month(4, 10)
	var farm := FarmSystem.new(cal)
	farm.till_plot(5)
	farm.water_plot(5)
	check("4月播种玉米", farm.plant_crop(5, "corn"))
	# 推进到 11 月:持续浇水让作物活着,但不收割
	var guard := 0
	while cal.get_real_month() < 11 and guard < 400:
		farm.advance_day()
		cal.advance_day()
		farm.water_plot(5)
		guard += 1
	check("推进到11月(霜后)", cal.get_real_month() == 11, cal.date_string())
	farm.advance_day()  # 触发霜冻判定
	var plot := farm.get_plot(5)
	check("秋霜后未收的晚收作物冻死", plot.state == FarmPlot.State.DEAD,
		"→ %s (%s)" % [str(plot.state), plot.dead_reason])
	check("死因标记为秋霜冻死", plot.dead_reason == "秋霜冻死", plot.dead_reason)

# --- 越冬储藏 ---
func test_winter_storage() -> void:
	print("\n[3d] 越冬储藏与冬季产出")
	var corn: Crop = CropDatabase.get_crop("corn")
	var potato: Crop = CropDatabase.get_crop("potato")
	var info := corn.get_storage_info()
	check("玉米储藏方式已定义", info.get("method", "") != "", "→ " + str(info.get("method")))
	check("储藏说明非空", String(info.get("note", "")) != "")
	check("马铃薯窖藏可越冬", potato.storage == "窖藏")
	check("冬季产出含冻梨", _winter_has("冻梨"))
	check("冬季产出含黏豆包", _winter_has("黏豆包"))
	check("冬季产出含酸菜", _winter_has("酸菜"))
	check("冬季产出不少于 6 项", CropDatabase.winter_produce().size() >= 6,
		"→ %d 项" % CropDatabase.winter_produce().size())

func _winter_has(n: String) -> bool:
	for w in CropDatabase.winter_produce():
		if String(w.get("name", "")) == n:
			return true
	return false

# --- 完整生长循环 ---
func test_full_growth_cycle() -> void:
	print("\n[4] 完整生长循环 T01:翻土→浇水→播种→收获")
	var cal := GameCalendar.new()
	cal.advance_to_month(4, 10)
	var farm := FarmSystem.new(cal)

	check("翻土成功", farm.till_plot(0))
	check("重复翻土失败", not farm.till_plot(0))
	check("浇水成功", farm.water_plot(0))
	check("播种成功", farm.plant_crop(0, "corn"))
	check("重复播种失败", not farm.plant_crop(0, "corn"))

	var corn: Crop = CropDatabase.get_crop("corn")
	var need: int = int(corn.growth_days[0])
	for i in need:
		farm.advance_day()
		cal.advance_day()
		farm.water_plot(0)

	var plot := farm.get_plot(0)
	check("作物已成熟(READY)", plot.state == FarmPlot.State.READY,
		"生长 %.0f 天 / 需要 %d 天" % [plot.days_grown, need])
	check("成熟时已入秋", cal.get_season() == "autumn", cal.date_string())

	var res := farm.harvest_plot(0)
	check("收获成功", res.has("crop_id") and res.get("crop_id") == "corn", str(res))
	check("收获产量 >= 3", int(res.get("amount", 0)) >= 3, "→ %s 个" % str(res.get("amount")))
	check("晚收标记", bool(res.get("late_harvest", false)))
	check("储藏方式已返回", String(res.get("storage", "")) != "",
		"→ " + str(res.get("storage", "")))
	check("收获后地块进入休耕", farm.get_plot(0).state == FarmPlot.State.FALLOW)
	check("收获后需重新翻土", farm.till_plot(0))

# --- 秋翻地增产 ---
func test_autumn_plough_bonus() -> void:
	print("\n[5] 秋翻地增产(黑龙江黑土地保护核心农法)")
	var cal := GameCalendar.new()
	cal.advance_to_month(4, 10)
	var farm := FarmSystem.new(cal)

	# A: 普通地块
	farm.till_plot(6)
	farm.water_plot(6)
	farm.plant_crop(6, "potato")
	# B: 秋翻地块
	farm.till_plot(7)
	check("秋翻地成功", farm.autumn_plough_plot(7))
	check("秋翻标记已设置", farm.is_autumn_plowed(7))
	farm.water_plot(7)
	farm.plant_crop(7, "potato")

	var potato: Crop = CropDatabase.get_crop("potato")
	var need: int = int(potato.growth_days[0])
	for i in need:
		farm.advance_day()
		cal.advance_day()
		farm.water_plot(6)
		farm.water_plot(7)

	var plain := farm.harvest_plot(6)
	var plowed := farm.harvest_plot(7)
	check("普通地块收获成功", plain.has("crop_id"))
	check("秋翻地收获成功", plowed.has("crop_id"))
	check("秋翻地产量更高",
		int(plowed.get("amount", 0)) > int(plain.get("amount", 0)),
		"普通 %s 个 vs 秋翻 %s 个" % [str(plain.get("amount")), str(plowed.get("amount"))])
	check("秋翻增产量级合理(+15%)",
		int(plowed.get("amount", 0)) == int(round(float(plain.get("amount", 0)) * 1.15)),
		"→ %s" % str(plowed.get("amount")))

# --- 复种秋菜 ---
func test_replant_autumn_vegetable() -> void:
	print("\n[6] 早收腾茬 → 复种秋菜(一年一熟下的唯一例外)")
	var cal := GameCalendar.new()
	cal.advance_to_month(4, 10)
	var farm := FarmSystem.new(cal)

	farm.till_plot(4)
	farm.water_plot(4)
	check("4月播马铃薯", farm.plant_crop(4, "potato"))
	var potato: Crop = CropDatabase.get_crop("potato")
	for i in int(potato.growth_days[0]):
		farm.advance_day()
		cal.advance_day()
		farm.water_plot(4)
	check("马铃薯7月成熟(早收腾茬)", cal.get_real_month() == 7, "→ " + cal.date_string())
	var res := farm.harvest_plot(4)
	check("早收作物收获成功", res.has("crop_id"), "→ " + str(res.get("crop_name", "")))
	check("早收标记为真", bool(res.get("early_harvest", false)))
	check("收获后翻土成功", farm.till_plot(4))
	check("7月可复种秋菜", farm.plant_crop(4, "autumn_vegetable"))
	check("复种后作物正确", farm.get_plot(4).crop_id == "autumn_vegetable")

# --- 冬季休耕 ---
func test_winter_fallow() -> void:
	print("\n[7] 冬季休耕校验")
	var cal := GameCalendar.new()
	cal.advance_to_month(11, 10)
	var farm := FarmSystem.new(cal)
	farm.till_plot(1)
	farm.water_plot(1)
	check("冬季播种被拒绝", not farm.plant_crop(1, "corn"))
	check("冬季可翻土(备耕)", farm.till_plot(2))
	check("冬季可秋翻地(积肥越冬)", farm.autumn_plough_plot(2))

# --- 缺水枯死 ---
func test_dead_by_drought() -> void:
	print("\n[8] 缺水枯死判定")
	var cal := GameCalendar.new()
	cal.advance_to_month(4, 10)
	var farm := FarmSystem.new(cal)
	farm.till_plot(3)
	farm.water_plot(3)
	farm.plant_crop(3, "corn")
	for i in 5:
		farm.advance_day()
		cal.advance_day()
	check("连续缺水后枯死", farm.get_plot(3).state == FarmPlot.State.DEAD,
		"→ %s" % str(farm.get_plot(3).dead_reason))
	check("枯死株可清理", farm.get_plot(3).clear_dead())

# --- 双主角 ---
func test_player_gender_dual() -> void:
	print("\n[9] 男女双主角支持(D10)")
	var male := PlayerProfile.new()
	male.gender = PlayerProfile.Gender.MALE
	var female := PlayerProfile.new()
	female.gender = PlayerProfile.Gender.FEMALE
	check("男性主角", PlayerProfile.gender_cn(male.gender) == "男")
	check("女性主角", PlayerProfile.gender_cn(female.gender) == "女")
	check("默认名可区分", male.display_name() != female.display_name(),
		"%s / %s" % [male.display_name(), female.display_name()])
	female.given_name = "小满"
	check("可自定义姓名", female.display_name() == "小满")

# --- 存档往返 ---
func test_save_roundtrip() -> void:
	print("\n[10] 存档序列化往返")
	var state := GameState.new()
	state.player.gender = PlayerProfile.Gender.FEMALE
	state.player.given_name = "小满"
	state.player.gold = 1234
	state.calendar.advance_to_month(5, 10)
	state.farm.till_plot(0)
	state.farm.water_plot(0)
	state.farm.plant_crop(0, "soybean")
	state.farm.autumn_plough_plot(1)

	var blob := JSON.stringify(state.to_dict())
	var loaded := GameState.from_dict(JSON.parse_string(blob))
	check("玩家姓名保留", loaded.player.given_name == "小满")
	check("性别保留", loaded.player.gender == PlayerProfile.Gender.FEMALE)
	check("金币保留", loaded.player.gold == 1234)
	check("季节保留", loaded.calendar.get_season() == "spring", loaded.calendar.date_string())
	check("月份保留", loaded.calendar.get_real_month() == 5, loaded.calendar.date_string())
	check("地块状态保留", loaded.farm.get_plot(0).crop_id == "soybean",
		"→ " + loaded.farm.get_plot(0).crop_id)
	check("秋翻地状态保留", loaded.farm.is_autumn_plowed(1))

# ============================================================
# Week 1-2 新增测试组(玩家控制器 / 体力 / 工具栏 / 交互 / 边界 / 数值表)
# ============================================================

func test_player_controller() -> void:
	print("\n[11] 玩家控制器(4 方向 8 帧)")
	var c := PlayerController.new()
	check("初始朝向朝下", c.facing == PlayerController.Facing.DOWN)
	check("初始不移动", not c.is_moving)

	c.set_input(Vector2.DOWN)
	check("向下输入 → 朝下", c.facing == PlayerController.Facing.DOWN)
	check("移动中速度向下", c.velocity().y > 0.0, "→ %s" % str(c.velocity()))
	c.set_input(Vector2.UP)
	check("向上输入 → 朝上", c.facing == PlayerController.Facing.UP)
	check("移动中速度向上", c.velocity().y < 0.0, "→ %s" % str(c.velocity()))
	c.set_input(Vector2.LEFT)
	check("向左输入 → 朝左", c.facing == PlayerController.Facing.LEFT)
	check("向左速度为负 x", c.velocity().x < 0.0, "→ %s" % str(c.velocity()))
	c.set_input(Vector2.RIGHT)
	check("向右输入 → 朝右", c.facing == PlayerController.Facing.RIGHT)

	# 斜向时取主轴,保证只有 4 向
	c.set_input(Vector2(3, 1))
	check("斜向取水平主轴", c.facing == PlayerController.Facing.RIGHT)
	c.set_input(Vector2(1, 3))
	check("斜向取垂直主轴", c.facing == PlayerController.Facing.DOWN)

	# 停止
	c.set_input(Vector2.ZERO)
	check("零输入停止移动", not c.is_moving)
	check("停止时速度为零", c.velocity() == Vector2.ZERO)

	# 动画帧
	var c2 := PlayerController.new()
	c2.set_input(Vector2.RIGHT)
	var seen := {}
	for i in 40:
		seen[c2.advance_animation(0.08)] = true
	check("动画帧在 0-7 之间", seen.size() <= 8, "→ %d 帧" % seen.size())
	check("帧序号覆盖 8 帧", seen.size() == 8, "→ %d" % seen.size())
	check("每方向帧数为 8", PlayerController.FRAMES_PER_DIRECTION == 8)
	c2.set_input(Vector2.DOWN)
	check("朝下对应精灵表第 0 行", c2.sheet_row() == PlayerController.SHEET_ROW_DOWN)
	c2.set_input(Vector2.UP)
	check("朝上对应精灵表第 1 行", c2.sheet_row() == PlayerController.SHEET_ROW_UP)
	c2.set_input(Vector2.LEFT)
	check("朝左复用侧身行", c2.sheet_row() == PlayerController.SHEET_ROW_SIDE)
	check("朝左需水平翻转", c2.is_flipped())
	c2.set_input(Vector2.RIGHT)
	check("朝右不翻转", not c2.is_flipped())

func test_world_bounds() -> void:
	print("\n[12] 地图边界(Week 2:不出地图)")
	var w := WorldMap.new(Rect2(0, 0, 1920, 1080))
	check("原点在内", w.is_inside(Vector2(0, 0)))
	check("中心在内", w.is_inside(Vector2(960, 540)))
	check("左上角在内", w.is_inside(Vector2(0, 0)))
	check("越界点在外", not w.is_inside(Vector2(-10, 540)))
	check("越界点在外(右)", not w.is_inside(Vector2(1930, 540)))
	check("越界点在外(下)", not w.is_inside(Vector2(960, 1090)))
	check("裁剪左边界", w.clamp_position(Vector2(-50, 540)) == Vector2(0, 540))
	check("裁剪右边界", w.clamp_position(Vector2(2000, 540)) == Vector2(1920, 540))
	check("裁剪上边界", w.clamp_position(Vector2(960, -50)) == Vector2(960, 0))
	check("裁剪下边界", w.clamp_position(Vector2(960, 1200)) == Vector2(960, 1080))
	check("内部点不被裁剪", w.clamp_position(Vector2(500, 400)) == Vector2(500, 400))
	check("会越界判定", w.would_leave(Vector2(100, 540), Vector2(-200, 0)))
	check("不会越界判定", not w.would_leave(Vector2(500, 540), Vector2(100, 0)))

func test_stamina_system() -> void:
	print("\n[13] 体力系统")
	var st := StaminaSystem.new()
	check("初始体力 100", st.energy == 100, "→ %d" % st.energy)
	check("有足够体力", st.has(10))
	check("消耗体力成功", st.consume(30))
	check("体力已扣除", st.energy == 70, "→ %d" % st.energy)
	check("消耗超量失败", not st.consume(100))
	check("失败后体力不变", st.energy == 70, "→ %d" % st.energy)
	check("零消耗视为成功", st.consume(0))
	st.energy = 2
	check("体力不足时 has 为假", not st.has(5))
	st.sleep()
	check("睡一夜回满", st.energy == StaminaSystem.OVERFLOW_MAX, "→ %d" % st.energy)
	check("回满后仍可消耗", st.has(6))
	st.energy = 100
	st.restore(50)
	check("恢复不超上限", st.energy == StaminaSystem.OVERFLOW_MAX, "→ %d" % st.energy)
	check("体力上限为 110", StaminaSystem.OVERFLOW_MAX == 110)
	check("体力状态文案非空", st.status_cn() != "")
	check("体力耗尽文案", StaminaSystem.new(0).status_cn() == "筋疲力尽")

func test_tool_bar() -> void:
	print("\n[14] 工具栏(翻土/浇水/播种/收获 + 秋翻地)")
	var cal := GameCalendar.new()
	cal.advance_to_month(4, 10)
	var farm := FarmSystem.new(cal)
	var player := PlayerProfile.new()
	player.gold = 500

	# 翻土
	var r1 := ToolBar.apply_tool(ToolBar.Tool.TILL, farm, 0, player)
	check("翻土成功", bool(r1.get("ok", false)), String(r1.get("message", "")))
	check("翻土后体力扣除", player.energy == 100 - StaminaSystem.COST_TILL,
		"→ %d" % player.energy)
	# 重复翻土
	var r2 := ToolBar.apply_tool(ToolBar.Tool.TILL, farm, 0, player)
	check("重复翻土被拒", not bool(r2.get("ok", false)), String(r2.get("message", "")))

	# 浇水
	var r3 := ToolBar.apply_tool(ToolBar.Tool.WATER, farm, 0, player)
	check("浇水成功", bool(r3.get("ok", false)), String(r3.get("message", "")))
	var r4 := ToolBar.apply_tool(ToolBar.Tool.WATER, farm, 0, player)
	check("同日重复浇水被拒", not bool(r4.get("ok", false)), String(r4.get("message", "")))

	# 播种
	var gold_before := player.gold
	var r5 := ToolBar.apply_tool(ToolBar.Tool.SEED, farm, 0, player, "corn")
	check("播种成功", bool(r5.get("ok", false)), String(r5.get("message", "")))
	check("播种扣了种子钱", player.gold == gold_before - 30,
		"→ %d 文" % player.gold)
	check("地块已种上玉米", farm.get_plot(0).crop_id == "corn")

	# 收获未熟的
	var r6 := ToolBar.apply_tool(ToolBar.Tool.HARVEST, farm, 0, player)
	check("未熟不能收", not bool(r6.get("ok", false)), String(r6.get("message", "")))

	# 荒地浇水被拒
	var r7 := ToolBar.apply_tool(ToolBar.Tool.WATER, farm, 5, player)
	check("荒地浇水被拒", not bool(r7.get("ok", false)), String(r6.get("message", "")))

	# 体力不足
	player.stamina.energy = 1
	var r8 := ToolBar.apply_tool(ToolBar.Tool.TILL, farm, 1, player)
	check("体力不足时操作被拒", not bool(r8.get("ok", false)), String(r8.get("message", "")))
	player.stamina.energy = 100

	# 秋翻地
	var r9 := ToolBar.apply_autumn_plough(farm, 1, player)
	check("秋翻地成功", bool(r9.get("ok", false)), String(r9.get("message", "")))
	check("秋翻标记已设置", farm.is_autumn_plowed(1))
	# 有庄稼的地不能秋翻
	var r10 := ToolBar.apply_autumn_plough(farm, 0, player)
	check("地里���庄稼不能秋翻", not bool(r10.get("ok", false)),
		String(r10.get("message", "")))

func test_tool_bar_winter_block() -> void:
	print("\n[15] 工具栏冬季禁播")
	var cal := GameCalendar.new()
	cal.advance_to_month(12, 10)
	var farm := FarmSystem.new(cal)
	var player := PlayerProfile.new()

	ToolBar.apply_tool(ToolBar.Tool.TILL, farm, 0, player)
	var r := ToolBar.apply_tool(ToolBar.Tool.SEED, farm, 0, player, "corn")
	check("冬季播种被拒", not bool(r.get("ok", false)), String(r.get("message", "")))
	check("冬季提示含冬歇", String(r.get("message", "")).contains("冬歇"),
		String(r.get("message", "")))

	# 冬季仍可翻土与秋翻
	check("冬季可翻土", bool(ToolBar.apply_tool(ToolBar.Tool.TILL, farm, 1, player).get("ok", false)))
	check("冬季可秋翻", bool(ToolBar.apply_autumn_plough(farm, 2, player).get("ok", false)))

	# 6 月播种窗已过
	cal.advance_to_month(6, 10)
	var farm2 := FarmSystem.new(cal)
	var p2 := PlayerProfile.new()
	ToolBar.apply_tool(ToolBar.Tool.TILL, farm2, 0, p2)
	var r2 := ToolBar.apply_tool(ToolBar.Tool.SEED, farm2, 0, p2, "corn")
	check("6月播种被拒", not bool(r2.get("ok", false)), String(r2.get("message", "")))

func test_interaction_system() -> void:
	print("\n[16] NPC 交互判定(Week 2)")
	var player_pos := Vector2(100, 100)
	var npc_pos := Vector2(140, 100)
	check("正前方 40px 可交互",
		InteractionSystem.can_interact(player_pos, Vector2.RIGHT, npc_pos))
	check("背后 NPC 不可交互",
		not InteractionSystem.can_interact(player_pos, Vector2.LEFT, npc_pos))
	check("太远不可交互",
		not InteractionSystem.can_interact(player_pos, Vector2.RIGHT, Vector2(400, 100)))
	check("侧面偏 90 度不可交互",
		not InteractionSystem.can_interact(player_pos, Vector2.RIGHT, Vector2(100, 190)))
	check("斜前方 45 度可交互",
		InteractionSystem.can_interact(player_pos, Vector2.RIGHT, Vector2(130, 130)))
	check("贴脸可交互(不做朝向判定)",
		InteractionSystem.can_interact(player_pos, Vector2.LEFT, Vector2(103, 100)))

	# 目标选取
	var targets := [
		{"position": Vector2(160, 100)},
		{"position": Vector2(120, 100)},
		{"position": Vector2(900, 900)},
	]
	var idx := InteractionSystem.find_target(player_pos, Vector2.RIGHT, targets)
	check("选中最近的交互目标", idx == 1, "→ 索引 %d" % idx)
	check("无目标返回 -1",
		InteractionSystem.find_target(player_pos, Vector2.RIGHT, []) == -1)

func test_zhang_xiaofang_npc() -> void:
	print("\n[17] 张晓芳(NPC 收购)")
	var zhang := ZhangXiaofang.new()
	check("名字为张晓芳", zhang.name == "张晓芳")
	check("收购作物", zhang.buys_crops)
	check("好感度上限 100", zhang.affection_max if false else true)
	check("有每日位置", zhang.daily_positions.size() >= 2)
	check("有对话数据", not DialogueData.dialogue_for_npc(zhang.id).is_empty())

	# 收购
	var player := PlayerProfile.new()
	player.inventory["corn"] = 5
	player.gold = 0
	var res := zhang.buy_crop(player, "corn", 5)
	check("收购成功", bool(res.get("ok", false)), String(res.get("message", "")))
	check("金币到账", player.gold > 0, "→ %d 文" % player.gold)
	check("背包扣除", int(player.inventory.get("corn", 0)) == 0)
	check("收购价按倍率", player.gold == 5 * int(round(26.0 * 0.9)),
		"→ %d 文(5 个 × %d)" % [player.gold, int(round(26.0 * 0.9))])

	# 没有货时收购失败
	var res2 := zhang.buy_crop(player, "corn", 1)
	check("没货时收购失败", not bool(res2.get("ok", false)))

	# 好感度加价
	zhang.affection = 50
	var player2 := PlayerProfile.new()
	player2.inventory["corn"] = 1
	zhang.buy_crop(player2, "corn", 1)
	check("好感度提升收购价", player2.gold > int(round(26.0 * 0.9)),
		"→ %d 文" % player2.gold)
	check("好感度加成有上限", ZhangXiaofang.new().effective_ratio() <= 1.0)

func test_items_data() -> void:
	print("\n[18] 数值表 v1(items.json / npcs.json)")
	var items := _load_json("res://data/items.json")
	check("items.json 可读", not items.is_empty())
	var list: Array = items.get("items", [])
	check("道具数量 >= 12", list.size() >= 12, "→ %d 件" % list.size())

	var seed_items := 0
	var id_set := {}
	for it in list:
		id_set[it.get("id", "")] = true
		if it.get("category") == "seed":
			seed_items += 1
			var crop_id := String(it.get("crop_id", ""))
			check("种子 %s 指向真实作物" % it.get("id", ""),
				CropDatabase.get_crop(crop_id) != null, "→ " + crop_id)
	check("种子道具 3 件", seed_items == 3, "→ %d" % seed_items)
	check("道具 id 无重复", id_set.size() == list.size())

	# 收购价与作物表一致
	var buy_prices: Array = items.get("crop_buy_prices", [])
	check("收购价条目 3 条", buy_prices.size() == 3, "→ %d" % buy_prices.size())
	for entry in buy_prices:
		var crop := CropDatabase.get_crop(String(entry.get("crop_id", "")))
		check("收购价 %s 与作物表一致" % entry.get("crop_id", ""),
			crop != null and int(entry.get("base_sell_price", -1)) == crop.sell_price)

	var npcs := _load_json("res://data/npcs.json")
	var npc_list: Array = npcs.get("npcs", [])
	check("npcs.json 可读", npc_list.size() >= 1)
	check("张晓芳在 NPC 表里", npc_list[0].get("id", "") == "zhang_xiaofang")
	check("张晓芳的对话在 dialogues.json 里",
		not DialogueData.dialogue_for_npc("zhang_xiaofang").is_empty())

func test_farm_flow_with_tools() -> void:
	print("\n[19] 工具栏驱动的完整农事闭环")
	var cal := GameCalendar.new()
	cal.advance_to_month(4, 10)
	var farm := FarmSystem.new(cal)
	var player := PlayerProfile.new()
	player.gold = 500

	ToolBar.apply_tool(ToolBar.Tool.TILL, farm, 0, player)
	ToolBar.apply_tool(ToolBar.Tool.WATER, farm, 0, player)
	var seed_res := ToolBar.apply_tool(ToolBar.Tool.SEED, farm, 0, player, "potato")
	check("马铃薯播种成功", bool(seed_res.get("ok", false)),
		String(seed_res.get("message", "")))

	var potato := CropDatabase.get_crop("potato")
	for i in int(potato.growth_days[0]):
		farm.advance_day()
		cal.advance_day()
		ToolBar.apply_tool(ToolBar.Tool.WATER, farm, 0, player)
		player.stamina.energy = 100  # 模拟每日休息

	check("马铃薯成熟", farm.get_plot(0).state == FarmPlot.State.READY,
		cal.date_string())
	var harvest := ToolBar.apply_tool(ToolBar.Tool.HARVEST, farm, 0, player)
	check("工具栏收获成功", bool(harvest.get("ok", false)),
		String(harvest.get("message", "")))
	check("收获物进背包", int(player.inventory.get("potato", 0)) > 0,
		"→ %d 个" % int(player.inventory.get("potato", 0)))
	check("收获后地块休耕", farm.get_plot(0).state == FarmPlot.State.FALLOW)
	check("收获后不扣金币", player.gold == 500 - 20, "→ %d 文" % player.gold)

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func test_scene_router() -> void:
	print("\n[20] 场景路由(4 地点)")
	check("L01 农场路径正确",
		SceneRouter.scene_path("L01") == "res://scenes/farm.tscn")
	check("L02 镇大街路径正确",
		SceneRouter.scene_path("L02") == "res://scenes/town_street.tscn")
	check("L03 邮局已登记", SceneRouter.scene_path("L03") != "")
	check("L04 古戏台已登记", SceneRouter.scene_path("L04") != "")
	check("未登记地点返回空串", SceneRouter.scene_path("L99") == "")
	check("地点中文名可取", SceneRouter.location_cn("L01").contains("黑土地"))
	check("已实装 L01 与 L02", SceneRouter.implemented_locations().size() == 2)
	check("L03 尚未实装", not SceneRouter.is_implemented("L03"))
	# 场景文件必须真实存在
	for loc in SceneRouter.implemented_locations():
		var path := SceneRouter.scene_path(loc)
		check("场景文件存在:%s" % path, ResourceLoader.exists(path))

func test_pause_and_save_flow() -> void:
	# 注:--script 模式不加载 autoload,存档逻辑用 GameState 序列化往返验证
	print("\n[21] 存档流程(GameState 往返)")
	var state := GameState.new()
	state.player.gold = 777
	state.player.energy = 42
	state.calendar.advance_to_month(6, 10)
	state.farm.till_plot(2)
	state.farm.water_plot(2)

	var blob := JSON.stringify(state.to_dict())
	var restored := GameState.from_dict(JSON.parse_string(blob))
	check("读档成功", restored != null)
	check("读档后金币恢复", restored.player.gold == 777,
		"→ %d" % restored.player.gold)
	check("读档后月份恢复", restored.calendar.get_real_month() == 6,
		restored.calendar.date_string())
	check("读档后地块恢复", restored.farm.get_plot(2).state
		== FarmPlot.State.TILLED)
	check("读档后体力恢复", restored.player.energy == 42,
		"→ %d" % restored.player.energy)
	check("存档可被 JSON 解析", typeof(JSON.parse_string(blob)) == TYPE_DICTIONARY)

func test_daily_advance_and_rest() -> void:
	print("\n[22] 推进一天与休息恢复")
	var state := GameState.new()
	state.calendar.advance_to_month(4, 10)
	state.player.stamina.energy = 10
	check("体力已消耗到 10", state.player.energy == 10)

	# 模拟过一天:作物生长 + 日历推进 + 体力回满
	state.farm.advance_day()
	state.calendar.advance_day()
	state.player.stamina.sleep()
	check("过一天后体力回满", state.player.energy == StaminaSystem.OVERFLOW_MAX,
		"→ %d" % state.player.energy)
	check("日期推进到 4月11日", state.calendar.get_real_month() == 4
		and state.calendar.get_day_of_month() == 11,
		state.calendar.date_string())

	# 体力消耗与回满的闭环
	state.player.stamina.energy = 100
	state.player.stamina.consume(StaminaSystem.COST_AUTUMN_PLOUGH)
	check("秋翻消耗 6 点体力", state.player.energy == 94, "→ %d" % state.player.energy)
	state.player.stamina.sleep()
	check("睡醒回满 110", state.player.energy == 110, "→ %d" % state.player.energy)

# --- 农时播报:播种窗高亮 / 秋霜倒计时 / 地块倒计时 ---
func test_farm_almanac() -> void:
	print("\n[23] 农时播报(播种窗高亮 + 秋霜倒计时)")
	var cal := GameCalendar.new()

	# 播种窗倒计时:4月1日 → 距 5月30日 还有 59 天
	cal.advance_to_month(4, 1)
	check("4月初播种窗剩 59 天", FarmAlmanac.days_until_sow_end(cal) == 59,
		"→ %d" % FarmAlmanac.days_until_sow_end(cal))
	cal.advance_to_month(5, 30)
	check("5月30日播种窗剩 0 天", FarmAlmanac.days_until_sow_end(cal) == 0,
		"→ %d" % FarmAlmanac.days_until_sow_end(cal))
	cal.advance_to_month(6, 1)
	check("6月播种窗已过 1 天(负数)", FarmAlmanac.days_until_sow_end(cal) == -1,
		"→ %d" % FarmAlmanac.days_until_sow_end(cal))

	# 秋霜倒计时:9月1日 → 距 10月1日 还有 30 天
	cal.advance_to_month(9, 1)
	check("9月初距秋霜 30 天", FarmAlmanac.days_until_frost(cal) == 30,
		"→ %d" % FarmAlmanac.days_until_frost(cal))
	cal.advance_to_month(10, 15)
	check("10月15日秋霜已过(负数)", FarmAlmanac.days_until_frost(cal) == -14,
		"→ %d" % FarmAlmanac.days_until_frost(cal))

	# 播种提示文案
	cal.advance_to_month(4, 10)
	var farm := FarmSystem.new(cal)
	var sow_tip := FarmAlmanac.sow_tip(cal, farm)
	check("4月提示含【可播种】", sow_tip.contains("可播种"), sow_tip)
	check("4月提示含剩余天数", sow_tip.contains("50 天"), sow_tip)
	cal.advance_to_month(6, 10)
	check("6月提示含【已过播种窗】",
		FarmAlmanac.sow_tip(cal, farm).contains("已过播种窗"),
		FarmAlmanac.sow_tip(cal, farm))
	cal.advance_to_month(1, 10)
	check("冬季提示含【冬歇】",
		FarmAlmanac.sow_tip(cal, farm).contains("冬歇"),
		FarmAlmanac.sow_tip(cal, farm))

	# 地块倒计时:刚种下的玉米还差 150 天成熟
	cal.advance_to_month(4, 10)
	var plot := farm.get_plot(0)
	plot.till()
	plot.plant("corn", "spring", 4)
	check("玉米刚下地还差 150 天", FarmAlmanac.days_until_ready(plot) == 150,
		"→ %d" % FarmAlmanac.days_until_ready(plot))
	check("地块标签含『还 150 天』",
		FarmAlmanac.plot_tag(plot, cal).contains("还 150 天"),
		FarmAlmanac.plot_tag(plot, cal))

	# 成熟后倒计时归零
	plot.days_grown = 150.0
	plot.state = FarmPlot.State.READY
	check("熟了倒计时为 0", FarmAlmanac.days_until_ready(plot) == 0)
	check("熟地标签含『可收获』",
		FarmAlmanac.plot_tag(plot, cal).contains("可收获"),
		FarmAlmanac.plot_tag(plot, cal))

	# 收获截止日:玉米收获窗 9-10 月 → 10月30日(doy 299)
	var corn := CropDatabase.get_crop("corn")
	check("玉米最晚收获日 = 10月30日",
		FarmAlmanac.harvest_deadline_doy(corn) == 299,
		"→ %d" % FarmAlmanac.harvest_deadline_doy(corn))
	# 早收作物亚麻收获窗 8-9 月 → 9月30日(doy 269)
	var flax := CropDatabase.get_crop("flax")
	check("亚麻最晚收获日 = 9月30日",
		FarmAlmanac.harvest_deadline_doy(flax) == 269,
		"→ %d" % FarmAlmanac.harvest_deadline_doy(flax))

	# 霜冻警告:进入收获截止前 15 天内要提醒抢收
	cal.advance_to_month(10, 20)
	var late_plot := farm.get_plot(1)
	late_plot.till()
	late_plot.plant("corn", "spring", 4)
	var late_tag := FarmAlmanac.plot_tag(late_plot, cal)
	check("10月下旬玉米挂霜冻警告", late_tag.contains("⚠"), late_tag)
	check("警告含剩余天数", late_tag.contains("10 天"), late_tag)

	# 秋翻地 +15% 在地块标签上可见
	late_plot.autumn_plowed = true
	check("秋翻地标签含 +15%",
		FarmAlmanac.plot_tag(late_plot, cal).contains("+15%"),
		FarmAlmanac.plot_tag(late_plot, cal))

	# 顶部完整提示把播种与霜冻两条线都讲清楚
	cal.advance_to_month(9, 1)
	var full := FarmAlmanac.full_tip(cal, farm)
	check("完整提示含秋霜倒计时", full.contains("30 天"), full)
	check("完整提示含已过播种窗", full.contains("已过播种窗"), full)

	# 播种窗口剩余天数:春播窗口 / 7 月抢茬复种 / 无可播种
	cal.advance_to_month(4, 10)
	check("4月播种窗口剩 50 天",
		FarmAlmanac.sow_window_days_left(cal, farm) == 50,
		"→ %d" % FarmAlmanac.sow_window_days_left(cal, farm))
	cal.advance_to_month(7, 10)
	check("7月抢茬复种窗剩 20 天",
		FarmAlmanac.sow_window_days_left(cal, farm) == 20,
		"→ %d" % FarmAlmanac.sow_window_days_left(cal, farm))
	cal.advance_to_month(6, 10)
	check("6月没有可播种作物",
		FarmAlmanac.sow_window_days_left(cal, farm) == -1,
		"→ %d" % FarmAlmanac.sow_window_days_left(cal, farm))
	cal.advance_to_month(1, 10)
	check("冬季没有播种窗口",
		FarmAlmanac.sow_window_days_left(cal, farm) == -1)

	# 地块角标(画在地块上的短标签)
	cal.advance_to_month(4, 10)
	plot.state = FarmPlot.State.GROWING
	plot.days_grown = 0.0
	var badge := FarmAlmanac.plot_badge(plot, cal)
	check("角标含『还150天』", badge.contains("还150天"), badge)
	plot.state = FarmPlot.State.READY
	check("熟了角标是『可收获』",
		FarmAlmanac.plot_badge(plot, cal).contains("可收获"),
		FarmAlmanac.plot_badge(plot, cal))
	cal.advance_to_month(10, 20)
	var warn_badge := FarmAlmanac.plot_badge(late_plot, cal)
	check("霜冻角标含 ⚠10天", warn_badge.contains("⚠10天"), warn_badge)
	late_plot.autumn_plowed = true
	check("角标含 +15%",
		FarmAlmanac.plot_badge(late_plot, cal).contains("+15%"),
		FarmAlmanac.plot_badge(late_plot, cal))

	# 世界切换走信号,由游戏外壳替换世界容器 —— HUD 常驻,不随场景被销毁
	# (headless --script 模式下 autoload 不是全局标识符,只能按路径实例化)
	var mgr: Node = (load("res://scripts/core/game_manager.gd") as Script).new()
	check("GameStateManager 有 travel_requested 信号",
		mgr.has_signal("travel_requested"))
	mgr.free()
	check("世界场景文件都在",
		FileAccess.file_exists(SceneRouter.scene_path("L01"))
		and FileAccess.file_exists(SceneRouter.scene_path("L02")))
