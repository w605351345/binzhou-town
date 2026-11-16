extends RefCounted
class_name DramaSystem

## 《月桂谣》三幕古戏的纯逻辑层。
## 剧本、选择、解锁与结局全部数据驱动；UI 只负责呈现和转发点击。

const DATA_PATH := "res://data/drama.json"

static var _data: Dictionary = {}
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(DATA_PATH):
		push_error("剧本数据不存在: %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("剧本数据不是合法 JSON: %s" % DATA_PATH)
		return
	_data = parsed

static func title() -> String:
	_ensure_loaded()
	return String(_data.get("title", "月桂谣"))

static func subtitle() -> String:
	_ensure_loaded()
	return String(_data.get("subtitle", "月桂剧场 · 三幕古戏"))

static func premise() -> String:
	_ensure_loaded()
	return String(_data.get("premise", ""))

static func all_acts() -> Array:
	_ensure_loaded()
	return Array(_data.get("acts", []))

static func get_act(act_id: String) -> Dictionary:
	for act in all_acts():
		if String(act.get("id", "")) == act_id:
			return act
	return {}

static func harvested_total(state: GameState) -> int:
	if state == null:
		return 0
	return int(state.flags.get("harvested_total", 0))

## 把农事主循环和古戏进度说成玩家能执行的一句话。
## 收菜时 HUD 会直接显示“还差几份”，避免玩家不知道 20% 的剧本该怎么推进。
static func farm_progress_text(state: GameState) -> String:
	if state == null:
		return ""
	var total := harvested_total(state)
	for act in all_acts():
		var act_id := String(act.get("id", ""))
		if is_completed(state, act_id):
			continue
		var title := String(act.get("title", act.get("name", "下一幕")))
		var need := int(Dictionary(act.get("unlock", {})).get("harvested_total", 0))
		if total < need:
			return "累计收获 %d 份作物 · 《%s》还差 %d 份解锁" % [
				total, title, need - total]
		var acts := all_acts()
		var index := acts.find(act)
		if index > 0:
			var previous := String(acts[index - 1].get("id", ""))
			if not is_completed(state, previous):
				return "累计收获 %d 份作物 · 先去月桂剧场演完上一幕" % total
		return "累计收获 %d 份作物 · 《%s》已可排练" % [total, title]
	if all_completed(state):
		return "累计收获 %d 份作物 · 三幕古戏已全部公演" % total
	return "累计收获 %d 份作物" % total

static func _progress(state: GameState) -> Dictionary:
	if state.drama_progress == null:
		state.drama_progress = {}
	var p: Dictionary = state.drama_progress
	if not p.has("acts_completed"):
		p["acts_completed"] = []
	if not p.has("node_index"):
		p["node_index"] = {}
	if not p.has("choices"):
		p["choices"] = {}
	if not p.has("reputation"):
		p["reputation"] = 0
	if not p.has("current_act"):
		p["current_act"] = ""
	state.drama_progress = p
	return p

static func is_completed(state: GameState, act_id: String) -> bool:
	return Array(_progress(state).get("acts_completed", [])).has(act_id)

static func unlock_text(act: Dictionary) -> String:
	var need := int(Dictionary(act.get("unlock", {})).get("harvested_total", 0))
	if need <= 0:
		return "已解锁"
	return "累计收获 %d 份作物后解锁" % need

static func is_unlocked(state: GameState, act_id: String) -> bool:
	var acts := all_acts()
	var index := -1
	for i in acts.size():
		if String(acts[i].get("id", "")) == act_id:
			index = i
			break
	if index < 0:
		return false
	var act: Dictionary = acts[index]
	if index > 0:
		var previous_id := String(acts[index - 1].get("id", ""))
		if not is_completed(state, previous_id):
			return false
	var need := int(Dictionary(act.get("unlock", {})).get("harvested_total", 0))
	return harvested_total(state) >= need

static func act_state_text(state: GameState, act: Dictionary) -> String:
	var act_id := String(act.get("id", ""))
	if is_completed(state, act_id):
		return "已完成"
	if not is_unlocked(state, act_id):
		return unlock_text(act)
	var idx := int(Dictionary(_progress(state).get("node_index", {})).get(act_id, 0))
	var nodes: Array = act.get("nodes", [])
	return "可排练 · 第 %d/%d 场" % [mini(idx + 1, nodes.size()), nodes.size()]

## 进入某一幕。已完成的一幕可以重看，但不会重复发奖励。
static func begin_act(state: GameState, act_id: String) -> Dictionary:
	var act := get_act(act_id)
	if act.is_empty():
		return {"ok": false, "message": "找不到这一幕的戏页。"}
	if not is_unlocked(state, act_id):
		return {"ok": false, "message": unlock_text(act)}
	var p := _progress(state)
	p["current_act"] = act_id
	var indexes: Dictionary = p["node_index"]
	if not indexes.has(act_id):
		indexes[act_id] = 0
	if is_completed(state, act_id):
		return {"ok": true, "message": "这一幕已经演过，可以再翻翻戏页。",
			"completed": true, "node": _node_at(act, int(indexes[act_id]))}
	return {"ok": true, "message": String(act.get("summary", "")),
		"completed": false, "node": _node_at(act, int(indexes[act_id]))}

static func current_act_id(state: GameState) -> String:
	var p := _progress(state)
	var current := String(p.get("current_act", ""))
	if current != "":
		return current
	for act in all_acts():
		var act_id := String(act.get("id", ""))
		if not is_completed(state, act_id) and is_unlocked(state, act_id):
			return act_id
	return String(all_acts().back().get("id", "act1")) if not all_acts().is_empty() else ""

static func current_node(state: GameState, act_id: String = "") -> Dictionary:
	var id := act_id if act_id != "" else current_act_id(state)
	var act := get_act(id)
	if act.is_empty():
		return {}
	var indexes: Dictionary = _progress(state).get("node_index", {})
	return _node_at(act, int(indexes.get(id, 0)))

static func _node_at(act: Dictionary, index: int) -> Dictionary:
	var nodes: Array = act.get("nodes", [])
	if nodes.is_empty():
		return {}
	return nodes[clampi(index, 0, nodes.size() - 1)]

## 选择一个分支。返回结果文案、是否完成整幕，以及新增奖励。
static func choose(state: GameState, act_id: String, choice_id: String) -> Dictionary:
	var act := get_act(act_id)
	if act.is_empty() or not is_unlocked(state, act_id):
		return {"ok": false, "message": "这一幕还没解锁。"}
	var p := _progress(state)
	var indexes: Dictionary = p["node_index"]
	var idx := int(indexes.get(act_id, 0))
	var nodes: Array = act.get("nodes", [])
	if idx >= nodes.size():
		return {"ok": false, "message": "这一幕已经演完了。"}
	var node: Dictionary = nodes[idx]
	var chosen: Dictionary = {}
	for option in node.get("choices", []):
		if String(option.get("id", "")) == choice_id:
			chosen = option
			break
	if chosen.is_empty():
		return {"ok": false, "message": "这页戏词对不上。"}

	var rep := int(chosen.get("reputation", 0))
	p["reputation"] = int(p.get("reputation", 0)) + rep
	var choices: Dictionary = p["choices"]
	var trail: Array = choices.get(act_id, [])
	trail.append({
		"node_id": String(node.get("id", "")),
		"choice_id": choice_id,
		"label": String(chosen.get("label", "")),
	})
	choices[act_id] = trail
	var bonds: Dictionary = chosen.get("bond", {})
	for npc_id in bonds.keys():
		var key := String(npc_id)
		state.set_npc_affection(key, state.npc_affection(key) + int(bonds[npc_id]))
	indexes[act_id] = idx + 1
	p["node_index"] = indexes

	var finished := idx + 1 >= nodes.size()
	var reward: Dictionary = {}
	if finished and not is_completed(state, act_id):
		var completed: Array = p["acts_completed"]
		completed.append(act_id)
		p["acts_completed"] = completed
		reward = _grant_reward(state, act)
	# 下一幕已解锁时自动把“当前幕”推进过去，面板无需刷新两次。
	var acts := all_acts()
	for i in acts.size():
		if String(acts[i].get("id", "")) == act_id and i + 1 < acts.size():
			var next_id := String(acts[i + 1].get("id", ""))
			if is_unlocked(state, next_id):
				p["current_act"] = next_id
			break
	state.drama_progress = p
	var message := String(chosen.get("result", "这一页翻过去了。"))
	if finished:
		message += "\n【本幕完成】" + _reward_text(reward)
	return {"ok": true, "message": message, "finished": finished,
		"reward": reward, "node": current_node(state, act_id)}

static func _grant_reward(state: GameState, act: Dictionary) -> Dictionary:
	var spec: Dictionary = act.get("reward", {})
	var gold := int(spec.get("gold", 0))
	if gold > 0:
		state.player.gold += gold
	var items: Dictionary = spec.get("items", {})
	for item_id in items.keys():
		state.player.inventory[String(item_id)] = \
			int(state.player.inventory.get(String(item_id), 0)) + int(items[item_id])
	var rep := int(spec.get("reputation", 0))
	_progress(state)["reputation"] = int(_progress(state).get("reputation", 0)) + rep
	return {"gold": gold, "items": items.duplicate(true), "reputation": rep}

static func _reward_text(reward: Dictionary) -> String:
	var parts: Array = []
	var gold := int(reward.get("gold", 0))
	if gold > 0:
		parts.append("%d 文钱" % gold)
	var items: Dictionary = reward.get("items", {})
	for item_id in items.keys():
		var item := ItemDatabase.get_item(String(item_id))
		parts.append("%s×%d" % [item.get("name", item_id), int(items[item_id])])
	var rep := int(reward.get("reputation", 0))
	if rep > 0:
		parts.append("公演评价 +%d" % rep)
	return "、".join(parts) if not parts.is_empty() else "戏页已收好"

static func reputation(state: GameState) -> int:
	return int(_progress(state).get("reputation", 0))

static func all_completed(state: GameState) -> bool:
	for act in all_acts():
		if not is_completed(state, String(act.get("id", ""))):
			return false
	return not all_acts().is_empty()

static func ending(state: GameState) -> Dictionary:
	_ensure_loaded()
	if not all_completed(state):
		return {}
	var rep := reputation(state)
	var list: Array = _data.get("endings", [])
	list.sort_custom(func(a, b): return int(a.get("min_reputation", 0)) > int(b.get("min_reputation", 0)))
	for ending_data in list:
		if rep >= int(ending_data.get("min_reputation", 0)):
			return ending_data.duplicate(true)
	return list.back().duplicate(true) if not list.is_empty() else {}

static func completed_count(state: GameState) -> int:
	return Array(_progress(state).get("acts_completed", [])).size()
