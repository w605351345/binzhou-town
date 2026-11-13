extends RefCounted
class_name DialogueData

## 对话数据库:从 data/dialogues.json 加载。
##
## 一份对话 = 一个条目列表(lines)。每个条目:
##   { "id", "text", "condition": {...}, "options": [...] }
## 选项:
##   { "text", "next": "条目id" }        跳到另一条
##   { "text", "next": null }            结束对话
##   { "text", "action": "shop_sell" }   触发动作(商店/好感度/标记等)

const DIALOGUES_PATH := "res://data/dialogues.json"

static var _cache: Dictionary = {}
static var _loaded := false

static func load_all() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	_cache = {}
	if not FileAccess.file_exists(DIALOGUES_PATH):
		push_warning("DialogueData: 未找到 %s" % DIALOGUES_PATH)
		return _cache
	var f := FileAccess.open(DIALOGUES_PATH, FileAccess.READ)
	if f == null:
		push_warning("DialogueData: 无法打开 %s" % DIALOGUES_PATH)
		return _cache
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("DialogueData: dialogues.json 格式错误")
		return _cache
	for d in parsed.get("dialogues", []):
		if d is Dictionary and String(d.get("id", "")) != "":
			_cache[String(d.get("id", ""))] = d
	return _cache

static func get_dialogue(id: String) -> Dictionary:
	return load_all().get(id, {})

static func all_ids() -> Array:
	return load_all().keys()

## 某位 NPC 的对话
static func dialogue_for_npc(npc_id: String) -> Dictionary:
	for d in load_all().values():
		if String(d.get("npc_id", "")) == npc_id:
			return d
	return {}
