extends RefCounted
class_name QuestSystem

## 公告板任务状态机。任务数据在 quests.json，进度与完成记录写进 GameState。

const QUESTS_PATH := "res://data/quests.json"
static var _quests: Array = []
static var _by_id: Dictionary = {}
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(QUESTS_PATH, FileAccess.READ)
	if f == null:
		push_error("任务数据不存在: %s" % QUESTS_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_quests = Array(parsed.get("quests", []))
		for quest in _quests:
			_by_id[String(quest.get("id", ""))] = quest

static func all_quests() -> Array:
	_ensure_loaded()
	return _quests.duplicate(true)

static func get_quest(quest_id: String) -> Dictionary:
	_ensure_loaded()
	var quest: Variant = _by_id.get(quest_id, {})
	return quest.duplicate(true) if quest is Dictionary else {}

static func _ensure_state(state: GameState) -> void:
	if state == null:
		return
	if not state.quests.has("active") or not (state.quests["active"] is Array):
		state.quests["active"] = []
	if not state.quests.has("completed") or not (state.quests["completed"] is Array):
		state.quests["completed"] = []
	if not state.quests.has("completed_days") or not (state.quests["completed_days"] is Dictionary):
		state.quests["completed_days"] = {}

static func active_entries(state: GameState) -> Array:
	if state == null:
		return []
	_ensure_state(state)
	return (state.quests["active"] as Array).duplicate(true)

static func active_entry(state: GameState, quest_id: String) -> Dictionary:
	if state == null:
		return {}
	_ensure_state(state)
	for entry in state.quests["active"]:
		if entry is Dictionary and String(entry.get("id", "")) == quest_id:
			return entry
	return {}

static func is_active(state: GameState, quest_id: String) -> bool:
	return not active_entry(state, quest_id).is_empty()

static func is_completed(state: GameState, quest_id: String) -> bool:
	if state == null:
		return false
	_ensure_state(state)
	return (state.quests["completed"] as Array).has(quest_id)

static func available_quests(state: GameState, calendar: GameCalendar) -> Array:
	_ensure_loaded()
	if state == null or calendar == null:
		return []
	_ensure_state(state)
	var out: Array = []
	var today := calendar.abs_day()
	for raw in _quests:
		var quest: Dictionary = raw
		var quest_id := String(quest.get("id", ""))
		if is_active(state, quest_id):
			continue
		var repeatable := bool(quest.get("repeatable", false))
		if repeatable:
			if int((state.quests["completed_days"] as Dictionary).get(quest_id, -1)) == today:
				continue
		elif is_completed(state, quest_id):
			continue
		if not _conditions_ok(state, quest, calendar):
			continue
		out.append(quest.duplicate(true))
	return out

static func accept(state: GameState, quest_id: String) -> Dictionary:
	var quest := get_quest(quest_id)
	if quest.is_empty() or state == null:
		return {"ok": false, "message": "公告板上没有这条活"}
	_ensure_state(state)
	if is_active(state, quest_id):
		return {"ok": false, "message": "这条活已经接了"}
	var repeatable := bool(quest.get("repeatable", false))
	if not repeatable and is_completed(state, quest_id):
		return {"ok": false, "message": "这条活已经办完了"}
	var today := state.calendar.abs_day()
	if repeatable and int((state.quests["completed_days"] as Dictionary).get(quest_id, -1)) == today:
		return {"ok": false, "message": "今天的活已经交过了，明天再来"}
	if not _conditions_ok(state, quest, state.calendar):
		return {"ok": false, "message": "眼下还接不了这条活"}
	(state.quests["active"] as Array).append({
		"id": quest_id,
		"accepted_day": today,
		"progress": {},
	})
	return {
		"ok": true, "quest": quest,
		"message": "接了「%s」。%s" % [quest.get("title", quest_id), quest.get("summary", "")],
	}

## 动作类任务推进。target 例如 cook / fish / forage / harvest / talk / gift。
static func progress(state: GameState, target: String, amount: int = 1) -> Array:
	var updates: Array = []
	if state == null or target == "" or amount <= 0:
		return updates
	_ensure_state(state)
	for entry in state.quests["active"]:
		if not (entry is Dictionary):
			continue
		var quest := get_quest(String(entry.get("id", "")))
		if quest.is_empty():
			continue
		var progress_map: Dictionary = entry.get("progress", {})
		var changed := false
		for req in quest.get("requirements", []):
			if String(req.get("type", "")) != "action":
				continue
			if String(req.get("target", "")) != target:
				continue
			var old := int(progress_map.get(target, 0))
			var needed := int(req.get("count", 1))
			var new_value := mini(needed, old + amount)
			if new_value != old:
				progress_map[target] = new_value
				changed = true
				updates.append({
					"quest_id": String(entry.get("id", "")),
					"target": target, "value": new_value, "needed": needed,
				})
		if changed:
			entry["progress"] = progress_map
	return updates

static func can_turn_in(state: GameState, quest_id: String) -> bool:
	var entry := active_entry(state, quest_id)
	if entry.is_empty():
		return false
	var quest := get_quest(quest_id)
	if quest.is_empty():
		return false
	var progress_map: Dictionary = entry.get("progress", {})
	for req in quest.get("requirements", []):
		var req_type := String(req.get("type", ""))
		match req_type:
			"deliver":
				var item_id := String(req.get("item_id", ""))
				if int(state.player.inventory.get(item_id, 0)) < int(req.get("count", 1)):
					return false
			"action":
				var target := String(req.get("target", ""))
				if int(progress_map.get(target, 0)) < int(req.get("count", 1)):
					return false
			"event":
				var events: Array = state.events.get("done", [])
				if not events.has(String(req.get("event_id", ""))):
					return false
			"flag":
				if not bool(state.flags.get(String(req.get("flag", "")), false)):
					return false
			_:
				return false
	return true

static func turn_in(state: GameState, quest_id: String) -> Dictionary:
	if not can_turn_in(state, quest_id):
		return {"ok": false, "message": "这条活还没办完，或者要交的东西不够"}
	var quest := get_quest(quest_id)
	for req in quest.get("requirements", []):
		if String(req.get("type", "")) == "deliver":
			var item_id := String(req.get("item_id", ""))
			var left := int(state.player.inventory.get(item_id, 0)) - int(req.get("count", 1))
			if left <= 0:
				state.player.inventory.erase(item_id)
			else:
				state.player.inventory[item_id] = left
	var rewards: Dictionary = quest.get("rewards", {})
	var gold := int(rewards.get("gold", 0))
	state.player.gold += gold
	var reward_items: Dictionary = rewards.get("items", {})
	for item_id in reward_items.keys():
		state.player.inventory[String(item_id)] = int(state.player.inventory.get(
			String(item_id), 0)) + int(reward_items[item_id])
	var affection := int(rewards.get("affection", 0))
	var giver := String(quest.get("giver", ""))
	if affection > 0 and giver != "":
		state.set_npc_affection(giver, state.npc_affection(giver) + affection)
	_ensure_state(state)
	var completed: Array = state.quests["completed"]
	if not completed.has(quest_id):
		completed.append(quest_id)
	(state.quests["completed_days"] as Dictionary)[quest_id] = state.calendar.abs_day()
	var active: Array = state.quests["active"]
	for i in range(active.size() - 1, -1, -1):
		if active[i] is Dictionary and String(active[i].get("id", "")) == quest_id:
			active.remove_at(i)
	var reward_parts: Array = []
	if gold > 0:
		reward_parts.append("%d 文" % gold)
	if affection > 0:
		reward_parts.append("好感 +%d" % affection)
	if not reward_items.is_empty():
		reward_parts.append("%d 件东西" % reward_items.size())
	return {
		"ok": true, "gold": gold, "affection": affection, "items": reward_items,
		"message": "交完「%s」%s" % [quest.get("title", quest_id),
			("，得到" + "、".join(reward_parts)) if not reward_parts.is_empty() else "。"],
	}

static func requirement_text(req: Dictionary) -> String:
	var req_type := String(req.get("type", ""))
	match req_type:
		"deliver":
			var item_id := String(req.get("item_id", ""))
			var item := ItemDatabase.get_item(item_id)
			return "交付 %s ×%d" % [item.get("name", item_id), int(req.get("count", 1))]
		"action":
			return "%s %d 次" % [req.get("label", req.get("target", "完成动作")),
				int(req.get("count", 1))]
		"event":
			return String(req.get("label", "完成指定人物故事"))
		"flag":
			return String(req.get("label", "满足条件"))
	return "完成委托"

static func progress_text(state: GameState, quest_id: String) -> String:
	var entry := active_entry(state, quest_id)
	var quest := get_quest(quest_id)
	if entry.is_empty() or quest.is_empty():
		return ""
	var progress_map: Dictionary = entry.get("progress", {})
	var parts: Array = []
	for req in quest.get("requirements", []):
		if String(req.get("type", "")) == "action":
			var target := String(req.get("target", ""))
			parts.append("%d/%d" % [int(progress_map.get(target, 0)), int(req.get("count", 1))])
		elif String(req.get("type", "")) == "deliver":
			var item_id := String(req.get("item_id", ""))
			parts.append("%d/%d" % [int(state.player.inventory.get(item_id, 0)),
				int(req.get("count", 1))])
	return " · ".join(parts)

static func _conditions_ok(state: GameState, quest: Dictionary, calendar: GameCalendar) -> bool:
	var min_affection := int(quest.get("min_affection", 0))
	if state.npc_affection(String(quest.get("giver", ""))) < min_affection:
		return false
	var seasons: Array = quest.get("seasons", [])
	if not seasons.is_empty() and not seasons.has(calendar.get_season()):
		return false
	var required_flags: Dictionary = quest.get("requires_flags", {})
	for flag in required_flags.keys():
		if state.flags.get(flag, null) != required_flags[flag]:
			return false
	return true
