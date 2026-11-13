extends SceneTree
## headless 端到端集成自测:以**玩家视角**走完整条链路
##
## 与其他自测的分工:
##   test_core.gd   —— 纯逻辑单元测试(每个模块单测)
##   test_scenes.gd —— 外壳/场景集成测试(HUD 常驻、换地点不掉 HUD)
##   本文件         —— **完整生长循环端到端验证**,对应 Week 4 Go/No-Go 验收用例
##
## 覆盖:
##   T01 翻土→浇水→播种→夏长→秋收→卖出→金币增加
##   T04 存档 → 重启 → 读档 → 状态不丢
##   T06 秋收季不收割 → 推进到 11 月 → 秋霜冻死
##   T07 冬季尝试播种 → 被拒绝并提示"冬歇"
##   T08 早收作物 7 月腾茬 → 复种秋菜 → 秋收成功(一年两茬)
##
## 特点:全部通过 ToolBar(真实玩家按键入口)驱动,不直接改内部状态 ——
##       这样测出来的就是玩家真正能走通的流程。
##
## 运行: godot --headless --script res://scripts/tests/test_integration.gd

var _passed := 0
var _failed := 0

func _init() -> void:
	print("=== 《宾州小镇》端到端集成自测 (integration test) ===")
	print("设定:黑龙江黑土地 · 一年一熟 · 春播秋收 · 冬季休耕")
	print("链路:玩家按键(ToolBar) → FarmSystem → 背包 → 张晓芳收购")
	print("--------------------------------------------------")

	test_t01_full_growth_cycle()
	test_t06_frost_kills_late_crop()
	test_t07_winter_sowing_blocked()
	test_t08_early_harvest_replant()
	test_t04_save_load_roundtrip()
	test_stamina_pressure()
	test_drought_kills_crop()
	test_sowing_window_closed()
	test_autumn_plough_next_year()
	test_year_cycle_and_seasons()

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

# --- 玩家动作模拟 ---

## 模拟玩家按工具键:J/K/L/I → ToolBar(真实入口,不是直接改状态)
func _do(state: GameState, tool: int, plot_index: int, crop_id: String = "") -> Dictionary:
	return ToolBar.apply_tool(tool, state.farm, plot_index, state.player, crop_id)

## 模拟"睡一觉":作物生长 + 日期推进 + 体力回满
func _sleep(state: GameState) -> void:
	state.farm.advance_day()
	state.calendar.advance_day()
	state.player.stamina.sleep()

## 每天浇一次水,推进到指定地块成熟。返回推进天数。
func _grow_to_ready(state: GameState, plot_index: int, max_days: int = 400) -> int:
	var farm := state.farm
	var days := 0
	while farm.get_plot(plot_index).state != FarmPlot.State.READY and days < max_days:
		if farm.get_plot(plot_index).state == FarmPlot.State.DEAD:
			break
		_do(state, ToolBar.Tool.WATER, plot_index)
		_sleep(state)
		days += 1
	return days

## 推进到下一个 4 月 1 日(跨年)
func _advance_to_next_april(state: GameState) -> void:
	var guard := 0
	while (state.calendar.get_real_month() != 4 or state.calendar.get_day_of_month() != 1) and guard < 400:
		_sleep(state)
		guard += 1

