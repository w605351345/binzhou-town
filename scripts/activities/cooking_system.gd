extends RefCounted
class_name CookingSystem

const RECIPES_PATH := "res://data/recipes.json"
static var _recipes: Array = []
static var _by_id: Dictionary = {}
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(RECIPES_PATH, FileAccess.READ)
	if f == null:
		push_error("菜谱数据不存在: %s" % RECIPES_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_recipes = Array(parsed.get("recipes", []))
		for recipe in _recipes:
			_by_id[String(recipe.get("id", ""))] = recipe

static func all_recipes() -> Array:
	_ensure_loaded()
	return _recipes.duplicate(true)

static func get_recipe(recipe_id: String) -> Dictionary:
	_ensure_loaded()
	var recipe: Variant = _by_id.get(recipe_id, {})
	return recipe.duplicate(true) if recipe is Dictionary else {}

static func can_cook(state: GameState, recipe_id: String) -> bool:
	var recipe := get_recipe(recipe_id)
	if recipe.is_empty() or state == null:
		return false
	for need in recipe.get("ingredients", []):
		if int(state.player.inventory.get(String(need.get("id", "")), 0)) \
				< int(need.get("count", 1)):
			return false
	return true

static func cook(state: GameState, recipe_id: String) -> Dictionary:
	var recipe := get_recipe(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "message": "没有这道菜谱"}
	if not can_cook(state, recipe_id):
		return {"ok": false, "message": "材料不够，先看看缺什么"}
	for need in recipe.get("ingredients", []):
		var item_id := String(need.get("id", ""))
		state.player.inventory[item_id] = int(state.player.inventory.get(item_id, 0)) \
			- int(need.get("count", 1))
		if int(state.player.inventory[item_id]) <= 0:
			state.player.inventory.erase(item_id)
	var result_id := String(recipe.get("result", ""))
	state.player.inventory[result_id] = int(state.player.inventory.get(result_id, 0)) + 1
	var energy := int(recipe.get("energy", 0))
	if state.player.stamina != null and energy > 0:
		state.player.stamina.restore(energy)
	QuestSystem.progress(state, "cook", 1)
	return {
		"ok": true, "result_id": result_id,
		"name": String(recipe.get("name", result_id)),
		"energy": energy,
		"message": "做好了%s，热乎着。" % recipe.get("name", result_id),
	}
