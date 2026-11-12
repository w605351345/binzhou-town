extends RefCounted
class_name CropDatabase

## 作物数据库:从 data/crops.json 加载,提供查询与季节校验。
## 黑龙江设定:一年一熟,春播秋收,冬季休耕。

const CROPS_PATH := "res://data/crops.json"

static var _cache: Dictionary = {}
static var _loaded := false

static func load_all() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	_cache = {}
	if not FileAccess.file_exists(CROPS_PATH):
		push_warning("CropDatabase: 未找到 %s" % CROPS_PATH)
		return _cache
	var f := FileAccess.open(CROPS_PATH, FileAccess.READ)
	if f == null:
		push_warning("CropDatabase: 无法打开 %s" % CROPS_PATH)
		return _cache
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("CropDatabase: crops.json 格式错误")
		return _cache
	for c in parsed.get("crops", []):
		if c is Dictionary:
			var crop := Crop.from_dict(c)
			if crop.id != "":
				_cache[crop.id] = crop
	return _cache

static func get_crop(id: String) -> Crop:
	return load_all().get(id, null)

static func all_ids() -> Array:
	return load_all().keys()

static func all_crops() -> Array:
	return load_all().values()

static func mvp_crops() -> Array:
	var out: Array = []
	for c in all_crops():
		if c.mvp:
			out.append(c)
	return out

## 在指定季节可播种的作物(黑龙江:春播为主)
static func sowable_in(season: String) -> Array:
	var out: Array = []
	for c in all_crops():
		if c.can_sow_in(season):
			out.append(c)
	return out

## 秋收作物:收获季为 autumn
static func autumn_harvest_crops() -> Array:
	var out: Array = []
	for c in all_crops():
		if c.is_autumn_harvest():
			out.append(c)
	return out

static func winter_produce() -> Array:
	load_all()
	var f := FileAccess.open(CROPS_PATH, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	return parsed.get("winter_produce", [])
