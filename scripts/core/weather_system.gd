extends RefCounted
class_name WeatherSystem

## 西境四季天气:季节权重 + 存档种子 + 绝对日共同决定。
## 同一天读档天气不变；次日天气可提前看，但不额外制造随机失真。

const DEFAULT_TODAY := "sunny"
const DEFAULT_TOMORROW := "cloudy"
const BLIZZARD := "blizzard"
const RAIN := "rain"

const NAMES := {
	"sunny": "晴", "cloudy": "阴", "drizzle": "细雨", "cold_snap": "倒春寒",
	"wind": "大风", "humid": "闷热", "thunderstorm": "雷雨", "rainstorm": "暴雨",
	"frost_morning": "霜晨", "cold_rain": "冷雨", "first_snow": "初雪",
	"clear_cold": "晴冷", "snow": "雪", "blizzard": "暴风雪", "smog": "烟霾",
	"rain": "雨",
}

const SEASON_WEIGHTS := {
	"spring": {"sunny": 30, "cloudy": 20, "drizzle": 25, "cold_snap": 15, "wind": 10},
	"summer": {"sunny": 35, "humid": 20, "thunderstorm": 20, "rainstorm": 15, "cloudy": 10},
	"autumn": {"sunny": 30, "frost_morning": 15, "cloudy": 25, "cold_rain": 20, "first_snow": 10},
	"winter": {"clear_cold": 35, "snow": 30, "blizzard": 15, "smog": 20},
}

var today: String = DEFAULT_TODAY
var tomorrow: String = DEFAULT_TOMORROW
var seed: int = 0

## 次日预报别名:界面与任务统一叫 forecast。
var forecast: String:
	get:
		return tomorrow
	set(value):
		tomorrow = value

func _init(p_today: String = DEFAULT_TODAY, p_tomorrow: String = DEFAULT_TOMORROW,
		p_seed: int = 0) -> void:
	today = p_today
	tomorrow = p_tomorrow
	seed = p_seed

## 按季节 + 种子 + 绝对日抽天气。同参数永远得到同一结果。
static func weather_for_day(calendar: GameCalendar, p_seed: int, day_offset: int = 0) -> String:
	if calendar == null:
		return DEFAULT_TODAY
	var target := GameCalendar.new()
	target.from_absolute_day(calendar.abs_day() + day_offset)
	var weights := weights_for(target.get_season())
	var ids: Array = weights.keys()
	ids.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p_seed) ^ (target.abs_day() * 7919 + 17)
	var pick := rng.randi_range(1, 100)
	var cursor := 0
	for weather_id in ids:
		cursor += int(weights[weather_id])
		if pick <= cursor:
			return String(weather_id)
	return String(ids.back()) if not ids.is_empty() else DEFAULT_TODAY

## 刷新当天与次日预报。roll 是本方法的返回值别名。
func refresh(calendar: GameCalendar, p_seed: int) -> String:
	seed = p_seed
	today = weather_for_day(calendar, seed, 0)
	tomorrow = forecast_for_day(calendar, seed, 0)
	return today

func roll(calendar: GameCalendar, p_seed: int) -> String:
	return refresh(calendar, p_seed)

## 明日预报:按季节准确率决定说真话还是报偏，但同一天读档重复结果一致。
static func forecast_for_day(calendar: GameCalendar, p_seed: int, day_offset: int = 0) -> String:
	var target := GameCalendar.new()
	target.from_absolute_day(calendar.abs_day() + day_offset + 1)
	var actual := weather_for_day(calendar, p_seed, day_offset + 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p_seed) ^ ((target.abs_day() + 1) * 104729 + 97)
	if rng.randf() < forecast_accuracy(target.get_season()):
		return actual
	var weights := weights_for(target.get_season())
	weights.erase(actual)
	var ids: Array = weights.keys()
	ids.sort()
	if ids.is_empty():
		return actual
	var pick := rng.randi_range(1, _weight_total(weights))
	var cursor := 0
	for weather_id in ids:
		cursor += int(weights[weather_id])
		if pick <= cursor:
			return String(weather_id)
	return actual

static func forecast_accuracy(season: String) -> float:
	match season:
		"spring": return 0.72
		"summer": return 0.82
		"autumn": return 0.88
		"winter": return 0.97
	return 0.75

static func _weight_total(weights: Dictionary) -> int:
	var total := 0
	for weather_id in weights.keys():
		total += int(weights[weather_id])
	return total

static func weights_for(season: String) -> Dictionary:
	var raw: Dictionary = SEASON_WEIGHTS.get(season, SEASON_WEIGHTS["spring"])
	return raw.duplicate(true)

static func weather_cn(weather_id: String) -> String:
	return String(NAMES.get(weather_id, "未知"))

static func waters_crops(weather_id: String) -> bool:
	return weather_id in ["drizzle", "thunderstorm", "rainstorm", "cold_rain", RAIN]

static func outdoor_stamina_multiplier(weather_id: String) -> float:
	match weather_id:
		BLIZZARD: return 1.8
		"snow": return 1.35
		"cold_snap": return 1.25
		"clear_cold": return 1.2
		"cold_rain": return 1.15
		"humid": return 1.15
		"smog": return 1.05
	return 1.0

static func is_snow(weather_id: String) -> bool:
	return weather_id in ["snow", BLIZZARD, "first_snow"]

static func hint_for(weather_id: String) -> String:
	match weather_id:
		"drizzle", RAIN, "thunderstorm", "rainstorm", "cold_rain":
			return "作物自动浇水，外出别把种子淋湿"
		BLIZZARD:
			return "暴风雪，户外体力消耗大增，尽量别远行"
		"snow", "first_snow":
			return "雪天，路面湿滑，注意保暖"
		"cold_snap":
			return "倒春寒，已出苗的作物要当心"
		"frost_morning":
			return "霜晨，晚收作物要抓紧"
		"smog":
			return "烟霾，能见度低，壁炉边最舒坦"
		"humid":
			return "闷热，庄稼长得快，人也容易乏"
		"wind":
			return "大风，晾晒的粮食记得收"
		"clear_cold":
			return "晴冷，日头亮但地冻得硬"
	return "适合下地，也适合去镇上走走"

func to_dict() -> Dictionary:
	return {"today": today, "tomorrow": tomorrow, "seed": seed}

static func from_dict(d: Dictionary) -> WeatherSystem:
	return WeatherSystem.new(
		String(d.get("today", DEFAULT_TODAY)),
		String(d.get("tomorrow", DEFAULT_TOMORROW)),
		int(d.get("seed", 0)))
