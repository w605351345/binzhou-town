extends RefCounted
class_name CraftingSystem

const PATH := "res://data/crafting.json"
static var _recipes: Array = []
static var _by_id: Dictionary = {}
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("制造数据不存在: %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_recipes = Array(parsed.get("recipes", []))
	for raw in _recipes:
		if raw is Dictionary:
			_by_id[String(raw.get("id", ""))] = raw

static func all_recipes() -> Array:
	_ensure_loaded()
	return _recipes.duplicate(true)

static func get_recipe(recipe_id: String) -> Dictionary:
	_ensure_loaded()
	var raw: Variant = _by_id.get(recipe_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}

static func can_craft(state: GameState, recipe_id: String) -> bool:
	var recipe := get_recipe(recipe_id)
	if state == null or recipe.is_empty():
		return false
	if not station_available(state, String(recipe.get("station", "workbench"))):
		return false
	var skill_id := String(recipe.get("skill", "crafting"))
	if SkillSystem.level(state.player, skill_id) < int(recipe.get("skill_level", 1)):
		return false
	for raw_id in Dictionary(recipe.get("ingredients", {})).keys():
		if int(state.player.inventory.get(String(raw_id), 0)) \
				< int(recipe["ingredients"][raw_id]):
			return false
	return true

static func station_available(state: GameState, station_id: String) -> bool:
	if station_id == "" or station_id == "workbench":
		return state != null
	return state != null and int(state.player.inventory.get(station_id, 0)) > 0

static func station_name(station_id: String) -> String:
	match station_id:
		"furnace_basic": return "小熔炉"
		"preserve_jar": return "腌渍罐"
		"placeable_chest": return "木储物箱"
		_: return "农具工作台"

static func craft(state: GameState, recipe_id: String) -> Dictionary:
	var recipe := get_recipe(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "message": "没有这张配方。"}
	if not can_craft(state, recipe_id):
		return {"ok": false, "message": "材料不够，或者手艺还没到。"}
	for raw_id in Dictionary(recipe.get("ingredients", {})).keys():
		var item_id := String(raw_id)
		var need := int(recipe["ingredients"][raw_id])
		state.player.inventory[item_id] = int(state.player.inventory.get(item_id, 0)) - need
		if int(state.player.inventory[item_id]) <= 0:
			state.player.inventory.erase(item_id)
	var result_id := String(recipe.get("result", ""))
	var count := maxi(1, int(recipe.get("count", 1)))
	var skill_id := String(recipe.get("skill", "crafting"))
	var rng := RandomNumberGenerator.new()
	rng.seed = state.calendar.abs_day() * 977 + recipe_id.hash()
	if rng.randf() < SkillSystem.extra_product_chance(state.player, skill_id):
		count += 1
	state.player.inventory[result_id] = int(state.player.inventory.get(result_id, 0)) + count
	var xp_result := SkillSystem.add_xp(state.player, skill_id, int(recipe.get("xp", 5)))
	return {
		"ok": true, "result_id": result_id, "count": count,
		"message": "做出%s ×%d。%s" % [
			String(ItemDatabase.get_item(result_id).get("name", result_id)), count,
			String(xp_result.get("message", ""))],
	}

## 每个喷灌器清早灌溉三块尚未浇过的地。
static func apply_sprinklers(state: GameState) -> int:
	if state == null:
		return 0
	var count := int(state.player.inventory.get("sprinkler_basic", 0))
	var budget := count * 3
	if budget <= 0:
		return 0
	var watered := 0
	for plot in state.farm.plots:
		if watered >= budget:
			break
		if plot.state in [FarmPlot.State.PLANTED, FarmPlot.State.GROWING, FarmPlot.State.READY] \
				and plot.water(state.calendar.abs_day()):
			watered += 1
	return watered