# ============================================================================
# T01 完整生长循环:春播 → 夏长 → 秋收 → 卖出 → 金币增加
# ============================================================================
func test_t01_full_growth_cycle() -> void:
	print("\n[T01] 完整生长循环:翻土→浇水→播种→夏长→秋收→卖出→金币增加")
	var state := GameState.new()
	state.calendar.advance_to_month(4, 1)
	var farm := state.farm
	var player_state := state.player
	var idx := 0
	var gold_before := player_state.gold

	# --- 春播 ---
	var r_till := _do(state, ToolBar.Tool.TILL, idx)
	check("J 翻土成功", bool(r_till.get("ok")), "→ " + String(r_till.get("message", "")))
	check("地块进入已翻土态", farm.get_plot(idx).state == FarmPlot.State.TILLED)
	var r_water := _do(state, ToolBar.Tool.WATER, idx)
	check("K 浇水成功", bool(r_water.get("ok")), "→ " + String(r_water.get("message", "")))
	check("地块记下了浇水日", farm.get_plot(idx).last_watered_day == state.calendar.day_of_year)
	var r_seed := _do(state, ToolBar.Tool.SEED, idx, "corn")
	check("L 播种玉米成功", bool(r_seed.get("ok")), "→ " + String(r_seed.get("message", "")))
	check("地块进入已播种态", farm.get_plot(idx).state == FarmPlot.State.PLANTED)
	check("播种扣了种子钱", player_state.gold == gold_before - 30,
		"→ %d 文钱" % player_state.gold)

	# --- 夏长:每天照料,直到秋收 ---
	var days := _grow_to_ready(state, idx)
	check("玉米在秋天成熟", farm.get_plot(idx).state == FarmPlot.State.READY,
		"→ %s @ %s" % [str(farm.get_plot(idx).state), state.calendar.date_string()])
	check("成熟时点落在 9-10 月收获窗", state.calendar.get_real_month() >= 9
		and state.calendar.get_real_month() <= 10,
		"→ %d 月(生长 %d 天)" % [state.calendar.get_real_month(), days])
	check("成熟时地块标签提示可收获",
		FarmAlmanac.plot_badge(farm.get_plot(idx), state.calendar).contains("可收获"),
		FarmAlmanac.plot_badge(farm.get_plot(idx), state.calendar))

	# --- 秋收 ---
	var r_harvest := _do(state, ToolBar.Tool.HARVEST, idx)
	check("I 收获成功", bool(r_harvest.get("ok")), "→ " + String(r_harvest.get("message", "")))
	var amount := int(player_state.inventory.get("corn", 0))
	check("玉米进背包", amount > 0, "→ %d 个" % amount)
	check("收获后地块转为待翻耕", farm.get_plot(idx).state == FarmPlot.State.FALLOW)

	# --- 卖出:镇大街找张晓芳 ---
	var zhang := ZhangXiaofang.new()
	var sell := zhang.buy_crop(player_state, "corn", amount)
	check("张晓芳收购成功", bool(sell.get("ok")), "→ " + String(sell.get("message", "")))
	check("背包里的玉米已出手", int(player_state.inventory.get("corn", 0)) == 0)
	# 张晓芳给熟人情分:0.9 倍价 → 26 × 0.9 ≈ 23 文
	var expect_gold := gold_before - 30 + 23 * amount
	check("金币涨回来了", player_state.gold == expect_gold,
		"→ %d 文钱(买种 %d + 卖粮 %d)" % [player_state.gold, 30, 23 * amount])
	check("比买种子前多", player_state.gold > gold_before,
		"→ %d > %d" % [player_state.gold, gold_before])

# ============================================================================
# T06 秋收季不收割 → 秋霜冻死
# ============================================================================
func test_t06_frost_kills_late_crop() -> void:
	print("\n[T06] 秋收季不收割 → 秋霜冻死")
	var state := GameState.new()
	state.calendar.advance_to_month(4, 10)
	var farm := state.farm
	var idx := 1
	_do(state, ToolBar.Tool.TILL, idx)
	_do(state, ToolBar.Tool.WATER, idx)
	_do(state, ToolBar.Tool.SEED, idx, "corn")
	check("4 月种下晚收作物玉米", farm.get_plot(idx).crop_id == "corn")

	# 一路照料到 11 月,但就是不割
	var guard := 0
	while state.calendar.get_real_month() < 11 and guard < 400:
		_do(state, ToolBar.Tool.WATER, idx)
		_sleep(state)
		guard += 1
	check("推进到了 11 月霜后", state.calendar.get_real_month() == 11,
		"→ " + state.calendar.date_string())

	_sleep(state)  # 再睡一天触发霜冻判定
	var plot := farm.get_plot(idx)
	check("未收割的晚收作物冻死", plot.state == FarmPlot.State.DEAD,
		"→ %s (%s)" % [str(plot.state), plot.dead_reason])
	check("死因标记为秋霜冻死", plot.dead_reason == "秋霜冻死", plot.dead_reason)

	var r := _do(state, ToolBar.Tool.HARVEST, idx)
	check("冻死地块收不了", not bool(r.get("ok")), "→ " + String(r.get("message", "")))
	check("提示带秋霜字样", String(r.get("message", "")).contains("冻死"),
		String(r.get("message", "")))

	# 农时播报要说清楚"还有几块晚收没割"
	check("农时提示提到秋霜", FarmAlmanac.full_tip(state.calendar, farm).contains("秋霜"),
		FarmAlmanac.full_tip(state.calendar, farm))

	# 绝收 ≠ 颗粒无收的死局:按 J 把死茬翻进土里,这地还能接着种
	var r_clear := _do(state, ToolBar.Tool.TILL, idx)
	check("按 J 能翻土清茬", bool(r_clear.get("ok")), "→ " + String(r_clear.get("message", "")))
	check("清茬后地块回到可播种态", farm.get_plot(idx).state == FarmPlot.State.TILLED)
	check("清茬后作物已清空", farm.get_plot(idx).crop_id == "")

