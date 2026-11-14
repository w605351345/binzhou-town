extends RefCounted
class_name NpcScheduleSystem

## 把 NPC 数据中的时段/季节/天气/日期变体解析成当前状态。
## 优先级：显式 priority > 天气特殊 > 季节特殊 > 日期变体 > 通用日程。

static func resolve(npc_data: Dictionary, calendar: GameCalendar,
		clock: GameClock, weather: Variant = null) -> Dictionary:
	if npc_data.is_empty():
		return _fallback({})
	if clock == null:
		clock = GameClock.new()
	var season := calendar.get_season() if calendar != null else "spring"
	var day := calendar.day_of_year if calendar != null else 0
	var weather_id := _weather_id(weather)

	var best: Dictionary = {}
	var best_score := -1
	for raw in npc_data.get("schedules", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw
		if not _matches(entry, season, day, clock.minute_of_day, weather_id):
			continue
		var score := _score(entry)
		if score > best_score:
			best = entry
			best_score = score
	if best.is_empty():
		return _fallback(npc_data)

	var pos_raw: Array = best.get("position", [0, 0])
	return {
		"location_id": String(best.get("location_id", npc_data.get("home_location", ""))),
		"position": Vector2(float(pos_raw[0]), float(pos_raw[1])),
		"activity": String(best.get("activity", "")),
		"available": bool(best.get("available", true)),
	}

static func _fallback(npc_data: Dictionary) -> Dictionary:
	var pos_raw: Array = npc_data.get("home_position", [0, 0])
	return {
		"location_id": String(npc_data.get("home_location", "")),
		"position": Vector2(float(pos_raw[0]), float(pos_raw[1])),
		"activity": "在家休息",
		"available": false,
	}

static func _matches(entry: Dictionary, season: String, day: int,
		minute: int, weather_id: String) -> bool:
	if minute < _minute(String(entry.get("time_from", "00:00"))):
		return false
	if minute >= _minute(String(entry.get("time_to", "24:00"))):
		return false
	if entry.has("day_modulo"):
		var mod := maxi(1, int(entry.get("day_modulo", 1)))
		if day % mod != int(entry.get("day_remainder", 0)):
			return false
	if entry.has("seasons") and not _as_strings(entry.get("seasons", [])).has(season):
		return false
	if entry.has("weather") and not _weather_matches(entry.get("weather", []), weather_id):
		return false
	return true

static func _score(entry: Dictionary) -> int:
	var score := int(entry.get("priority", 0)) * 1000
	if entry.has("weather"):
		score += 300
	if entry.has("seasons"):
		score += 120
	if entry.has("day_modulo"):
		score += 30
	return score

static func _weather_matches(wanted: Variant, actual: String) -> bool:
	if actual == "":
		return false
	for item in _as_strings(wanted):
		if item == actual:
			return true
		match item:
			"rain":
				if WeatherSystem.waters_crops(actual):
					return true
			"snow":
				if WeatherSystem.is_snow(actual):
					return true
			"storm":
				if actual in [WeatherSystem.BLIZZARD, "thunderstorm", "rainstorm"]:
					return true
			"sunny":
				if actual in ["sunny", "clear_cold", "frost_morning"]:
					return true
	return false

static func _weather_id(weather: Variant) -> String:
	if weather == null:
		return WeatherSystem.DEFAULT_TODAY
	if weather is String:
		return String(weather)
	if weather is Dictionary:
		return String(weather.get("today", WeatherSystem.DEFAULT_TODAY))
	if weather is WeatherSystem:
		return weather.today
	return WeatherSystem.DEFAULT_TODAY

static func _as_strings(value: Variant) -> Array:
	if value is Array:
		var out: Array = []
		for item in value:
			out.append(String(item))
		return out
	if value == null:
		return []
	return [String(value)]

static func _minute(hhmm: String) -> int:
	var parts := hhmm.split(":")
	if parts.size() < 2:
		return 0
	return int(parts[0]) * 60 + int(parts[1])
