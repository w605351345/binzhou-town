extends RefCounted
class_name EventSystem

## 好感事件目录与触发判定。事件台词仍交给 DialogueRunner。

const EVENTS_PATH := "res://data/events.json"

static var _events: Array = []
static var _by_id: Dictionary = {}
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(EVENTS_PATH, FileAccess.READ)
	if f == null:
		push_error("事件数据不存在: %s" % EVENTS_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("事件数据不是合法 JSON: %s" % EVENTS_PATH)
		return
	for raw in parsed.get("events", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = raw
		var event_id := String(event.get("id", ""))
		if event_id == "":
			continue
		_events.append(event)
		_by_id[event_id] = event

static func all_events() -> Array:
	_ensure_loaded()
	var out: Array = []
	for event in _events:
		out.append(event.duplicate(true))
	return out

static func get_event(event_id: String) -> Dictionary:
	_ensure_loaded()
	var event: Variant = _by_id.get(event_id, {})
	return event.duplicate(true) if event is Dictionary else {}

static func active_event_id(state: GameState) -> String:
	if state == null:
		return ""
	return String(state.events.get("active", ""))

static func available_event(state: GameState, location_id: String,
		calendar: GameCalendar, clock: GameClock, weather: Variant = null) -> Dictionary:
	_ensure_loaded()
	if active_event_id(state) != "":
		return {}
	var best: Dictionary = {}
	var best_priority := -999999
	for event in _events:
		var event_id := String(event.get("id", ""))
		if not can_trigger(state, event_id, location_id, calendar, clock, weather):
			continue
		var priority := int(event.get("priority", 0))
		if priority > best_priority:
			best = event
			best_priority = priority
	return best.duplicate(true) if not best.is_empty() else {}

static func can_trigger(state: GameState, event_id: String, location_id: String,
		calendar: GameCalendar, clock: GameClock, weather: Variant = null) -> bool:
	_ensure_loaded()
	var event := get_event(event_id)
	if event.is_empty() or state == null:
		return false
	if active_event_id(state) != "":
		return false
	if _done(state).has(event_id):
		return false
	if String(event.get("location_id", "")) != location_id:
		return false
	var npc_id := String(event.get("npc_id", ""))
	if state.npc_affection(npc_id) < int(event.get("affection_min", 0)):
		return false
	if calendar != null:
		var seasons: Array = event.get("seasons", [])
		if not seasons.is_empty() and not _strings(seasons).has(calendar.get_season()):
			return false
		var weekdays: Array = event.get("weekdays", [])
		if not weekdays.is_empty() and not _ints(weekdays).has(calendar.abs_day() % 7):
			return false
	if clock != null:
		if clock.minute_of_day < _minute(String(event.get("time_from", "00:00"))):
			return false
		if clock.minute_of_day >= _minute(String(event.get("time_to", "24:00"))):
			return false
	if not _weather_ok(event.get("weather", []), weather):
		return false
	for req in _strings(event.get("requires_events", [])):
		if not _done(state).has(req):
			return false
		var done_days: Dictionary = state.events.get("done_days", {})
		if done_days.has(req):
			var elapsed := calendar.abs_day() - int(done_days[req]) if calendar != null else 0
			if elapsed < int(event.get("days_since_event_min", 0)):
				return false
			if event.has("days_since_event_max") \
					and elapsed > int(event.get("days_since_event_max", 99999)):
				return false
	var required_flags: Dictionary = event.get("requires_flags", {})
	for flag in required_flags.keys():
		if typeof(state.flags.get(flag, false)) != typeof(required_flags[flag]):
			return false
		if state.flags.get(flag, null) != required_flags[flag]:
			return false
	return true

## 开始事件只负责锁定当前事件；条件在 available_event/can_trigger 已经判定过。
static func start_event(state: GameState, event_id: String) -> Dictionary:
	var event := get_event(event_id)
	if event.is_empty() or state == null:
		return {}
	state.events["active"] = event_id
	return event

static func finish_event(state: GameState, event_id: String) -> void:
	if state == null or event_id == "":
		return
	var event := get_event(event_id)
	if event.is_empty():
		return
	var done := _done(state)
	if not done.has(event_id):
		done.append(event_id)
	state.events["done"] = done
	if not state.events.has("done_days"):
		state.events["done_days"] = {}
	state.events["done_days"][event_id] = state.calendar.abs_day()
	if active_event_id(state) == event_id:
		state.events["active"] = ""
	RelationshipSystem.mark_event_done(state, String(event.get("npc_id", "")), event_id)
	QuestSystem.progress(state, "event", 1)

static func _done(state: GameState) -> Array:
	var done: Variant = state.events.get("done", [])
	return done if done is Array else []

static func _weather_ok(wanted: Variant, weather: Variant) -> bool:
	var ids := _strings(wanted)
	if ids.is_empty():
		return true
	var actual := _weather_id(weather)
	for item in ids:
		if item == actual:
			return true
		if item == "rain" and WeatherSystem.waters_crops(actual):
			return true
		if item == "snow" and WeatherSystem.is_snow(actual):
			return true
		if item == "storm" and actual in [WeatherSystem.BLIZZARD, "thunderstorm", "rainstorm"]:
			return true
	return false

static func _weather_id(weather: Variant) -> String:
	if weather is String:
		return String(weather)
	if weather is Dictionary:
		return String(weather.get("today", "sunny"))
	if weather is WeatherSystem:
		return weather.today
	return "sunny"

static func _strings(value: Variant) -> Array:
	var out: Array = []
	if value is Array:
		for item in value:
			out.append(String(item))
	elif value != null:
		out.append(String(value))
	return out

static func _ints(value: Variant) -> Array:
	var out: Array = []
	if value is Array:
		for item in value:
			out.append(int(item))
	return out

static func _minute(value: String) -> int:
	var parts := value.split(":")
	if parts.size() < 2:
		return 0
	return int(parts[0]) * 60 + int(parts[1])
