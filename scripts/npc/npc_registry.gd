extends RefCounted
class_name NpcRegistry

## data/npcs.json 的唯一读取入口。场景层不再按 id 写 if/else。

const NPCS_PATH := "res://data/npcs.json"

static var _npcs: Array = []
static var _by_id: Dictionary = {}
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(NPCS_PATH):
		push_error("NPC 数据不存在: %s" % NPCS_PATH)
		return
	var f := FileAccess.open(NPCS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("NPC 数据不是合法 JSON: %s" % NPCS_PATH)
		return
	for raw in parsed.get("npcs", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = raw
		var npc_id := String(data.get("id", ""))
		if npc_id == "":
			continue
		_npcs.append(data)
		_by_id[npc_id] = data

static func get_npc(id: String) -> Dictionary:
	_ensure_loaded()
	var data: Variant = _by_id.get(id, {})
	return data.duplicate(true) if data is Dictionary else {}

static func all_npcs() -> Array:
	_ensure_loaded()
	var out: Array = []
	for data in _npcs:
		out.append(data.duplicate(true))
	return out

static func has_npc(id: String) -> bool:
	_ensure_loaded()
	return _by_id.has(id)

## 计算某地此刻应当出现的 NPC。不可交谈、已回家的人不会返回，避免幽灵节点。
static func npcs_in_location(location_id: String, calendar: GameCalendar,
		clock: GameClock, weather: Variant = null) -> Array:
	_ensure_loaded()
	var out: Array = []
	for raw in _npcs:
		var data: Dictionary = raw
		var resolved := NpcScheduleSystem.resolve(data, calendar, clock, weather)
		if not bool(resolved.get("available", false)):
			continue
		if String(resolved.get("location_id", "")) != location_id:
			continue
		out.append({
			"id": String(data.get("id", "")),
			"name": String(data.get("name", "")),
			"data": data.duplicate(true),
			"location_id": location_id,
			"position": resolved.get("position", Vector2.ZERO),
			"activity": String(resolved.get("activity", "")),
			"available": true,
		})
	return out