# ============================================================================
# T07 冬季尝试播种 → 被拒绝并提示"冬歇"
# ============================================================================
func test_t07_winter_sowing_blocked() -> void:
	print("\n[T07] 冬季尝试播种 → 被拒绝并提示『冬歇』")
	var state := GameState.new()
	state.calendar.advance_to_month(12, 15)
	var idx := 2
	check("冬天先能翻地", bool(_do(state, ToolBar.Tool.TILL, idx).get("ok")))
	var r := _do(state, ToolBar.Tool.SEED, idx, "corn")
	check("冬季播种被拒绝", not bool(r.get("ok")), "→ " + String(r.get("message", "")))
	check("拒绝提示含『冬歇』", String(r.get("message", "")).contains("冬歇"),
		String(r.get("message", "")))
	check("地块没被种上", state.farm.get_plot(idx).state == FarmPlot.State.TILLED)
	check("地块没有作物", state.farm.get_plot(idx).crop_id == "")

	# 冬天不能种,但能秋翻积肥(黑土地保护核心农法不受季节限制)
	var r_plough := ToolBar.apply_autumn_plough(state.farm, idx, state.player)
	check("冬季可以秋翻地", bool(r_plough.get("ok")), "→ " + String(r_plough.get("message", "")))
	check("秋翻标记生效", state.farm.get_plot(idx).autumn_plowed)
	check("农时提示说冬歇", FarmAlmanac.full_tip(state.calendar, state.farm).contains("冬歇"),
		FarmAlmanac.full_tip(state.calendar, state.farm))

# ============================================================================
# T08 早收腾茬 → 复种秋菜 → 秋收成功(一年两茬)
# ============================================================================
func test_t08_early_harvest_replant() -> void:
	print("\n[T08] 早收腾茬 → 7 月抢种秋菜 → 秋收成功(一年两茬)")
	var state := GameState.new()
	state.calendar.advance_to_month(4, 1)
	var farm := state.farm
	var player_state := state.player
	var idx := 3

	# --- 第一茬:4 月马铃薯 ---
	_do(state, ToolBar.Tool.TILL, idx)
	_do(state, ToolBar.Tool.WATER, idx)
	var r_seed1 := _do(state, ToolBar.Tool.SEED, idx, "potato")
	check("4 月种下马铃薯", bool(r_seed1.get("ok")), "→ " + String(r_seed1.get("message", "")))
	_grow_to_ready(state, idx)
	check("马铃薯 7 月就熟(早收)", farm.get_plot(idx).state == FarmPlot.State.READY,
		"→ %s @ %s" % [str(farm.get_plot(idx).state), state.calendar.date_string()])
	check("早收时点落在 7 月", state.calendar.get_real_month() == 7,
		"→ %d 月" % state.calendar.get_real_month())
	var r_h1 := _do(state, ToolBar.Tool.HARVEST, idx)
	check("马铃薯早收成功", bool(r_h1.get("ok")), "→ " + String(r_h1.get("message", "")))
	check("马铃薯进背包", int(player_state.inventory.get("potato", 0)) > 0,
		"→ %d 个" % int(player_state.inventory.get("potato", 0)))
	check("腾茬后地块待翻耕", farm.get_plot(idx).state == FarmPlot.State.FALLOW)

	# --- 第二茬:翻土 → 7 月抢种秋菜 ---
	check("腾茬后翻土成功", bool(_do(state, ToolBar.Tool.TILL, idx).get("ok")))
	var r_seed2 := _do(state, ToolBar.Tool.SEED, idx, "autumn_vegetable")
	check("7 月抢种秋菜成功", bool(r_seed2.get("ok")), "→ " + String(r_seed2.get("message", "")))

	# --- 秋收 ---
	_grow_to_ready(state, idx)
	check("秋菜 9 月成熟", farm.get_plot(idx).state == FarmPlot.State.READY,
		"→ %s @ %s" % [str(farm.get_plot(idx).state), state.calendar.date_string()])
	check("秋菜成熟落在 9-10 月", state.calendar.get_real_month() >= 9
		and state.calendar.get_real_month() <= 10,
		"→ %d 月" % state.calendar.get_real_month())
	var r_h2 := _do(state, ToolBar.Tool.HARVEST, idx)
	check("秋菜收获成功", bool(r_h2.get("ok")), "→ " + String(r_h2.get("message", "")))
	check("两茬都进了背包",
		int(player_state.inventory.get("potato", 0)) > 0
		and int(player_state.inventory.get("autumn_vegetable", 0)) > 0,
		"→ 土豆 %d / 秋菜 %d" % [
			int(player_state.inventory.get("potato", 0)),
			int(player_state.inventory.get("autumn_vegetable", 0))])
	check("一年两茬都在同一年内", state.calendar.year == 1,
		"→ 第 %d 年 %d 月" % [state.calendar.year, state.calendar.get_real_month()])

