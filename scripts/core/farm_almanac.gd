extends RefCounted
class_name FarmAlmanac

## 农时播报器:把"几月几号、地里啥样、还剩几天"翻译成玩家一眼看懂的提示。
##
## Week 3 收尾件「农时提示 UI」的核心逻辑层:
##   · 播种窗高亮 —— 今年还剩几天能下种(春播 4-5 月,7 月抢茬复种秋菜)
##   · 秋霜倒计时 —— 晚收作物还有几天会被冻死在地里
##   · 地块倒计时 —— 哪块地几天后熟、几天后必须割
##
## 黑龙江农时的三条硬线:
##   1. 春播窗口只有 4-5 月,5 月底封窗,错过当年绝收
##   2. 7 月早收腾茬可复种一茬秋菜 —— 一年一熟大原则下的唯一例外
##   3. 收获窗口末月一过,晚收作物就冻死在地里,颗粒无收
##
## 纯逻辑,不碰节点,便于 headless 自测。

## 秋霜月(与 FarmPlot.FROST_MONTH 保持一致)
const FROST_MONTH := 10
## 春播窗口末月(黑龙江:4-5 月,5 月底封窗)
const LAST_SOW_MONTH := 5
## 进入这个天数范围就开始提醒抢收
const FROST_WARN_DAYS := 15

# --- 倒计时 ---

## 距秋霜(10月1日)还有几天;负数 = 霜期已过
static func days_until_frost(calendar: GameCalendar) -> int:
	if calendar == null:
		return -1
	return (FROST_MONTH - 1) * GameCalendar.DAYS_PER_MONTH - calendar.day_of_year

## 距春播窗口关闭(5月30日)还有几天;负数 = 已错过
static func days_until_sow_end(calendar: GameCalendar) -> int:
	if calendar == null:
		return -1
	return LAST_SOW_MONTH * GameCalendar.DAYS_PER_MONTH - 1 - calendar.day_of_year

## 某作物的播种截止日(播种窗口末月最后一天)的年内日序
static func sow_deadline_doy(crop: Crop) -> int:
	if crop == null or crop.plant_window.is_empty():
		return -1
	var hi := int(crop.plant_window[0])
	if crop.plant_window.size() >= 2:
		hi = int(crop.plant_window[1])
	return hi * GameCalendar.DAYS_PER_MONTH - 1

## 某作物的最晚收获日(收获窗口末月最后一天)的年内日序
static func harvest_deadline_doy(crop: Crop) -> int:
	if crop == null or crop.harvest_window.is_empty():
		return -1
	var hi := int(crop.harvest_window[0])
	if crop.harvest_window.size() >= 2:
		hi = int(crop.harvest_window[1])
	return hi * GameCalendar.DAYS_PER_MONTH - 1

## 地块距离成熟还有几天;已熟 0,地里没作物 -1
static func days_until_ready(plot: FarmPlot) -> int:
	if plot == null or plot.crop_id == "":
		return -1
	if plot.state == FarmPlot.State.READY:
		return 0
	var crop := CropDatabase.get_crop(plot.crop_id)
	if crop == null:
		return -1
	var lo := 0.0
	if crop.growth_days.size() > 0:
		lo = float(crop.growth_days[0])
	return maxi(0, int(ceil(lo - plot.days_grown)))

## 地块距离最晚收获日还有几天;地里没作物 -1,已过则为负数
static func days_until_harvest_deadline(plot: FarmPlot, calendar: GameCalendar) -> int:
	if plot == null or plot.crop_id == "" or calendar == null:
		return -1
	var crop := CropDatabase.get_crop(plot.crop_id)
	if crop == null:
		return -1
	return harvest_deadline_doy(crop) - calendar.day_of_year

## 当前可播种窗口还剩几天(按实际可播作物算:春播窗口或 7 月抢茬复种)。
## 没有可播种作物返回 -1。
static func sow_window_days_left(calendar: GameCalendar, farm: FarmSystem = null) -> int:
	if calendar == null or calendar.is_winter():
		return -1
	var crops := _sowable_crops(calendar, farm)
	if crops.is_empty():
		return -1
	var deadline := -1
	for c in crops:
		deadline = maxi(deadline, sow_deadline_doy(c))
	return deadline - calendar.day_of_year

# --- 文案 ---

## 播种提示:冬歇 / 可播种(还剩几天) / 抢茬复种 / 已过播种窗
static func sow_tip(calendar: GameCalendar, farm: FarmSystem = null) -> String:
	if calendar == null:
		return ""
	if calendar.is_winter():
		return "【冬歇】地里歇着呢 · 可秋翻地积肥 · R 键深翻"
	var crops := _sowable_crops(calendar, farm)
	if crops.is_empty():
		return "【已过播种窗】%d月种不上了,等明年春" % calendar.get_real_month()
	var names: Array = []
	var deadline := -1
	for c in crops:
		names.append(c.name)
		deadline = maxi(deadline, sow_deadline_doy(c))
	var is_spring := calendar.get_season() == "spring"
	var tag := "【可播种】" if is_spring else "【抢茬复种】"
	var window_cn := "播种窗" if is_spring else "复种窗"
	var left := deadline - calendar.day_of_year
	return "%s%s · %s还剩 %d 天(最晚 %s 下种)" % [
		tag, ", ".join(names), window_cn, left, _doy_cn(deadline)]

