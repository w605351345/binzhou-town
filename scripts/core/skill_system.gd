extends RefCounted
class_name SkillSystem

## 七项生活技能。等级写入 PlayerProfile.skills，经验写入 skill_xp，
## 两者都随存档保存；旧档只有等级时按 0 经验补齐，不会丢进度。

const PATH := "res://data/skills.json"
static var _skills: Array = []
static var _by_id: Dictionary = {}
static var _level_xp: Array = [0, 0, 100, 250, 450, 700, 1000, 1400, 1900, 2500, 3200]
static var _max_level := 10
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("技能数据不存在: %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_skills = Array(parsed.get("skills", []))
	_level_xp = Array(parsed.get("level_xp", _level_xp))
	_max_level = int(parsed.get("max_level", _max_level))
	for raw in _skills:
		if raw is Dictionary:
			_by_id[String(raw.get("id", ""))] = raw

static func all_skills() -> Array:
	_ensure_loaded()
	return _skills.duplicate(true)

static func skill_ids() -> Array:
	_ensure_loaded()
	return _by_id.keys()

static func skill_name(skill_id: String) -> String:
	_ensure_loaded()
	return String(Dictionary(_by_id.get(skill_id, {})).get("name", skill_id))

static func max_level() -> int:
	_ensure_loaded()
	return _max_level

static func ensure_player(player: PlayerProfile) -> void:
	if player == null:
		return
	_ensure_loaded()
	if player.skills == null or not player.skills is Dictionary:
		player.skills = {}
	if player.skill_xp == null or not player.skill_xp is Dictionary:
		player.skill_xp = {}
	for raw in _skills:
		var id := String(raw.get("id", ""))
		if id == "":
			continue
		if not player.skills.has(id):
			player.skills[id] = 1
		else:
			player.skills[id] = clampi(int(player.skills[id]), 1, _max_level)
		if not player.skill_xp.has(id):
			player.skill_xp[id] = 0
		else:
			player.skill_xp[id] = maxi(0, int(player.skill_xp[id]))

static func level(player: PlayerProfile, skill_id: String) -> int:
	ensure_player(player)
	return clampi(int(player.skills.get(skill_id, 1)), 1, _max_level)

static func xp(player: PlayerProfile, skill_id: String) -> int:
	ensure_player(player)
	return maxi(0, int(player.skill_xp.get(skill_id, 0)))

static func xp_for_level(target_level: int) -> int:
	_ensure_loaded()
	var level_index := clampi(target_level, 1, _max_level)
	if level_index < _level_xp.size():
		return int(_level_xp[level_index])
	return int(_level_xp.back()) if not _level_xp.is_empty() else 0

static func xp_to_next(player: PlayerProfile, skill_id: String) -> int:
	var current := level(player, skill_id)
	if current >= _max_level:
		return 0
	return maxi(0, xp_for_level(current + 1) - xp(player, skill_id))

static func add_xp(player: PlayerProfile, skill_id: String, amount: int) -> Dictionary:
	ensure_player(player)
	if player == null or amount <= 0 or not player.skills.has(skill_id):
		return {"ok": false, "level": level(player, skill_id), "level_up": false, "message": ""}
	var before := level(player, skill_id)
	var total := xp(player, skill_id) + amount
	var current := before
	while current < _max_level and total >= xp_for_level(current + 1):
		current += 1
	player.skill_xp[skill_id] = total
	player.skills[skill_id] = current
	var message := "+%d %s经验" % [amount, skill_name(skill_id)]
	if current > before:
		message = "%s升到 %d 级！%s" % [skill_name(skill_id), current, message]
	return {
		"ok": true, "xp": total, "level": current, "level_up": current > before,
		"message": message,
	}

static func crop_value_multiplier(player: PlayerProfile) -> float:
	return 1.0 + minf(0.20, float(level(player, "farming") - 1) * 0.02)

static func social_talk_bonus(player: PlayerProfile) -> int:
	return 1 if level(player, "social") >= 5 else 0

static func mining_damage_bonus(player: PlayerProfile) -> int:
	return (level(player, "mining") - 1) * 2

static func extra_product_chance(player: PlayerProfile, skill_id: String) -> float:
	return minf(0.35, float(level(player, skill_id) - 1) * 0.03)

static func summary(player: PlayerProfile) -> String:
	ensure_player(player)
	var parts: Array = []
	for skill_id in ["farming", "ranching", "mining", "crafting", "fishing", "foraging", "social"]:
		if player.skills.has(skill_id):
			parts.append("%s %d" % [skill_name(skill_id), level(player, skill_id)])
	return " · ".join(parts)
