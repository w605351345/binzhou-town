extends RefCounted
class_name GuidanceSystem

## 新玩家引导:不依赖任务面板,直接根据农场/交谈/睡觉进度给出下一条可执行动作。
## 目标不是做手把手教程,而是让玩家进游戏 30 秒内知道"现在该按什么、去哪里"。

const TARGET_PLOTS := 3

static func current_step(state: GameState) -> Dictionary:
	if state == null or state.farm == null:
		return _step("回农场看看", "从镇中心南边小路回自家农场。", "打开背包查看种子")
	var farm := state.farm
	var stats := farm.get_stats()
	var planted := int(stats.get("planted", 0))
	var ready := int(stats.get("ready", 0))
	var tilled := _count_state(farm, FarmPlot.State.TILLED)
	var watered := _watered_today(farm, state.calendar.abs_day())
	if ready > 0:
		return _step("收下第一茬庄稼", "靠近成熟地块按 E（或 I）收获。", _farm_summary(stats, tilled, watered))
	if planted == 0:
		if tilled > 0:
			return _step("播下第一包种子", "靠近翻好的地按 E；开局已有玉米种和马铃薯种。",
				_farm_summary(stats, tilled, watered))
		return _step("开垦第一块地", "靠近农舍南边的地块，按 E 翻土。",
			_farm_summary(stats, tilled, watered))
	if planted < TARGET_PLOTS:
		return _step("把春耕铺开", "再翻地播种，凑满 %d 块；E 会自动切换农作动作。" % TARGET_PLOTS,
			_farm_summary(stats, tilled, watered))
	if watered < planted:
		return _step("给庄稼浇透水", "靠近已播种的地按 E；连续两天没水会旱死。",
			_farm_summary(stats, tilled, watered))
	if not bool(state.flags.get("tutorial_talked", false)):
		return _step("去镇上认认人", "从农场南边小路去镇中心，靠近镇民按 E 聊天。",
			_farm_summary(stats, tilled, watered))
	var start_day := int(state.flags.get("run_started_abs_day", state.calendar.abs_day()))
	if state.calendar.abs_day() <= start_day:
		return _step("回木床睡一觉", "回农舍，走到木床旁按 E 或 T。睡觉会推进一天并恢复体力。",
			_farm_summary(stats, tilled, watered))
	var drama_step := _drama_progress_step(state)
	if not drama_step.is_empty():
		return drama_step
	if not bool(state.flags.get("postcard_sent_once", false)):
		return _step("去老邮局寄一封短信",
			"从镇中心进邮局，在柜台按 E。寄信不强制，是农闲时给远方报个平安。",
			_farm_summary(stats, tilled, watered))
	return _step("把日子过起来",
		"照料田地、去镇上卖粮接委托；每天记得回家睡觉。收成会慢慢推进月桂剧场的新幕。",
		_farm_summary(stats, tilled, watered))

## 农事是主线，古戏是长线叙事。只在作物已经攒够解锁条件时把戏台推到主指引，
## 其余时候仍让玩家先完成当天的农活。
static func _drama_progress_step(state: GameState) -> Dictionary:
	var stats := state.farm.get_stats()
	var farm_text := _farm_summary(stats,
		_count_state(state.farm, FarmPlot.State.TILLED),
		_watered_today(state.farm, state.calendar.abs_day()))
	for act in DramaSystem.all_acts():
		var act_id := String(act.get("id", ""))
		if DramaSystem.is_completed(state, act_id):
			continue
		if DramaSystem.is_unlocked(state, act_id):
			return _step("去月桂剧场排下一幕",
				"从镇中心东侧进入月桂剧场，靠近戏台按 E 排练《%s》。" %
					String(act.get("title", "月桂谣")),
				farm_text)
		break
	return {}

static func guide_text(state: GameState) -> String:
	var step := current_step(state)
	# 统计数字留给靠近地块时的上下文卡；常驻引导只说下一步做什么。
	return "%s\n%s" % [step.get("title", ""), step.get("hint", "")]

static func _step(title: String, hint: String, summary: String) -> Dictionary:
	return {"title": title, "hint": hint, "summary": summary}

static func _count_state(farm: FarmSystem, wanted: int) -> int:
	var count := 0
	for plot in farm.plots:
		if plot != null and plot.state == wanted:
			count += 1
	return count

static func _watered_today(farm: FarmSystem, today: int) -> int:
	var count := 0
	for plot in farm.plots:
		if plot != null and plot.crop_id != "" and plot.last_watered_abs_day == today:
			count += 1
	return count

static func _farm_summary(stats: Dictionary, tilled: int, watered: int) -> String:
	return "田地：可翻 %d · 已翻 %d · 已种 %d/%d\n今日浇水 %d · 可收 %d" % [
		int(stats.get("total", 0)) - int(stats.get("planted", 0)) - tilled,
		tilled, int(stats.get("planted", 0)), TARGET_PLOTS, watered,
		int(stats.get("ready", 0)),
	]