## 秋霜倒计时提示
static func frost_tip(calendar: GameCalendar, farm: FarmSystem = null) -> String:
	if calendar == null:
		return ""
	var left := days_until_frost(calendar)
	if left > 0:
		return "秋霜还有 %d 天(10月1日霜降),晚收的别拖" % left
	var pending := _late_harvest_pending(farm)
	if pending > 0:
		return "⚠ 秋霜到了,还有 %d 块晚收作物没割,10月底前割完" % pending
	return "秋霜已过,地里该收的都收了"

## 顶部完整提示:播种线 + 霜冻线,一句话讲清"现在该干嘛"
static func full_tip(calendar: GameCalendar, farm: FarmSystem = null) -> String:
	var parts: Array = []
	var sow := sow_tip(calendar, farm)
	if sow != "":
		parts.append(sow)
	var frost := frost_tip(calendar, farm)
	if frost != "":
		parts.append(frost)
	return " · ".join(parts)

## 地块说明(一句话,给消息栏/悬停用)
static func plot_tag(plot: FarmPlot, calendar: GameCalendar = null) -> String:
	if plot == null:
		return ""
	var parts: Array = []
	var crop := CropDatabase.get_crop(plot.crop_id)
	var crop_name := crop.name if crop != null else "庄稼"
	match plot.state:
		FarmPlot.State.PLANTED, FarmPlot.State.GROWING:
			var left := days_until_ready(plot)
			if left > 0:
				parts.append("%s · 还 %d 天" % [crop_name, left])
			else:
				parts.append("%s · 快熟了" % crop_name)
		FarmPlot.State.READY:
			parts.append("%s · 可收获啦" % crop_name)
		FarmPlot.State.DEAD:
			var reason := plot.dead_reason if plot.dead_reason != "" else "不明"
			parts.append("枯死 · %s · J 翻土清茬" % reason)
		FarmPlot.State.FALLOW:
			parts.append("休耕")
		FarmPlot.State.TILLED:
			parts.append("已翻土")
		FarmPlot.State.UNTILLED:
			parts.append("荒地")
	# 霜冻警告:进入最晚收获日前的最后一段日子必须提醒抢收
	var dl := days_until_harvest_deadline(plot, calendar)
	if dl >= 0 and dl <= FROST_WARN_DAYS and plot.state != FarmPlot.State.DEAD:
		parts.append("⚠ %d 天内必割" % dl)
	# 秋翻地的增产加成必须让玩家看见
	if plot.autumn_plowed:
		parts.append("秋翻 +15%")
	return " · ".join(parts)

## 地块角标(画在地块上的短标签)
static func plot_badge(plot: FarmPlot, calendar: GameCalendar = null) -> String:
	if plot == null:
		return ""
	var parts: Array = []
	match plot.state:
		FarmPlot.State.PLANTED, FarmPlot.State.GROWING:
			var left := days_until_ready(plot)
			if left > 0:
				parts.append("还%d天" % left)
		FarmPlot.State.READY:
			parts.append("可收获")
		FarmPlot.State.DEAD:
			parts.append("枯死")
	var dl := days_until_harvest_deadline(plot, calendar)
	if dl >= 0 and dl <= FROST_WARN_DAYS and plot.state != FarmPlot.State.DEAD:
		parts.append("⚠%d天" % dl)
	if plot.autumn_plowed:
		parts.append("+15%")
	return " ".join(parts)

# --- 内部 ---

## 当前月份可播种的作物(优先用农场的口径,两者不一致时按日历重算)
static func _sowable_crops(calendar: GameCalendar, farm: FarmSystem) -> Array:
	if farm != null and farm.calendar != null and farm.calendar.day_of_year == calendar.day_of_year:
		var from_farm: Array = []
		for cid in farm.sowable_crop_ids():
			var c := CropDatabase.get_crop(String(cid))
			if c != null:
				from_farm.append(c)
		return from_farm
	var out: Array = []
	for c in CropDatabase.all_crops():
		if c.can_sow_in(calendar.get_season()) and c.can_sow_in_month(calendar.get_real_month()):
			out.append(c)
	return out

## 地里还没割的晚收作物块数
static func _late_harvest_pending(farm: FarmSystem) -> int:
	if farm == null:
		return 0
	var count := 0
	for p in farm.plots:
		if p.crop_id == "" or p.state == FarmPlot.State.DEAD:
			continue
		var crop := CropDatabase.get_crop(p.crop_id)
		if crop != null and crop.is_late_harvest():
			count += 1
	return count

## 年内日序 → 中文日期
static func _doy_cn(doy: int) -> String:
	if doy < 0:
		return "—"
	var month := int(floor(float(doy) / GameCalendar.DAYS_PER_MONTH)) + 1
	var day := doy % GameCalendar.DAYS_PER_MONTH + 1
	return "%d月%d日" % [month, day]
