extends RefCounted
class_name FestivalSystem

const FESTIVALS_PATH := "res://data/festivals.json"
static var _festivals: Array = []
static var _by_id: Dictionary = {}
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(FESTIVALS_PATH, FileAccess.READ)
	if f == null:
		push_error("节日数据不存在: %s" % FESTIVALS_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_festivals = Array(parsed.get("festivals", []))
		for festival in _festivals:
			_by_id[String(festival.get("id", ""))] = festival

static func all_festivals() -> Array:
	_ensure_loaded()
	return _festivals.duplicate(true)

static func get_festival(festival_id: String) -> Dictionary:
	_ensure_loaded()
	var festival: Variant = _by_id.get(festival_id, {})
	return festival.duplicate(true) if festival is Dictionary else {}

static func is_today(calendar: GameCalendar) -> Dictionary:
	_ensure_loaded()
	if calendar == null:
		return {}
	for festival in _festivals:
		if int(festival.get("month", 0)) == calendar.get_real_month() \
				and int(festival.get("day", 0)) == calendar.get_day_of_month():
			return festival.duplicate(true)
	return {}

static func available_activities(festival_id: String) -> Array:
	var festival := get_festival(festival_id)
	return Array(festival.get("activities", [])).duplicate(true)
