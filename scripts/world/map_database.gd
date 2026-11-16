extends RefCounted
class_name MapDatabase

## maps.json 的纯逻辑查询与静态校验。
## 场景层只消费这里解析出的数据，不在脚本里硬编码另一套地图。

const MAPS_PATH := "res://data/maps.json"

## 会挡住主角行走的道具。灯、告示牌、灯笼这类装饰仍然允许贴近/穿过,
## 其余有实体占地的家具、建筑与树木都要有碰撞,否则人物会直接穿墙。
const SOLID_PROP_TYPES := {
	"house": true, "building": true, "barn": true, "fence": true,
	"well": true, "woodpile": true, "haystack": true, "cart": true,
	"plow": true, "barrel": true, "crate": true, "water_trough": true,
	"tool_rack": true, "bench": true, "counter": true, "shelf": true,
	"stove": true, "bed": true, "chest": true, "calendar": true,
	"table": true, "desk": true, "mailboxes": true, "medicine_cabinet": true,
	"stage": true, "backstage": true, "instrument": true, "ice_block": true,
	"shrine": true, "fallen_log": true, "mushroom_log": true, "reeds": true,
	"gravestone": true, "tree": true, "birch": true,
	"flowerbed": true, "shrub": true,
}

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

## 真实可达性：不只检查门中心是否被碰撞覆盖，而是从出生点沿可走区域寻路。
## 网格会按人物半宽扩张实体障碍，避免“测试能到、人物却卡在门框边”的假通过。
static func is_reachable(map: Dictionary, from: Vector2, to: Vector2,
		cell_size: float = 28.0, body_radius: float = 12.0) -> bool:
	if map.is_empty():
		return false
	var size := map_size(map)
	var cols := maxi(1, int(ceil(float(size.x) / cell_size)))
	var rows := maxi(1, int(ceil(float(size.y) / cell_size)))
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, cols, rows)
	astar.cell_size = Vector2(cell_size, cell_size)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	var solids := solid_rects(map)
	for y in rows:
		for x in cols:
			var tile := Rect2(Vector2(x, y) * cell_size, Vector2.ONE * cell_size)
			for solid in solids:
				if solid.grow(body_radius).intersects(tile, true):
					astar.set_point_solid(Vector2i(x, y), true)
					break
	var start_cell := _nearest_open_cell(astar, _cell_for_point(from, cell_size), cols, rows)
	var end_cell := _nearest_open_cell(astar, _cell_for_point(to, cell_size), cols, rows)
	if start_cell.x < 0 or end_cell.x < 0:
		return false
	if start_cell == end_cell:
		return true
	var path := astar.get_id_path(start_cell, end_cell)
	return not path.is_empty()

static func _cell_for_point(point: Vector2, cell_size: float) -> Vector2i:
	return Vector2i(int(floor(point.x / cell_size)), int(floor(point.y / cell_size)))

static func _nearest_open_cell(astar: AStarGrid2D, wanted: Vector2i,
		cols: int, rows: int) -> Vector2i:
	for radius in 5:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var cell := wanted + Vector2i(dx, dy)
				if cell.x < 0 or cell.y < 0 or cell.x >= cols or cell.y >= rows:
					continue
				if not astar.is_point_solid(cell):
					return cell
	return Vector2i(-1, -1)

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

## 道具的实体碰撞矩形。树只挡树干；建筑只挡底部落地部分，
## 不把屋顶和透明边距也当成墙。
static func prop_solid_rect(prop: Dictionary) -> Rect2:
	var kind := String(prop.get("type", ""))
	if not bool(SOLID_PROP_TYPES.get(kind, false)):
		return Rect2()
	var rect := rect_from_array(prop.get("rect", []))
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Rect2()
	if kind == "tree" or kind == "birch":
		var trunk_w := clampf(rect.size.x * 0.28, 28.0, 54.0)
		var trunk_h := clampf(rect.size.y * 0.26, 42.0, 70.0)
		return Rect2(rect.get_center().x - trunk_w * 0.5,
			rect.end.y - trunk_h, trunk_w, trunk_h)
	if kind in ["house", "building", "barn", "stage", "backstage"]:
		var footprint_w := rect.size.x * 0.86
		var footprint_h := rect.size.y * 0.58
		return Rect2(rect.get_center().x - footprint_w * 0.5,
			rect.end.y - footprint_h, footprint_w, footprint_h)
	if kind in ["stall", "counter", "shelf", "bench", "stove", "bed", "table",
			"desk", "chest", "medicine_cabinet", "water_trough"]:
		var footprint_w := rect.size.x * 0.92
		var footprint_h := rect.size.y * 0.84
		return Rect2(rect.get_center().x - footprint_w * 0.5,
			rect.end.y - footprint_h, footprint_w, footprint_h)
	return rect

