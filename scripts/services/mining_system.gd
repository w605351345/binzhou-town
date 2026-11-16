extends RefCounted
class_name MiningSystem

const PATH := "res://data/mine.json"
static var _floors: Array = []
static var _by_floor: Dictionary = {}
static var _max_floor := 8
static var _base_monster_chance := 0.24
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("矿洞数据不存在: %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_floors = Array(parsed.get("floors", []))
	_max_floor = int(parsed.get("max_floor", _max_floor))
	_base_monster_chance = float(parsed.get("base_monster_chance", _base_monster_chance))
	for raw in _floors:
		if raw is Dictionary:
			_by_floor[int(raw.get("floor", 0))] = raw

static func floor_data(floor_no: int) -> Dictionary:
	_ensure_loaded()
	var raw: Variant = _by_floor.get(clampi(floor_no, 1, _max_floor), {})
	return raw.duplicate(true) if raw is Dictionary else {}

static func all_floors() -> Array:
	_ensure_loaded()
	return _floors.duplicate(true)

static func ensure_state(state: GameState) -> void:
	if state == null:
		return
	if state.mine == null or not state.mine is Dictionary:
		state.mine = {}
	var defaults := {
		"floor": 1, "deepest": 1, "active": false, "ore_mined": 0,
		"monsters_defeated": 0, "visits": 0, "health": 100, "max_health": 100,
		"monster": {},
	}
	for key in defaults:
		if not state.mine.has(key):
			state.mine[key] = defaults[key]

static func enter(state: GameState) -> Dictionary:
	ensure_state(state)
	state.mine["active"] = true
	if int(state.mine.get("health", 0)) <= 0:
		state.mine["health"] = 35
	return {"ok": true, "floor": int(state.mine["floor"]),
		"message": "矿灯一亮，冷气从石缝里钻出来。"}

static func explore(state: GameState) -> Dictionary:
	ensure_state(state)
	if not bool(state.mine.get("active", false)):
		return {"ok": false, "message": "先点灯进洞。"}
	if not Dictionary(state.mine.get("monster", {})).is_empty():
		return {"ok": false, "message": "前头还有东西守着，得先把它赶开。"}
	if not state.player.stamina.consume(4):
		return {"ok": false, "message": "胳膊抬不动了，得先歇口气。"}
	var floor_no := int(state.mine.get("floor", 1))
	var floor := floor_data(floor_no)
	if floor.is_empty():
		return {"ok": false, "message": "这一层没有路了。"}
	state.mine["visits"] = int(state.mine.get("visits", 0)) + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = state.calendar.abs_day() * 1543 + floor_no * 97 \
		+ int(state.mine.get("visits", 0)) * 13
	var options: Array = floor.get("ores", [])
	var chosen: Dictionary = options[0] if not options.is_empty() else {}
	var total := 0
	for raw in options:
		total += int(raw.get("weight", 1))
	var pick := rng.randi_range(1, maxi(1, total))
	var cursor := 0
	for raw in options:
		cursor += int(raw.get("weight", 1))
		if pick <= cursor:
			chosen = raw
			break
	if chosen.is_empty():
		return {"ok": false, "message": "镐尖碰上硬岩，只崩出一星白印。"}
	var item_id := String(chosen.get("id", ""))
	var count := rng.randi_range(int(chosen.get("min", 1)), int(chosen.get("max", 1)))
	count += 1 if SkillSystem.level(state.player, "mining") >= 6 else 0
	state.player.inventory[item_id] = int(state.player.inventory.get(item_id, 0)) + count
	state.mine["ore_mined"] = int(state.mine.get("ore_mined", 0)) + count
	SkillSystem.add_xp(state.player, "mining", 5)
	var monster := Dictionary(floor.get("monster", {})).duplicate(true)
	var monster_chance := _base_monster_chance + float(floor_no - 1) * 0.025
	var encountered := not monster.is_empty() and rng.randf() < monster_chance
	if encountered:
		monster["hp"] = int(monster.get("hp", 20))
		monster["max_hp"] = int(monster.get("hp", 20))
		state.mine["monster"] = monster
	var item_name := String(ItemDatabase.get_item(item_id).get("name", item_id))
	return {
		"ok": true, "item_id": item_id, "count": count, "monster": encountered,
		"message": "凿下%s ×%d。%s" % [item_name, count,
			"石壁后传来爪子刮擦声。" if encountered else "洞里暂时安静。"],
	}

static func attack(state: GameState) -> Dictionary:
	ensure_state(state)
	var monster: Dictionary = state.mine.get("monster", {})
	if monster.is_empty():
		return {"ok": false, "message": "眼前没有要打的东西。"}
	if not state.player.stamina.consume(3):
		return {"ok": false, "message": "没力气抡镐了。"}
	var tool_level := int(state.player.tool_levels.get("pickaxe", 1))
	var damage := 8 + SkillSystem.mining_damage_bonus(state.player) + (tool_level - 1) * 4
	monster["hp"] = int(monster.get("hp", 1)) - damage
	if int(monster["hp"]) > 0:
		var incoming := int(monster.get("damage", 5))
		state.mine["health"] = maxi(0, int(state.mine.get("health", 100)) - incoming)
		state.mine["monster"] = monster
		SkillSystem.add_xp(state.player, "mining", 2)
		if int(state.mine["health"]) <= 0:
			return _collapse(state, "%s扑上来。你眼前一黑，醒来时已经躺在洞口。" % monster.get("name", "野兽"))
		return {"ok": true, "monster": monster, "damage": damage, "incoming": incoming,
			"message": "砸中%s %d 点，它回身挠了你 %d 点。" % [
				monster.get("name", "野兽"), damage, incoming]}
	state.mine["monster"] = {}
	state.mine["monsters_defeated"] = int(state.mine.get("monsters_defeated", 0)) + 1
	state.mine["health"] = mini(int(state.mine.get("max_health", 100)),
		int(state.mine.get("health", 100)) + 4)
	SkillSystem.add_xp(state.player, "mining", 12)
	return {"ok": true, "defeated": true,
		"message": "%s瘫在石堆边，矿洞又静下来。" % monster.get("name", "野兽")}

static func descend(state: GameState) -> Dictionary:
	ensure_state(state)
	if not Dictionary(state.mine.get("monster", {})).is_empty():
		return {"ok": false, "message": "先清开路，再往下走。"}
	var floor_no := int(state.mine.get("floor", 1))
	if floor_no >= _max_floor:
		return {"ok": false, "message": "最深处只剩一扇石门，眼下还推不开。"}
	floor_no += 1
	state.mine["floor"] = floor_no
	state.mine["deepest"] = maxi(int(state.mine.get("deepest", 1)), floor_no)
	SkillSystem.add_xp(state.player, "mining", 8)
	var floor := floor_data(floor_no)
	return {"ok": true, "floor": floor_no,
		"message": "沿着湿滑的台阶下到第 %d 层：%s。" % [floor_no, floor.get("name", "更深处")]}

static func retreat(state: GameState) -> Dictionary:
	ensure_state(state)
	state.mine["active"] = false
	state.mine["monster"] = {}
	return {"ok": true, "message": "你收起矿灯，顺着风往洞口走。"}

static func heal(state: GameState, amount: int) -> void:
	ensure_state(state)
	state.mine["health"] = mini(int(state.mine.get("max_health", 100)),
		int(state.mine.get("health", 100)) + amount)

static func summary(state: GameState) -> String:
	ensure_state(state)
	var floor_no := int(state.mine.get("floor", 1))
	var floor := floor_data(floor_no)
	return "第%d层 · %s | 生命 %d/%d | 最深 %d 层 | 矿石 %d" % [
		floor_no, floor.get("name", "矿洞"), int(state.mine.get("health", 100)),
		int(state.mine.get("max_health", 100)), int(state.mine.get("deepest", 1)),
		int(state.mine.get("ore_mined", 0))]

static func _collapse(state: GameState, message: String) -> Dictionary:
	state.mine["health"] = 30
	state.mine["floor"] = 1
	state.mine["active"] = false
	state.mine["monster"] = {}
	state.player.stamina.energy = mini(state.player.stamina.energy, 35)
	return {"ok": false, "collapsed": true, "message": message}
