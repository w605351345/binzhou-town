extends RefCounted
class_name ForageSystem

## 四季采集点。物品由 绝对日 + 点 key 决定，同一天读档不会改变。

const FORAGE_PATH := "res://data/forage.json"
static var _points: Array = []
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(FORAGE_PATH, FileAccess.READ)
	if f == null:
		push_error("采集数据不存在: %s" % FORAGE_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_points = Array(parsed.get("points", []))

static func all_points() -> Array:
	_ensure_loaded()
	return _points.duplicate(true)

static func daily_points(map_data: Dictionary, absolute_day: int) -> Array:
	_ensure_loaded()
	var map_id := String(map_data.get("id", ""))
	var calendar := GameCalendar.new()
	calendar.from_absolute_day(absolute_day)
	var season := calendar.get_season()
	var out: Array = []
	for raw in _points:
		var point: Dictionary = raw
		if String(point.get("map_id", "")) != map_id:
			continue
		if not Array(point.get("seasons", [])).has(season):
			continue
		var picked := _pick_item(point, absolute_day)
		if picked.is_empty():
			continue
		out.append({
			"key": String(point.get("key", "")),
			"map_id": map_id,
			"interactable_id": String(point.get("interactable_id", "")),
			"respawn_days": int(point.get("respawn_days", 1)),
			"items": [picked],
			"season": season,
		})
	return out

## 把地图上的一个“采集互动点”解析成当日有效的采集数据 key。
## 同一互动点在不同季节可能对应不同记录(例如河岸芦苇春/秋各一套)。
static func point_key_for(map_data: Dictionary, interactable_id: String,
		calendar: GameCalendar) -> String:
	_ensure_loaded()
	if calendar == null:
		return ""
	var map_id := String(map_data.get("id", ""))
	var season := calendar.get_season()
	for raw in _points:
		var point: Dictionary = raw
		if String(point.get("map_id", "")) != map_id:
			continue
		if String(point.get("interactable_id", "")) != interactable_id:
			continue
		if not Array(point.get("seasons", [])).has(season):
			continue
		if _pick_item(point, calendar.abs_day()).is_empty():
			continue
		return String(point.get("key", ""))
	return ""

static func collect(state: GameState, point_key: String) -> Dictionary:
	_ensure_loaded()
	var point := _point_by_key(point_key)
	if point.is_empty():
		return {"ok": false, "message": "这里没有可采的东西"}
	var seasons: Array = point.get("seasons", [])
	if not seasons.has(state.calendar.get_season()):
		return {"ok": false, "message": "这个时节采不到"}
	if not state.forage.has("collected"):
		state.forage["collected"] = {}
	var collected: Dictionary = state.forage["collected"]
	var today := state.calendar.abs_day()
	var last_day := int(collected.get(point_key, -99999))
	var respawn := int(point.get("respawn_days", 1))
	if last_day >= 0 and today - last_day < respawn:
		return {"ok": false, "message": "还得再等等，这里刚采过"}
	var picked := _pick_item(point, today)
	if picked.is_empty():
		return {"ok": false, "message": "今天什么也没长出来"}
	var item_id := String(picked.get("id", ""))
	var count := int(picked.get("count", 1))
	state.player.inventory[item_id] = int(state.player.inventory.get(item_id, 0)) + count
	collected[point_key] = today
	state.forage["collected"] = collected
	state.forage["last_day"] = today
	QuestSystem.progress(state, "forage", count)
	return {
		"ok": true, "item_id": item_id, "count": count,
		"name": String(picked.get("name", item_id)),
		"message": "采到%s ×%d。" % [picked.get("name", item_id), count],
	}

static func _point_by_key(key: String) -> Dictionary:
	_ensure_loaded()
	for raw in _points:
		if String(raw.get("key", "")) == key:
			return raw
	return {}

static func _pick_item(point: Dictionary, absolute_day: int) -> Dictionary:
	var options: Array = point.get("items", [])
	if options.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absolute_day) * 7919 ^ String(point.get("key", "")).hash()
	var total := 0
	for option in options:
		total += int(option.get("weight", 1))
	var pick := rng.randi_range(1, maxi(1, total))
	var cursor := 0
	var selected: Dictionary = options[0]
	for option in options:
		cursor += int(option.get("weight", 1))
		if pick <= cursor:
			selected = option
			break
	var count := rng.randi_range(int(selected.get("min", 1)), int(selected.get("max", 1)))
	return {
		"id": String(selected.get("id", "")),
		"name": String(ItemDatabase.get_item(String(selected.get("id", ""))).get(
			"name", selected.get("id", ""))),
		"count": count,
	}