## 地图里所有要挡人的矩形。门框会从实体矩形中挖掉,保证每扇门都能走到。
static func solid_rects(map: Dictionary) -> Array:
	var out: Array = []
	for prop in map.get("props", []):
		if typeof(prop) != TYPE_DICTIONARY:
			continue
		var rect := prop_solid_rect(prop)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var pieces: Array = [rect]
		for door in map.get("doors", []):
			var hole := door_rect(door).grow(10.0)
			var next: Array = []
			for piece in pieces:
				next.append_array(_subtract_rect(piece, hole))
			pieces = next
		for piece in pieces:
			if piece.size.x >= 6.0 and piece.size.y >= 6.0:
				out.append(piece)
	for layer in map.get("terrain", []):
		if String(layer.get("type", "")) == "water":
			var water := rect_from_array(layer.get("rect", []))
			if water.size.x > 0.0 and water.size.y > 0.0:
				out.append(water)
	return out

## 用 hole 挖掉 rect 的交集,返回最多四块剩余矩形。用于给门留出通道。
static func _subtract_rect(rect: Rect2, hole: Rect2) -> Array:
	if not rect.intersects(hole, true):
		return [rect]
	var cut := rect.intersection(hole)
	var out: Array = []
	var top_h := maxf(0.0, cut.position.y - rect.position.y)
	var bottom_y := maxf(cut.end.y, rect.position.y)
	var bottom_h := maxf(0.0, rect.end.y - bottom_y)
	var left := Rect2(rect.position.x, rect.position.y, cut.position.x - rect.position.x,
		rect.size.y)
	if left.size.x >= 6.0 and left.size.y >= 6.0:
		out.append(left)
	var right := Rect2(cut.end.x, rect.position.y, rect.end.x - cut.end.x, rect.size.y)
	if right.size.x >= 6.0 and right.size.y >= 6.0:
		out.append(right)
	var top := Rect2(cut.position.x, rect.position.y, cut.size.x, top_h)
	if top.size.x >= 6.0 and top.size.y >= 6.0:
		out.append(top)
	var bottom := Rect2(cut.position.x, bottom_y, cut.size.x, bottom_h)
	if bottom.size.x >= 6.0 and bottom.size.y >= 6.0:
		out.append(bottom)
	return out

## 校验所有门目标、目标出生点、双向配对与互动点。
static func validate_links() -> Array:
	var errors: Array = []
	_ensure_loaded()
	for id in all_ids():
		var map := get_map(id)
		var bounds := Rect2(Vector2.ZERO, Vector2(map_size(map)))
		var solids := solid_rects(map)
		if not bounds.has_point(spawn_point(map)):
			errors.append("%s 出生点越界" % id)
		for solid in solids:
			if solid.has_point(spawn_point(map)):
				errors.append("%s 出生点被实体挡住" % id)
				break
		if Array(map.get("interactables", [])).is_empty():
			errors.append("%s 没有互动点" % id)
		if Array(map.get("doors", [])).is_empty():
			errors.append("%s 没有出口" % id)
		for door in map.get("doors", []):
			var door_id := String(door.get("id", "?"))
			var door_rect := door_rect(door)
			if not bounds.encloses(door_rect):
				errors.append("%s/%s 门框越界" % [id, door_id])
			for solid in solids:
				if solid.has_point(door_rect.get_center()):
					errors.append("%s/%s 门中心被实体挡住" % [id, door_id])
					break
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
			if not is_reachable(map, spawn_point(map), door_rect(door).get_center()):
				errors.append("%s/%s 从出生点无法走到门口" % [id, door_id])
	return errors

static func _has_reverse_door(target_map: Dictionary, source_id: String) -> bool:
	for door in target_map.get("doors", []):
		if String(door.get("target", "")) == source_id:
			return true
	return false
