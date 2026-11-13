extends RefCounted
class_name Crop

## 作物数据模型(对应 data/crops.json)
## 黑龙江设定:一年一熟,全部为春播-秋收型,无越冬作物、无秋播作物。
##
## 关键区分(用户 D14 要求):
##   · 春播 —— 4月下旬至5月上旬下种,夏季生长,秋收
##   · 秋收 —— 分早收(7-8月,腾茬早可复种) 与 晚收(9-10月,抢在秋霜前)
##   · 越冬 —— 收获后按 storage 方式储藏(窖藏 / 晾晒),决定冬季加工玩法

var id: String = ""
var name: String = ""
var en_name: String = ""
var category: String = "grain"
var sowing_season: String = "spring"
var harvest_season: String = "autumn"
var plant_days: Array = []
var growth_days: Array = [10, 14]
var yield_min: int = 1
var yield_max: int = 3
var buy_price: int = 10
var sell_price: int = 20
var seed_price: int = 20
var regrow: int = 0
var water_per_day: int = 1
var icon: String = ""
var origin: String = ""
var flavor: String = ""
var mvp: bool = false

## 播种月份窗口(真实月份 1-12)
var plant_window: Array = []
## 收获月份窗口(真实月份 1-12)
var harvest_window: Array = []
## 越冬储藏方式:"窖藏" / "晾晒"
var storage: String = "窖藏"
var storage_note: String = ""
## 是否为早收作物(7-8月收获,腾茬早)
var early_harvest: bool = false
## 是否为晚收作物(10月收获,紧贴秋霜)
var late_harvest: bool = false

static func from_dict(d: Dictionary) -> Crop:
	var c := Crop.new()
	c.id = String(d.get("id", ""))
	c.name = String(d.get("name", ""))
	c.en_name = String(d.get("en_name", ""))
	c.category = String(d.get("category", "grain"))
	c.sowing_season = String(d.get("sowing_season", "spring"))
	c.harvest_season = String(d.get("harvest_season", "autumn"))
	c.plant_days = d.get("plant_days", [])
	c.growth_days = d.get("growth_days", [10, 14])
	c.yield_min = int(d.get("yield_min", 1))
	c.yield_max = int(d.get("yield_max", 3))
	c.buy_price = int(d.get("buy_price", 10))
	c.sell_price = int(d.get("sell_price", 20))
	c.seed_price = int(d.get("seed_price", 20))
	c.regrow = int(d.get("regrow", 0))
	c.water_per_day = int(d.get("water_per_day", 1))
	c.icon = String(d.get("icon", ""))
	c.origin = String(d.get("origin", ""))
	c.flavor = String(d.get("flavor", ""))
	c.mvp = bool(d.get("mvp", false))
	c.plant_window = d.get("plant_window", [])
	c.harvest_window = d.get("harvest_window", [])
	c.storage = String(d.get("storage", "窖藏"))
	c.storage_note = String(d.get("storage_note", ""))
	c.early_harvest = bool(d.get("early_harvest", false))
	c.late_harvest = bool(d.get("late_harvest", false))
	return c

## 是否可以在指定季节播种
func can_sow_in(season: String) -> bool:
	if plant_days.is_empty():
		return false
	return plant_days.has(season)

## 是否可在指定真实月份播种(黑龙江农时:4-5月,plant_window 为连续区间 [起, 止])
func can_sow_in_month(month: int) -> bool:
	if plant_window.is_empty():
		return true
	if plant_window.size() >= 2:
		var lo := int(plant_window[0])
		var hi := int(plant_window[1])
		return month >= lo and month <= hi
	return int(plant_window[0]) == month

## 是否可在指定真实月份收获(harvest_window 为连续区间 [起始月, 结束月])
func can_harvest_in_month(month: int) -> bool:
	if harvest_window.is_empty():
		return true
	if harvest_window.size() >= 2:
		var lo := int(harvest_window[0])
		var hi := int(harvest_window[1])
		return month >= lo and month <= hi
	return int(harvest_window[0]) == month

## 是否为秋收作物(收获季为 autumn)
func is_autumn_harvest() -> bool:
	return harvest_season == "autumn"

## 早收/晚收分类
func is_early_harvest() -> bool:
	return early_harvest

func is_late_harvest() -> bool:
	return late_harvest

## 生长阶段:0=种下 1=出苗 2=生长 3=成熟
func growth_stage(days_grown: float) -> int:
	if days_grown <= 0.0:
		return 0
	var lo := float(growth_days[0])
	var hi := float(growth_days[1])
	if days_grown >= lo:
		return 3
	if days_grown >= lo * 0.45:
		return 2
	return 1

func is_ready(days_grown: float) -> bool:
	return days_grown >= float(growth_days[0])

## 秋翻地产量加成(黑龙江黑土地保护:秋翻杀虫保墒,增产)
const AUTUMN_PLOUGH_BONUS := 0.15

## 收获产量:秋翻地有加成
func roll_yield(days_grown: float, autumn_plowed: bool = false) -> int:
	var lo := float(growth_days[0])
	var hi := float(growth_days[1])
	var ratio := 0.0
	if hi > lo:
		ratio = clampf((days_grown - lo) / (hi - lo), 0.0, 1.0)
	var base := yield_min + int(round((yield_max - yield_min) * ratio))
	if autumn_plowed:
		# 秋翻必须看得见收益:低产作物(如玉米最低产 3 个)按 15% 取整会被抹平成同一个数,
		# 玩家翻了地却没多打粮,黑土地保护这条核心农法就白设计了。所以保底多打 1 个。
		base = maxi(base + 1, int(round(float(base) * (1.0 + AUTUMN_PLOUGH_BONUS))))
	return base

## 收获后的越冬储藏信息
func get_storage_info() -> Dictionary:
	return {
		"method": storage,
		"note": storage_note,
		"keeps_through_winter": true,
	}

func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "category": category,
		"sowing_season": sowing_season, "harvest_season": harvest_season,
		"plant_days": plant_days, "growth_days": growth_days,
		"yield_min": yield_min, "yield_max": yield_max,
		"buy_price": buy_price, "sell_price": sell_price, "seed_price": seed_price,
		"water_per_day": water_per_day, "icon": icon,
		"plant_window": plant_window, "harvest_window": harvest_window,
		"storage": storage, "early_harvest": early_harvest, "late_harvest": late_harvest,
	}
