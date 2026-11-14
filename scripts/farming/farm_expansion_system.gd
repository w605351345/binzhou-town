extends RefCounted
class_name FarmExpansionSystem

## 木工房扩建。地图 L01 的 farm_area 是 6×4，因此农场上限 24 块。
## 扩建只增不减，旧地块对象和作物状态原样保留。

const MAX_PLOTS := 24
const STEPS := [
	{"total": 12, "gold": 120, "wood": 2, "label": "4×3"},
	{"total": 16, "gold": 240, "wood": 4, "label": "4×4"},
	{"total": 20, "gold": 400, "wood": 6, "label": "5×4"},
	{"total": 24, "gold": 600, "wood": 8, "label": "6×4"},
]

static func next_step(farm: FarmSystem) -> Dictionary:
	if farm == null:
		return {}
	for raw in STEPS:
		var step: Dictionary = raw
		if int(step.get("total", 0)) > farm.plots.size():
			return step.duplicate(true)
	return {}

## 返回 {ok, message, old_total, total, step}。材料不足时不做任何修改。
static func expand(state: GameState) -> Dictionary:
	if state == null or state.farm == null or state.player == null:
		return _fail("眼下没人能替你动工")
	var step := next_step(state.farm)
	if step.is_empty():
		return _fail("农场已经扩到地图边上了")
	var gold_cost := int(step.get("gold", 0))
	var wood_cost := int(step.get("wood", 0))
	var owned_wood := int(state.player.inventory.get("forage_wood", 0))
	if state.player.gold < gold_cost:
		return _fail("钱不够。赵长河要 %d 文，你兜里只有 %d 文" % [
			gold_cost, state.player.gold])
	if owned_wood < wood_cost:
		return _fail("木料不够。还差 %d 捆干柴" % (wood_cost - owned_wood))
	var old_total := state.farm.plots.size()
	state.player.gold -= gold_cost
	state.player.inventory["forage_wood"] = owned_wood - wood_cost
	if int(state.player.inventory["forage_wood"]) <= 0:
		state.player.inventory.erase("forage_wood")
	state.farm.ensure_size(int(step.get("total", old_total)))
	return {
		"ok": true,
		"message": "赵长河量完尺寸，把新地垄接上了。农场扩到 %s，共 %d 块地。" % [
			step.get("label", ""), state.farm.plots.size()],
		"old_total": old_total,
		"total": state.farm.plots.size(),
		"step": step,
	}

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message, "total": 0}
