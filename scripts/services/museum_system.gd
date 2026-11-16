extends RefCounted
class_name MuseumSystem

const PATH := "res://data/museum.json"
static var _collectibles: Array = []
static var _by_item: Dictionary = {}
static var _milestones: Array = []
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("博物馆数据不存在: %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_collectibles = Array(parsed.get("collectibles", []))
	_milestones = Array(parsed.get("milestones", []))
	for raw in _collectibles:
		if raw is Dictionary:
			_by_item[String(raw.get("item_id", ""))] = raw

static func all_collectibles() -> Array:
	_ensure_loaded()
	return _collectibles.duplicate(true)

static func collectible_for_item(item_id: String) -> Dictionary:
	_ensure_loaded()
	var raw: Variant = _by_item.get(item_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}

static func ensure_state(state: GameState) -> void:
	if state == null:
		return
	if state.museum == null or not state.museum is Dictionary:
		state.museum = {}
	if not state.museum.get("donated", []) is Array:
		state.museum["donated"] = []
	if not state.museum.get("rewards", []) is Array:
		state.museum["rewards"] = []

static func donated_ids(state: GameState) -> Array:
	ensure_state(state)
	return Array(state.museum.get("donated", [])).duplicate()

static func is_donated(state: GameState, item_id: String) -> bool:
	return donated_ids(state).has(item_id)

static func can_donate(state: GameState, item_id: String) -> bool:
	ensure_state(state)
	if collectible_for_item(item_id).is_empty() or is_donated(state, item_id):
		return false
	return int(state.player.inventory.get(item_id, 0)) > 0

static func donate(state: GameState, item_id: String) -> Dictionary:
	ensure_state(state)
	if is_donated(state, item_id):
		return {"ok": false, "message": "这件已经摆在柜里了。"}
	var info := collectible_for_item(item_id)
	if info.is_empty():
		return {"ok": false, "message": "苏文博摇头：这件不算镇史藏品。"}
	var have := int(state.player.inventory.get(item_id, 0))
	if have <= 0:
		return {"ok": false, "message": "背包里没有这件东西。"}
	state.player.inventory[item_id] = have - 1
	if int(state.player.inventory[item_id]) <= 0:
		state.player.inventory.erase(item_id)
	state.museum["donated"].append(item_id)
	var messages: Array = ["《%s》入柜。" % info.get("name", item_id)]
	var count := Array(state.museum["donated"]).size()
	for raw in _milestones:
		var milestone: Dictionary = raw
		var need := int(milestone.get("count", 0))
		var key := "milestone_%d" % need
		if count < need or Array(state.museum.get("rewards", [])).has(key):
			continue
		state.museum["rewards"].append(key)
		state.player.gold += int(milestone.get("gold", 0))
		for reward_id in Dictionary(milestone.get("items", {})).keys():
			state.player.inventory[String(reward_id)] = \
				int(state.player.inventory.get(String(reward_id), 0)) + \
				int(milestone["items"][reward_id])
		messages.append(String(milestone.get("message", "馆里记下了一笔。")))
	SkillSystem.add_xp(state.player, "foraging", 6)
	QuestSystem.progress(state, "museum_donate", 1)
	return {"ok": true, "count": count, "messages": messages,
		"message": " ".join(messages)}

static func progress_text(state: GameState) -> String:
	_ensure_loaded()
	return "藏品 %d/%d" % [donated_ids(state).size(), _collectibles.size()]
