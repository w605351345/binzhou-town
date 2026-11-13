extends RefCounted
class_name ItemDatabase

## 道具数据库:从 data/items.json 加载。
##
## 与 CropDatabase 同一套路 —— 数据在 JSON 里,逻辑在 GDScript 里,
## 这样价格表能单独校验,商店结算也能在 headless 下自测。

const ITEMS_PATH := "res://data/items.json"

static var _cache: Dictionary = {}
static var _loaded := false

static func load_all() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	_cache = {}
	if not FileAccess.file_exists(ITEMS_PATH):
		push_warning("ItemDatabase: 未找到 %s" % ITEMS_PATH)
		return _cache
	var f := FileAccess.open(ITEMS_PATH, FileAccess.READ)
	if f == null:
		push_warning("ItemDatabase: 无法打开 %s" % ITEMS_PATH)
		return _cache
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("ItemDatabase: items.json 格式错误")
		return _cache
	for item in parsed.get("items", []):
		if item is Dictionary:
			var item_id := String(item.get("id", ""))
			if item_id != "":
				_cache[item_id] = item
	return _cache

static func get_item(item_id: String) -> Dictionary:
	return load_all().get(item_id, {})

static func all_items() -> Array:
	return load_all().values()

## 某个分类的道具(seed / tool / food / material)
static func items_of_category(category: String) -> Array:
	var out: Array = []
	for item in all_items():
		if String(item.get("category", "")) == category:
			out.append(item)
	return out

## 商店在售的种子
static func seed_items() -> Array:
	return items_of_category("seed")

## 某作物对应的种子道具 id(没配种子返回空)
static func seed_for_crop(crop_id: String) -> String:
	for item in seed_items():
		if String(item.get("crop_id", "")) == crop_id:
			return String(item.get("id", ""))
	return ""