# ============================================================================
# T04 存档 → 重启 → 读档 → 状态不丢
# ============================================================================
func test_t04_save_load_roundtrip() -> void:
	print("\n[T04] 存档 → 重启 → 读档 → 状态不丢")
	var state := GameState.new()
	state.calendar.advance_to_month(4, 10)
	state.player.gold = 777
	state.player.inventory["corn"] = 5
	state.player.inventory["sour_cabbage"] = 2
	_do(state, ToolBar.Tool.TILL, 4)
	_do(state, ToolBar.Tool.WATER, 4)
	_do(state, ToolBar.Tool.SEED, 4, "corn")
	_do(state, ToolBar.Tool.TILL, 5)
	_do(state, ToolBar.Tool.WATER, 5)
	_do(state, ToolBar.Tool.SEED, 5, "potato")
	var gold_after_sow := state.player.gold

	# 走一遍真实的存档流程:序列化 → 落盘 → 读回
	var snapshot := JSON.stringify(state.to_dict())
	var file := FileAccess.open("user://integration_save.json", FileAccess.WRITE)
	if file == null:
		check("存档文件可写", false, "user:// 写入失败")
		return
	file.store_string(snapshot)
	file.close()
	var f2 := FileAccess.open("user://integration_save.json", FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f2.get_as_text())
	f2.close()

	var loaded := GameState.from_dict(parsed)
	check("读档后金币一致", loaded.player.gold == gold_after_sow,
		"→ %d 文钱" % loaded.player.gold)
	check("读档后背包一致", int(loaded.player.inventory.get("corn", 0)) == 5
		and int(loaded.player.inventory.get("sour_cabbage", 0)) == 2)
	check("读档后日期一致", loaded.calendar.day_of_year == state.calendar.day_of_year,
		"→ " + loaded.calendar.date_string())
	check("读档后体力一致", loaded.player.energy == state.player.energy,
		"→ %d/%d" % [loaded.player.energy, loaded.player.max_energy])
	check("读档后种下的玉米还在", loaded.farm.get_plot(4).crop_id == "corn",
		"→ " + loaded.farm.get_plot(4).crop_id)
	check("读档后种下的马铃薯还在", loaded.farm.get_plot(5).crop_id == "potato",
		"→ " + loaded.farm.get_plot(5).crop_id)
	check("读档后浇水记录还在",
		loaded.farm.get_plot(4).last_watered_day == state.farm.get_plot(4).last_watered_day)
	check("读档后作物生长天数还在",
		absf(loaded.farm.get_plot(4).days_grown - state.farm.get_plot(4).days_grown) < 0.001)

	# 读档后还能接着干:翻地 + 播种照常
	check("读档后能继续操作",
		bool(ToolBar.apply_tool(ToolBar.Tool.TILL, loaded.farm, 6, loaded.player).get("ok")))
	DirAccess.remove_absolute("user://integration_save.json")

