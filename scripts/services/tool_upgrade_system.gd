extends RefCounted
class_name ToolUpgradeSystem

const PATH := "res://data/tool_upgrades.json"
static var _tools: Dictionary = {}
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("工具升级数据不存在: %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for raw in Array(parsed.get("tools", [])):
		if raw is Dictionary:
			_tools[String(raw.get("id", ""))] = raw

static func all_tools() -> Array:
	_ensure_loaded()
	return _tools.values().duplicate(true)

static func get_tool(tool_id: String) -> Dictionary:
	_ensure_loaded()
	var raw: Variant = _tools.get(tool_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}

static func current_level(player: PlayerProfile, tool_id: String) -> int:
	if player == null:
		return 1
	return maxi(1, int(player.tool_levels.get(tool_id, 1)))

static func next_upgrade(player: PlayerProfile, tool_id: String) -> Dictionary:
	var tool := get_tool(tool_id)
	var level := current_level(player, tool_id)
	for raw in Array(tool.get("levels", [])):
		if int(raw.get("level", 0)) == level + 1:
			return Dictionary(raw).duplicate(true)
	return {}

static func can_upgrade(player: PlayerProfile, tool_id: String) -> bool:
	var upgrade := next_upgrade(player, tool_id)
	if upgrade.is_empty() or player == null:
		return false
	if player.gold < int(upgrade.get("cost", 0)):
		return false
	for raw_id in Dictionary(upgrade.get("ingredients", {})).keys():
		if int(player.inventory.get(String(raw_id), 0)) < int(upgrade["ingredients"][raw_id]):
			return false
	return true

static func upgrade(player: PlayerProfile, tool_id: String) -> Dictionary:
	if not can_upgrade(player, tool_id):
		return {"ok": false, "message": "钱或材料还差一点。"}
	var upgrade := next_upgrade(player, tool_id)
	player.gold -= int(upgrade.get("cost", 0))
	for raw_id in Dictionary(upgrade.get("ingredients", {})).keys():
		var item_id := String(raw_id)
		player.inventory[item_id] = int(player.inventory.get(item_id, 0)) - \
			int(upgrade["ingredients"][raw_id])
		if int(player.inventory[item_id]) <= 0:
			player.inventory.erase(item_id)
	player.tool_levels[tool_id] = int(upgrade.get("level", current_level(player, tool_id) + 1))
	SkillSystem.add_xp(player, "crafting", 20)
	return {"ok": true, "level": int(player.tool_levels[tool_id]),
		"message": "%s改成了%s。石铁山把锤子一放：拿回去试，不好使再来。" % [
			get_tool(tool_id).get("name", tool_id), upgrade.get("name", "新农具")]}
