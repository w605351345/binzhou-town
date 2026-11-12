extends RefCounted
class_name GameCalendar

## 时间与季节系统(黑龙江真实物候)
##
## 寒温带大陆性气候,一年一熟。按真实月份划分:
##   冬(11-3月,5个月)→ 春(4-5月)→ 夏(6-8月)→ 秋(9-10月)
## 冬季是最长的季节 —— 这正是"漫长休耕"的设计支点:
## 冬季不能播种,但可加工、腌制、熏制、走亲戚、做年货。
##
## 年 = 360 天(12 月 × 30 天),便于与节气/农时对齐。

const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12
const DAYS_PER_YEAR := DAYS_PER_MONTH * MONTHS_PER_YEAR  # 360

## 真实月份 → 季节(索引 0=1月)
const MONTH_SEASON: Array = [
	"winter", "winter", "winter",   # 1-3月
	"spring", "spring",             # 4-5月  播种期
	"summer", "summer", "summer",   # 6-8月  生长期
	"autumn", "autumn",             # 9-10月 收割期
	"winter", "winter",             # 11-12月
]

## 各季起始日(day_of_year)
const SEASON_START: Dictionary = {
	"winter": 0, "spring": 90, "summer": 150, "autumn": 240,
}
## 各季长度(天)
const SEASON_LENGTH: Dictionary = {
	"winter": 150, "spring": 60, "summer": 90, "autumn": 60,
}

## 现实秒 → 游戏日 比例:MVP 每 12 现实分钟 = 1 游戏日
const REAL_SECONDS_PER_GAME_DAY := 60.0 * 12.0

var year: int = 1
var day_of_year: int = 0   # 0-359

func get_season() -> String:
	return MONTH_SEASON[get_month_index()]

## 真实月份(1-12)
func get_real_month() -> int:
	return int(floor(float(day_of_year) / DAYS_PER_MONTH)) + 1

## 真实月份索引(0-11)
func get_month_index() -> int:
	return int(floor(float(day_of_year) / DAYS_PER_MONTH)) % MONTHS_PER_YEAR

func get_day_of_month() -> int:
	return day_of_year % DAYS_PER_MONTH + 1

## 距当前季结束还有几天
func get_days_left_in_season() -> int:
	var s := get_season()
	var start: int = SEASON_START[s]
	var length: int = SEASON_LENGTH[s]
	# 冬季从 11 月开始到次年 3 月底,跨年,需特殊处理
	if s == "winter":
		var month := get_real_month()
		if month >= 11:
			return (12 - month) * DAYS_PER_MONTH + 3 * DAYS_PER_MONTH - get_day_of_month() + 1
		return (3 * DAYS_PER_MONTH) - day_of_year
	return start + length - day_of_year

## 冬季 = 休耕季,禁止播种
func is_winter() -> bool:
	return get_season() == "winter"

## 播种季:仅 4-5 月(真实农时)
func is_sowing_season() -> bool:
	return get_season() == "spring"

## 收割季:9-10 月(秋收);夏末 8 月可收早熟作物
func is_harvest_season() -> bool:
	var s := get_season()
	return s == "autumn" or s == "summer"

## 春季剩余播种窗口是否还够 —— 过了 5 月底再种就来不及秋收了
func sowing_window_open() -> bool:
	return get_season() == "spring" and get_real_month() <= 5

## 季节中文名
static func season_cn(season: String) -> String:
	match season:
		"spring": return "春"
		"summer": return "夏"
		"autumn": return "秋"
		"winter": return "冬"
	return season

## 季节描述(黑龙江真实物候)
static func season_desc(season: String) -> String:
	match season:
		"spring":
			return "春 · 惊蛰开河，地化冻，正是下种的时候"
		"summer":
			return "夏 · 白昼漫长，日照足，庄稼疯长"
		"autumn":
			return "秋 · 霜降收秋，场院打粮，囤菜备冬"
		"winter":
			return "冬 · 漫长休耕，火炕上守岁，庄稼在土里歇着"
	return ""

## 推进一天
func advance_day() -> void:
	day_of_year += 1
	if day_of_year >= DAYS_PER_YEAR:
		day_of_year = 0
		year += 1

## 调试用:跳到指定季节的第 N 天
func advance_to_season(season: String, day_in_season: int = 1) -> void:
	var start: int = SEASON_START.get(season, 0)
	if season == "winter":
		# 冬季从 11 月 1 日起算(当年的 11 月)
		start = 10 * DAYS_PER_MONTH
	day_of_year = (start + clampi(day_in_season - 1, 0, SEASON_LENGTH.get(season, 90) - 1)) % DAYS_PER_YEAR

## 调试用:跳到指定真实月份的第 N 天
func advance_to_month(month: int, day: int = 1) -> void:
	day_of_year = ((month - 1) * DAYS_PER_MONTH + clampi(day - 1, 0, DAYS_PER_MONTH - 1)) % DAYS_PER_YEAR

func date_string() -> String:
	return "第%d年 %d月%d日(%s)" % [year, get_real_month(), get_day_of_month(), season_cn(get_season())]

func to_dict() -> Dictionary:
	return {"year": year, "day_of_year": day_of_year}

static func from_dict(d: Dictionary) -> GameCalendar:
	var c := GameCalendar.new()
	c.year = int(d.get("year", 1))
	c.day_of_year = int(d.get("day_of_year", 0))
	return c
