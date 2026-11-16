extends RefCounted
class_name LivestockSystem

const PATH := "res://data/livestock.json"
static var _animals: Array = []
static var _by_id: Dictionary = {}
static var _feed_item := "feed_hay"
static var _feed_price := 8
static var _capacity := 8
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("畜牧数据不存在: %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_animals = Array(parsed.get("animals", []))
	_feed_item = String(parsed.get("feed_item", _feed_item))
	_feed_price = int(parsed.get("feed_price", _feed_price))
	_capacity = int(parsed.get("barn_capacity", _capacity))
	for raw in _animals:
		if raw is Dictionary:
			_by_id[String(raw.get("id", ""))] = raw

static func all_animals() -> Array:
	_ensure_loaded()
	return _animals.duplicate(true)

static func get_animal(animal_id: String) -> Dictionary:
	_ensure_loaded()
	var raw: Variant = _by_id.get(animal_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}

static func feed_item() -> String:
	_ensure_loaded()
	return _feed_item

static func feed_price() -> int:
	_ensure_loaded()
	return _feed_price

static func capacity() -> int:
	_ensure_loaded()
	return _capacity

static func ensure_state(state: GameState) -> void:
	if state == null:
		return
	if state.livestock == null or not state.livestock is Dictionary:
		state.livestock = {}
	if not state.livestock.get("animals", []) is Array:
		state.livestock["animals"] = []
	if not state.livestock.has("next_id"):
		state.livestock["next_id"] = 1
	if not state.livestock.has("lifetime_products"):
		state.livestock["lifetime_products"] = 0

static func animal_count(state: GameState) -> int:
	ensure_state(state)
	return Array(state.livestock.get("animals", [])).size()

static func buy_animal(state: GameState, animal_id: String) -> Dictionary:
	ensure_state(state)
	var data := get_animal(animal_id)
	if data.is_empty():
		return {"ok": false, "message": "牧场没有这种牲口。"}
	if animal_count(state) >= _capacity:
		return {"ok": false, "message": "棚里已经满了，先把日子过顺再说。"}
	var cost := int(data.get("cost", 0))
	if state.player.gold < cost:
		return {"ok": false, "message": "钱不够，先攒 %d 文。" % cost}
	state.player.gold -= cost
	var next_id := int(state.livestock.get("next_id", 1))
	state.livestock["next_id"] = next_id + 1
	var animal := {
		"uid": next_id, "type": animal_id,
		"name": String(data.get("name", animal_id)),
		"days_left": maxi(1, int(data.get("days", 1))),
		"fed_today": false, "lifetime": 0,
	}
	state.livestock["animals"].append(animal)
	SkillSystem.add_xp(state.player, "ranching", 8)
	return {"ok": true, "animal": animal,
		"message": "%s进了棚，先让它认认地方。" % animal["name"]}

static func buy_feed(state: GameState, count: int = 1) -> Dictionary:
	ensure_state(state)
	if count <= 0:
		return {"ok": false, "message": "买几捆？"}
	var total := _feed_price * count
	if state.player.gold < total:
		return {"ok": false, "message": "钱不够，草料 %d 文一捆。" % _feed_price}
	state.player.gold -= total
	state.player.inventory[_feed_item] = int(state.player.inventory.get(_feed_item, 0)) + count
	return {"ok": true, "count": count, "message": "买了 %d 捆草料，花了 %d 文。" % [count, total]}

static func feed_all(state: GameState) -> Dictionary:
	ensure_state(state)
	var animals: Array = state.livestock.get("animals", [])
	if animals.is_empty():
		return {"ok": false, "message": "棚里还没有牲口。"}
	var need := 0
	for raw in animals:
		var animal: Dictionary = raw
		if not bool(animal.get("fed_today", false)):
			need += 1
	if need == 0:
		return {"ok": false, "message": "今天都喂过了，让它们安生嚼草。"}
	var have := int(state.player.inventory.get(_feed_item, 0))
	if have < need:
		return {"ok": false, "message": "草料不够，还差 %d 捆。" % (need - have)}
	state.player.inventory[_feed_item] = have - need
	if int(state.player.inventory[_feed_item]) <= 0:
		state.player.inventory.erase(_feed_item)
	for raw in animals:
		var animal: Dictionary = raw
		if not bool(animal.get("fed_today", false)):
			animal["fed_today"] = true
	state.livestock["animals"] = animals
	SkillSystem.add_xp(state.player, "ranching", need * 2)
	return {"ok": true, "count": need, "message": "添了 %d 份草料，棚里安静下来。" % need}

static func advance_day(state: GameState) -> Dictionary:
	ensure_state(state)
	var animals: Array = state.livestock.get("animals", [])
	var produced: Array = []
	for raw in animals:
		var animal: Dictionary = raw
		if not bool(animal.get("fed_today", false)):
			continue
		animal["days_left"] = int(animal.get("days_left", 1)) - 1
		if int(animal["days_left"]) <= 0:
			var data := get_animal(String(animal.get("type", "")))
			if data.is_empty():
				continue
			var product_id := String(data.get("product", ""))
			var amount := 1
			var rng := RandomNumberGenerator.new()
			rng.seed = state.calendar.abs_day() * 431 + int(animal.get("uid", 0))
			if rng.randf() < SkillSystem.extra_product_chance(state.player, "ranching"):
				amount += 1
			state.player.inventory[product_id] = \
				int(state.player.inventory.get(product_id, 0)) + amount
			animal["days_left"] = maxi(1, int(data.get("days", 1)))
			animal["lifetime"] = int(animal.get("lifetime", 0)) + amount
			state.livestock["lifetime_products"] = \
				int(state.livestock.get("lifetime_products", 0)) + amount
			produced.append({"name": String(data.get("product_name", product_id)),
				"count": amount, "animal": String(animal.get("name", ""))})
		animal["fed_today"] = false
	state.livestock["animals"] = animals
	var names: Array = []
	for entry in produced:
		names.append("%s×%d" % [entry.get("name", ""), int(entry.get("count", 0))])
	return {"ok": not produced.is_empty(), "products": produced,
		"message": "棚里收了：%s。" % "、".join(names) if not names.is_empty() else "棚里今天没有新产出。"}

static func summary(state: GameState) -> String:
	ensure_state(state)
	var animals: Array = state.livestock.get("animals", [])
	if animals.is_empty():
		return "棚里还空着。"
	var parts: Array = []
	for raw in animals:
		var animal: Dictionary = raw
		parts.append("%s(%s)" % [animal.get("name", "牲口"),
			"已喂" if bool(animal.get("fed_today", false)) else "等喂"])
	return "、".join(parts)
