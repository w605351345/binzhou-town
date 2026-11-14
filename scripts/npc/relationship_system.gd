extends RefCounted
class_name RelationshipSystem

## 交谈、送礼、生日与事件完成对关系的统一写入口。

const TALK_GAIN := 2
const LIKED_GAIN := 30
const NEUTRAL_GAIN := 8
const DISLIKED_GAIN := -20
const BIRTHDAY_MULTIPLIER := 3

static func relationship(state: GameState, npc_id: String) -> Dictionary:
	if state == null or npc_id == "":
		return {}
	if not state.relationships.has(npc_id):
		state.relationships[npc_id] = {
			"affection": 0,
			"gifted_today": false,
			"talked_today": false,
			"last_talk_day": -1,
			"last_gift_day": -1,
			"events_done": [],
		}
	var rel: Dictionary = state.relationships[npc_id]
	for key in ["affection", "gifted_today", "talked_today", "last_talk_day",
			"last_gift_day", "events_done"]:
		if not rel.has(key):
			rel[key] = [] if key == "events_done" else (-1 if key.begins_with("last_") else 0)
	return rel

static func talk(state: GameState, npc_id: String) -> Dictionary:
	var rel := relationship(state, npc_id)
	if rel.is_empty():
		return {"ok": false, "gain": 0, "already": false, "message": "没有可交谈的人"}
	var today := state.calendar.abs_day()
	if int(rel.get("last_talk_day", -1)) == today:
		rel["talked_today"] = true
		return {"ok": true, "gain": 0, "already": true,
			"message": "今天已经聊过了，关系不会再增加。"}
	rel["last_talk_day"] = today
	rel["talked_today"] = true
	rel["affection"] = int(rel.get("affection", 0)) + TALK_GAIN
	state.relationships[npc_id] = rel
	QuestSystem.progress(state, "talk", 1)
	return {"ok": true, "gain": TALK_GAIN, "already": false,
		"message": "聊了几句，好感 +%d。" % TALK_GAIN}

static func give_gift(state: GameState, npc_data: Dictionary, item_id: String) -> Dictionary:
	if state == null or npc_data.is_empty():
		return {"ok": false, "gain": 0, "message": "没有可送的人"}
	var npc_id := String(npc_data.get("id", ""))
	var rel := relationship(state, npc_id)
	if rel.is_empty():
		return {"ok": false, "gain": 0, "message": "没有可送的人"}
	if int(rel.get("last_gift_day", -1)) == state.calendar.abs_day():
		return {"ok": false, "gain": 0, "message": "%s今天已经收过礼物了" %
			String(npc_data.get("name", "对方"))}
	var item := ItemDatabase.get_item(item_id)
	if item.is_empty():
		return {"ok": false, "gain": 0, "message": "没有这件东西"}
	var have := int(state.player.inventory.get(item_id, 0))
	if have <= 0:
		return {"ok": false, "gain": 0, "message": "背包里没有%s" % item.get("name", item_id)}

	var item_name := String(item.get("name", item_id))
	var gain := NEUTRAL_GAIN
	var reaction := "普通"
	if _names_contain(npc_data.get("likes", []), item_name):
		gain = LIKED_GAIN
		reaction = "喜欢"
	elif _names_contain(npc_data.get("dislikes", []), item_name):
		gain = DISLIKED_GAIN
		reaction = "讨厌"
	var birthday := is_birthday(state, npc_data)
	if birthday and gain > 0:
		gain *= BIRTHDAY_MULTIPLIER
	state.player.inventory[item_id] = have - 1
	if int(state.player.inventory[item_id]) <= 0:
		state.player.inventory.erase(item_id)
	rel["last_gift_day"] = state.calendar.abs_day()
	rel["gifted_today"] = true
	rel["affection"] = clampi(int(rel.get("affection", 0)) + gain, 0,
		int(npc_data.get("affection_max", 100)))
	state.relationships[npc_id] = rel
	QuestSystem.progress(state, "gift", 1)

	var message := "%s%s了%s。" % [npc_data.get("name", "对方"), "收下" if gain >= 0 else "没有收", item_name]
	if reaction == "喜欢":
		message += "看得出是真喜欢。"
	elif reaction == "讨厌":
		message += "气氛一下冷了下来。"
	else:
		message += "客气地放在一边。"
	if birthday:
		message += "今天是她/他的生日，这份心意分量不一样。"
	return {
		"ok": true, "gain": gain, "reaction": reaction,
		"birthday": birthday, "message": message,
	}

static func is_birthday(state: GameState, npc_data: Dictionary) -> bool:
	if state == null or npc_data.is_empty():
		return false
	return state.calendar.get_real_month() == int(npc_data.get("birthday_month", -1)) \
		and state.calendar.get_day_of_month() == int(npc_data.get("birthday_day", -1))

static func mark_event_done(state: GameState, npc_id: String, event_id: String) -> void:
	var rel := relationship(state, npc_id)
	if rel.is_empty():
		return
	var done: Array = rel.get("events_done", [])
	if not done.has(event_id):
		done.append(event_id)
	rel["events_done"] = done
	rel["affection"] = clampi(int(rel.get("affection", 0)) + 10, 0, 100)
	state.relationships[npc_id] = rel

static func _names_contain(values: Variant, item_name: String) -> bool:
	if not (values is Array):
		return false
	for value in values:
		if String(value) == item_name:
			return true
	return false
