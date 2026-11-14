extends RefCounted
class_name PostcardData

## 明信片数据库:从 data/postcards.json 加载。
##
## 数据只描述"远方有谁"和"他们会寄回什么";寄信、在途、投递规则
## 都在 PostcardSystem 里,这样整条通讯链路可以 headless 自测。

const POSTCARDS_PATH := "res://data/postcards.json"

static var _loaded := false
static var _recipients: Dictionary = {}
static var _postcards: Dictionary = {}
static var _delivery_days: int = 1

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_recipients = {}
	_postcards = {}
	_delivery_days = 1
	if not FileAccess.file_exists(POSTCARDS_PATH):
		push_warning("PostcardData: 未找到 %s" % POSTCARDS_PATH)
		return
	var f := FileAccess.open(POSTCARDS_PATH, FileAccess.READ)
	if f == null:
		push_warning("PostcardData: 无法打开 %s" % POSTCARDS_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("PostcardData: postcards.json 格式错误")
		return
	_delivery_days = maxi(1, int(parsed.get("delivery_days", 1)))
	for recipient in parsed.get("recipients", []):
		if recipient is Dictionary and String(recipient.get("id", "")) != "":
			_recipients[String(recipient.get("id", ""))] = recipient
	for postcard in parsed.get("postcards", []):
		if postcard is Dictionary and String(postcard.get("id", "")) != "":
			_postcards[String(postcard.get("id", ""))] = postcard

static func delivery_days() -> int:
	_load()
	return _delivery_days

static func all_recipients() -> Array:
	_load()
	return _recipients.values()

static func get_recipient(recipient_id: String) -> Dictionary:
	_load()
	return _recipients.get(recipient_id, {})

static func all_postcards() -> Array:
	_load()
	return _postcards.values()

static func get_postcard(postcard_id: String) -> Dictionary:
	_load()
	return _postcards.get(postcard_id, {})

static func reply_ids(recipient_id: String) -> Array:
	var recipient := get_recipient(recipient_id)
	return recipient.get("reply_cards", [])
