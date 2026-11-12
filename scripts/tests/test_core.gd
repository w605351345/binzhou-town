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