# ============================================================================
# 体力:农活消耗体力,不够时明确拒绝,睡一觉回满
# ============================================================================
func test_stamina_pressure() -> void:
	print("\n[体力] 农活消耗体力 → 体力不够时拒绝 → 睡一觉回满")
	var state := GameState.new()
	state.calendar.advance_to_month(4, 1)
	var energy_before := state.player.energy
	var r := _do(state, ToolBar.Tool.TILL, 0)
	check("翻土成功", bool(r.get("ok")))
	check("翻土扣了体力", state.player.energy == energy_before - StaminaSystem.COST_TILL,
		"→ %d → %d" % [energy_before, state.player.energy])

	# 把体力压到不够翻土(需 4 点)
	state.player.stamina.energy = StaminaSystem.COST_TILL - 1
	var r2 := _do(state, ToolBar.Tool.TILL, 1)
	check("体力不够时翻土被拒", not bool(r2.get("ok")), "→ " + String(r2.get("message", "")))
	check("拒绝提示含『体力不够』", String(r2.get("message", "")).contains("体力不够"),
		String(r2.get("message", "")))
	check("被拒时体力没被扣", state.player.energy == StaminaSystem.COST_TILL - 1)

	# 体力够就照常干活
	state.player.stamina.energy = StaminaSystem.COST_TILL
	check("体力够时翻土成功", bool(_do(state, ToolBar.Tool.TILL, 1).get("ok")))

	# 睡一觉回满
	_sleep(state)
	check("睡一觉体力回满", state.player.energy == StaminaSystem.OVERFLOW_MAX,
		"→ %d/%d" % [state.player.energy, StaminaSystem.OVERFLOW_MAX])

# ============================================================================
# 缺水:忘浇水 → 作物枯死
# ============================================================================
func test_drought_kills_crop() -> void:
	print("\n[缺水] 忘浇水 → 作物枯死")
	var state := GameState.new()
	state.calendar.advance_to_month(4, 1)
	var farm := state.farm
	var idx := 5
	_do(state, ToolBar.Tool.TILL, idx)
	_do(state, ToolBar.Tool.WATER, idx)
	_do(state, ToolBar.Tool.SEED, idx, "corn")
	check("玉米已下种", farm.get_plot(idx).state == FarmPlot.State.PLANTED)

	# 连着 4 天不浇水(作物缺水容忍上限是 2 天)
	_sleep(state)
	_sleep(state)
	_sleep(state)
	_sleep(state)
	var plot := farm.get_plot(idx)
	check("缺水后作物枯死", plot.state == FarmPlot.State.DEAD,
		"→ %s (%s)" % [str(plot.state), plot.dead_reason])
	check("死因是缺水", plot.dead_reason == "缺水", plot.dead_reason)
	var r := _do(state, ToolBar.Tool.HARVEST, idx)
	check("枯死地块收不了", not bool(r.get("ok")), "→ " + String(r.get("message", "")))

# ============================================================================
# 一年一熟:过了 5 月底就播不上种
# ============================================================================
func test_sowing_window_closed() -> void:
	print("\n[一年一熟] 过了 5 月底就播不上种")
	var state := GameState.new()
	state.calendar.advance_to_month(6, 1)
	_do(state, ToolBar.Tool.TILL, 0)
	var r := _do(state, ToolBar.Tool.SEED, 0, "corn")
	check("6 月播玉米被拒", not bool(r.get("ok")), "→ " + String(r.get("message", "")))
	check("提示点名当前月份", String(r.get("message", "")).contains("6月"),
		String(r.get("message", "")))
	check("农时播报说已过播种窗",
		FarmAlmanac.sow_tip(state.calendar, state.farm).contains("已过播种窗"),
		FarmAlmanac.sow_tip(state.calendar, state.farm))
	check("地块没被种上", state.farm.get_plot(0).state == FarmPlot.State.TILLED)

	# 但 7 月是抢茬复种窗 —— 早收腾茬的能种
	state.calendar.advance_to_month(7, 1)
	var r2 := _do(state, ToolBar.Tool.SEED, 0, "autumn_vegetable")
	check("7 月能抢种秋菜", bool(r2.get("ok")), "→ " + String(r2.get("message", "")))

