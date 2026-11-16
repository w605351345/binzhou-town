extends RefCounted
class_name GameCalendar

## 时间与季节系统(麦溪镇真实物候)
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
## 新游戏从春耕第一天开始:4 月 1 日。旧版从 1 月 1 日开局,
## 玩家一进游戏就是漫长冬歇,既不能播种也看不到核心循环。
const START_DAY_OF_YEAR := 3 * DAYS_PER_MONTH  # 90 = 4 月 1 日

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
var day_of_year: int = START_DAY_OF_YEAR   # 0-359

## 绝对日:从第 1 年 1 月 1 日算起,永不回绕。
## 浇水、事件冷却、采集刷新等时间差必须用它,不能再用 day_of_year。
var absolute_day: int:
	get:
		return (year - 1) * DAYS_PER_YEAR + day_of_year
	set(value):
		from_absolute_day(value)

func abs_day() -> int:
	return absolute_day

func from_absolute_day(value: int) -> void:
	var safe := maxi(0, value)
	year = int(float(safe) / float(DAYS_PER_YEAR)) + 1
	day_of_year = safe % DAYS_PER_YEAR

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

## 当前是本赛季第几天(从 1 开始)
func get_season_day() -> int:
	match get_season():
		"spring":
			return day_of_year - SEASON_START["spring"] + 1
		"summer":
			return day_of_year - SEASON_START["summer"] + 1
		"autumn":
			return day_of_year - SEASON_START["autumn"] + 1
		_:
			# 冬季跨年:11-12 月接在 1-3 月之前
			if day_of_year < 3 * DAYS_PER_MONTH:
				return 2 * DAYS_PER_MONTH + day_of_year + 1
			return day_of_year - 10 * DAYS_PER_MONTH + 1

## 本赛季总天数
func get_season_length() -> int:
	return int(SEASON_LENGTH.get(get_season(), 90))

## 距当前季结束还有几天(含今天)
func get_days_left_in_season() -> int:
	return maxi(0, get_season_length() - get_season_day() + 1)

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

## 季节描述(麦溪镇真实物候)
static func season_desc(season: String) -> String:
	match season:
		"spring":
			return "春 · 惊蛰开河，地化冻，正是下种的时候"
		"summer":
			return "夏 · 白昼漫长，日照足，庄稼疯长"
		"autumn":
			return "秋 · 霜降收秋，场院打粮，囤菜备冬"
		"winter":
			return "冬 · 雪落农庄，壁炉边歇口气，为来年留一块好地"
	return ""

## 推进一天
func advance_day() -> void:
	from_absolute_day(abs_day() + 1)

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

## HUD 用的稳定日期格式:季节第几天与真实月日同时出现,避免"1月1日(冬)"和
## "初霜 270 天"这种互相打架的文案。
func date_short() -> String:
	return "第%d年 · %s季 · 第%d天" % [year, season_cn(get_season()), get_season_day()]

func date_detail() -> String:
	return "%d月%d日 · 第%d/%d天" % [get_real_month(), get_day_of_month(),
		get_season_day(), get_season_length()]

func to_dict() -> Dictionary:
	return {"year": year, "day_of_year": day_of_year, "absolute_day": abs_day()}

static func from_dict(d: Dictionary) -> GameCalendar:
	var c := GameCalendar.new()
	if d.has("absolute_day"):
		c.from_absolute_day(int(d.get("absolute_day", 0)))
	else:
		c.year = int(d.get("year", 1))
		c.day_of_year = int(d.get("day_of_year", 0))
	return c
