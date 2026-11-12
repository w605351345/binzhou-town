extends RefCounted
class_name FarmSystem

## 农场系统:管理 3x3 地块集合,执行翻土/浇水/播种/收获闭环。
## 黑龙江设定:一年一熟。春播(4-5月)→夏长(6-8月)→秋收(9-10月)→冬歇(11-2月)。
## 秋霜(10月)后未收作物冻死;早收作物腾茬早,可当年复种一季。

const DEFAULT_PLOT_COUNT := 9

var plots: Array[FarmPlot] = []
var calendar: GameCalendar = null

func _init(p_calendar: GameCalendar = null, plot_count: int = DEFAULT_PLOT_COUNT) -> void:
	calendar = p_calendar if p_calendar != null else GameCalendar.new()
	for i in plot_count:
		plots.append(FarmPlot.new(i))

func get_plot(index: int) -> FarmPlot:
	if index < 0 or index >= plots.size():
		return null
	return plots[index]

## 翻土
func till_plot(index: int) -> bool:
	var p := get_plot(index)
	if p == null:
		return false
	return p.till()

## 浇水
func water_plot(index: int) -> bool:
	var p := get_plot(index)
	if p == null:
		return false
	return p.water(calendar.day_of_year)

## 播种:冬季禁止播种,且须在作物的播种月份窗口内
func plant_crop(index: int, crop_id: String) -> bool:
	var p := get_plot(index)
	if p == null:
		return false
	if calendar.is_winter():
		return false
	return p.plant(crop_id, calendar.get_season(), calendar.get_real_month())

## 秋翻地:秋收后或冬季深翻积肥(黑龙江黑土地保护核心农法)
func autumn_plough_plot(index: int) -> bool:
	var p := get_plot(index)
	if p == null:
		return false
	return p.autumn_plough()

## 是否已秋翻地
func is_autumn_plowed(index: int) -> bool:
	var p := get_plot(index)
	if p == null:
		return false
	return p.autumn_plowed

## 收获
func harvest_plot(index: int) -> Dictionary:
	var p := get_plot(index)
	if p == null:
		return {}
	return p.harvest()

## 每日结算:推进所有地块生长
func advance_day() -> void:
	var month := calendar.get_real_month()
	for p in plots:
		p.advance_day(calendar.day_of_year, month)

## 统计:已播种数 / 可收获数 / 枯死数
func get_stats() -> Dictionary:
	var planted := 0
	var ready := 0
	var dead := 0
	for p in plots:
		if p.crop_id != "":
			planted += 1
		if p.state == FarmPlot.State.READY:
			ready += 1
		if p.state == FarmPlot.State.DEAD:
			dead += 1
	return {"total": plots.size(), "planted": planted, "ready": ready, "dead": dead}

## 当前季节 + 当前月份可播种的作物 id 列表
func sowable_crop_ids() -> Array:
	var out: Array = []
	for c in CropDatabase.sowable_in(calendar.get_season()):
		if c.can_sow_in_month(calendar.get_real_month()):
			out.append(c.id)
	return out

## 当前月份可收获的作物 id 列表
func harvestable_crop_ids() -> Array:
	var out: Array = []
	var month := calendar.get_real_month()
	for c in CropDatabase.all_crops():
		if c.can_harvest_in_month(month):
			out.append(c.id)
	return out

## 早收作物(7-8月,腾茬早可复种)
func early_harvest_crops() -> Array:
	var out: Array = []
	for c in CropDatabase.all_crops():
		if c.is_early_harvest():
			out.append(c.id)
	return out

## 晚收作物(9-10月,紧贴秋霜,压力来源)
func late_harvest_crops() -> Array:
	var out: Array = []
	for c in CropDatabase.all_crops():
		if c.is_late_harvest():
			out.append(c.id)
	return out

func to_dict() -> Dictionary:
	var arr: Array = []
	for p in plots:
		arr.append(p.to_dict())
	return {"plots": arr}

static func from_dict(d: Dictionary, p_calendar: GameCalendar) -> FarmSystem:
	var fs := FarmSystem.new(p_calendar)
	var arr: Array = d.get("plots", [])
	for i in arr.size():
		if i < fs.plots.size():
			fs.plots[i] = FarmPlot.from_dict(arr[i])
	return fs