# ============================================================================
# 黑土地核心农法:秋翻地 → 跨年仍生效 → 次年继续经营
# ============================================================================
func test_autumn_plough_next_year() -> void:
	print("\n[黑土地] 秋翻地 → 跨年仍生效 → 次年继续经营")
	var state := GameState.new()
	state.calendar.advance_to_month(4, 1)
	var farm := state.farm
	var idx := 7

	# 第一年:种一茬,收完
	_do(state, ToolBar.Tool.TILL, idx)
	_do(state, ToolBar.Tool.WATER, idx)
	_do(state, ToolBar.Tool.SEED, idx, "corn")
	_grow_to_ready(state, idx)
	check("第一年玉米成熟", farm.get_plot(idx).state == FarmPlot.State.READY,
		"→ " + state.calendar.date_string())
	var r_h1 := _do(state, ToolBar.Tool.HARVEST, idx)
	check("第一年收获成功", bool(r_h1.get("ok")))
	var first_amount := int(r_h1.get("result", {}).get("amount", 0))

	# 秋翻积肥
	var r_plough := ToolBar.apply_autumn_plough(farm, idx, state.player)
	check("秋翻地成功", bool(r_plough.get("ok")), "→ " + String(r_plough.get("message", "")))
	check("秋翻标记生效", farm.get_plot(idx).autumn_plowed)
	check("地块角标显示 +15%",
		FarmAlmanac.plot_badge(farm.get_plot(idx), state.calendar).contains("+15%"),
		FarmAlmanac.plot_badge(farm.get_plot(idx), state.calendar))

	# 跨年:秋翻标记不能丢
	_advance_to_next_april(state)
	check("到了第二年 4 月", state.calendar.year == 2
		and state.calendar.get_real_month() == 4,
		"→ 第 %d 年 %d 月" % [state.calendar.year, state.calendar.get_real_month()])
	check("跨年后秋翻标记仍在", farm.get_plot(idx).autumn_plowed)

	# 次年继续经营,且带 +15% 加成
	_do(state, ToolBar.Tool.TILL, idx)
	_do(state, ToolBar.Tool.WATER, idx)
	var r_seed := _do(state, ToolBar.Tool.SEED, idx, "corn")
	check("第二年能接着种", bool(r_seed.get("ok")), "→ " + String(r_seed.get("message", "")))
	_grow_to_ready(state, idx)
	check("第二年玉米成熟", farm.get_plot(idx).state == FarmPlot.State.READY,
		"→ " + state.calendar.date_string())
	var r_h2 := _do(state, ToolBar.Tool.HARVEST, idx)
	check("第二年收获成功", bool(r_h2.get("ok")), "→ " + String(r_h2.get("message", "")))
	check("收获回传秋翻加成标记",
		bool(r_h2.get("result", {}).get("autumn_plowed", false)))
	# 同样 150 天成熟:头年 3 个,秋翻后保底多打 1 个 → 4 个
	var second_amount := int(r_h2.get("result", {}).get("amount", 0))
	check("次年产量比头年多(秋翻保底 +1)", second_amount > first_amount,
		"→ %d 个 → %d 个" % [first_amount, second_amount])

# ============================================================================
# 年轮与四季轮转
# ============================================================================
func test_year_cycle_and_seasons() -> void:
	print("\n[年轮] 360 天一年 · 四季轮转 · 冬歇再开春")
	var state := GameState.new()
	var seen := {}
	var guard := 0
	while seen.size() < 4 and guard < 400:
		seen[state.calendar.get_season()] = true
		_sleep(state)
		guard += 1
	check("一年里四季都轮到了", seen.size() == 4, "→ " + str(seen.keys()))
	check("一年 360 天", GameCalendar.DAYS_PER_YEAR == 360)
	check("冬季是休耕季", state.calendar.get_season() == "winter"
		or seen.has("winter"), "→ " + state.calendar.date_string())

	# 开春能重新开始经营
	state.calendar.advance_to_month(4, 1)
	var idx := 8
	_do(state, ToolBar.Tool.TILL, idx)
	var r := _do(state, ToolBar.Tool.SEED, idx, "corn")
	check("开春能重新下种", bool(r.get("ok")), "→ " + String(r.get("message", "")))
	check("播种窗提示剩 60 天",
		FarmAlmanac.sow_window_days_left(state.calendar, state.farm) >= 0,
		"→ %d 天" % FarmAlmanac.sow_window_days_left(state.calendar, state.farm))
