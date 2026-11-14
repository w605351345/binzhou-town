extends RefCounted
class_name MapDatabase

## maps.json 的纯逻辑查询与静态校验。
## 场景层只消费这里解析出的数据，不在脚本里硬编码另一套地图。

const MAPS_PATH := "res://data/maps.json"

static var _maps: Dictionary = {}
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(MAPS_PATH):
		push_error("地图数据不存在: %s" % MAPS_PATH)
		return
	var f := FileAccess.open(MAPS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("地图数据不是合法 JSON: %s" % MAPS_PATH)
		return
	for raw in parsed.get("maps", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var map: Dictionary = raw
		_maps[String(map.get("id", ""))] = map

static func get_map(id: String) -> Dictionary:
	_ensure_loaded()
	return _maps.get(id, {})

static func all_ids() -> Array:
	_ensure_loaded()
	var ids := _maps.keys()
	ids.sort()
	return ids

static func all_maps() -> Array:
	var out: Array = []
	for id in all_ids():
		out.append(get_map(id))
	return out

static func map_size(map: Dictionary) -> Vector2i:
	var size: Array = map.get("size", [960, 540])
	return Vector2i(int(size[0]), int(size[1]))

static func spawn_point(map: Dictionary) -> Vector2:
	var spawn: Array = map.get("spawn", [480, 460])
	return Vector2(float(spawn[0]), float(spawn[1]))

static func rect_from_array(value: Array) -> Rect2:
	if value.size() < 4:
		return Rect2()
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))

## 门的空间触发矩形。
static func door_rect(door: Dictionary) -> Rect2:
	return rect_from_array(door.get("rect", []))

## 返回地图里的门数据；没有命中返回空字典。
static func door_at(map: Dictionary, point: Vector2) -> Dictionary:
	for door in map.get("doors", []):
		if door_rect(door).has_point(point):
			return door
	return {}

static func interactables(map: Dictionary) -> Array:
	return map.get("interactables", [])

static func nearest_interactable(map: Dictionary, point: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := INF
	for item in interactables(map):
		var pos := Vector2(float(item.get("pos", [0, 0])[0]), float(item.get("pos", [0, 0])[1]))
		var radius := float(item.get("radius", 90.0))
		var dist := point.distance_to(pos)
		if dist <= radius and dist < best_dist:
			best = item
			best_dist = dist
	return best

## 校验所有门目标、目标出生点、双向配对与互动点。
static func validate_links() -> Array:
	var errors: Array = []
	_ensure_loaded()
	for id in all_ids():
		var map := get_map(id)
		var bounds := Rect2(Vector2.ZERO, Vector2(map_size(map)))
		if not bounds.has_point(spawn_point(map)):
			errors.append("%s 出生点越界" % id)
		if Array(map.get("interactables", [])).is_empty():
			errors.append("%s 没有互动点" % id)
		if Array(map.get("doors", [])).is_empty():
			errors.append("%s 没有出口" % id)
		for door in map.get("doors", []):
			var door_id := String(door.get("id", "?"))
			if not bounds.encloses(door_rect(door)):
				errors.append("%s/%s 门框越界" % [id, door_id])
			var target := String(door.get("target", ""))
			var target_map := get_map(target)
			if target_map.is_empty():
				errors.append("%s/%s 指向不存在的地图 %s" % [id, door_id, target])
				continue
			var target_spawn_raw: Array = door.get("target_spawn", [])
			if target_spawn_raw.size() < 2:
				errors.append("%s/%s 缺少 target_spawn" % [id, door_id])
			else:
				var target_spawn := Vector2(float(target_spawn_raw[0]), float(target_spawn_raw[1]))
				var target_bounds := Rect2(Vector2.ZERO, Vector2(map_size(target_map)))
				if not target_bounds.has_point(target_spawn):
					errors.append("%s/%s 目标出生点越界" % [id, door_id])
			if not _has_reverse_door(target_map, id):
				errors.append("%s/%s 目标地图没有返程门" % [id, door_id])
	return errors

static func _has_reverse_door(target_map: Dictionary, source_id: String) -> bool:
	for door in target_map.get("doors", []):
		if String(door.get("target", "")) == source_id:
			return true
	return false
