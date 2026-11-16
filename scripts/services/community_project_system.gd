extends RefCounted
class_name CommunityProjectSystem

const PATH := "res://data/community.json"
static var _projects: Array = []
static var _by_id: Dictionary = {}
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("社区工程数据不存在: %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_projects = Array(parsed.get("projects", []))
	for raw in _projects:
		if raw is Dictionary:
			_by_id[String(raw.get("id", ""))] = raw

static func all_projects() -> Array:
	_ensure_loaded()
	return _projects.duplicate(true)

static func get_project(project_id: String) -> Dictionary:
	_ensure_loaded()
	var raw: Variant = _by_id.get(project_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}

static func ensure_state(state: GameState) -> void:
	if state == null:
		return
	if state.community == null or not state.community is Dictionary:
		state.community = {}
	if not state.community.get("progress", {}) is Dictionary:
		state.community["progress"] = {}
	if not state.community.get("completed", []) is Array:
		state.community["completed"] = []

static func is_completed(state: GameState, project_id: String) -> bool:
	ensure_state(state)
	return Array(state.community.get("completed", [])).has(project_id)

static func is_available(state: GameState, project_id: String) -> bool:
	ensure_state(state)
	var project := get_project(project_id)
	if project.is_empty() or is_completed(state, project_id):
		return false
	for required in Array(project.get("requires", [])):
		if not is_completed(state, String(required)):
			return false
	return true

static func progress_for(state: GameState, project_id: String) -> Dictionary:
	ensure_state(state)
	var all_progress: Dictionary = state.community.get("progress", {})
	var raw: Variant = all_progress.get(project_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}

static func can_donate(state: GameState, project_id: String, item_id: String) -> bool:
	if not is_available(state, project_id):
		return false
	var project := get_project(project_id)
	var needs: Dictionary = project.get("requirements", {})
	if not needs.has(item_id):
		return false
	var progress := progress_for(state, project_id)
	if int(progress.get(item_id, 0)) >= int(needs[item_id]):
		return false
	return int(state.player.inventory.get(item_id, 0)) > 0

static func donate(state: GameState, project_id: String, item_id: String) -> Dictionary:
	ensure_state(state)
	if not can_donate(state, project_id, item_id):
		return {"ok": false, "message": "这件材料现在用不上。"}
	var project := get_project(project_id)
	var needs: Dictionary = project.get("requirements", {})
	var have := int(state.player.inventory.get(item_id, 0))
	state.player.inventory[item_id] = have - 1
	if int(state.player.inventory[item_id]) <= 0:
		state.player.inventory.erase(item_id)
	var all_progress: Dictionary = state.community.get("progress", {})
	var progress := progress_for(state, project_id)
	progress[item_id] = int(progress.get(item_id, 0)) + 1
	all_progress[project_id] = progress
	state.community["progress"] = all_progress
	var done := true
	for raw_id in needs.keys():
		if int(progress.get(String(raw_id), 0)) < int(needs[raw_id]):
			done = false
			break
	if not done:
		return {"ok": true, "completed": false,
			"message": "交了 1 个%s，%s 还差一些材料。" % [
				String(ItemDatabase.get_item(item_id).get("name", item_id)),
				project.get("name", "工程")]}
	var completed: Array = state.community.get("completed", [])
	completed.append(project_id)
	state.community["completed"] = completed
	var rewards: Dictionary = project.get("rewards", {})
	state.player.gold += int(rewards.get("gold", 0))
	for reward_id in Dictionary(rewards.get("items", {})).keys():
		state.player.inventory[String(reward_id)] = \
			int(state.player.inventory.get(String(reward_id), 0)) + \
			int(rewards["items"][reward_id])
	var flag := String(rewards.get("flag", ""))
	if flag != "":
		state.flags[flag] = true
	SkillSystem.add_xp(state.player, "social", 25)
	return {"ok": true, "completed": true,
		"message": "%s完工了。镇上的人提起这事，都说是你搭的手。" % project.get("name", "工程")}

static func progress_text(state: GameState) -> String:
	ensure_state(state)
	return "公共工程 %d/%d" % [Array(state.community.get("completed", [])).size(), _projects.size()]
