extends RefCounted
class_name ShippingSystem

## 农场运输箱：把东西放进去，睡一觉后按售价结算金币。
## 与直接卖给收购商不同，运输箱适合批量出货。

static func ensure_state(state: GameState) -> void:
	if state == null:
		return
	if state.shipping == null or not state.shipping is Dictionary:
		state.shipping = {}
	if not state.shipping.get("items", {}) is Dictionary:
		state.shipping["items"] = {}
	if not state.shipping.has("last_payout"):
		state.shipping["last_payout"] = 0
	if not state.shipping.has("lifetime"):
		state.shipping["lifetime"] = 0
	if not state.shipping.has("last_report"):
		state.shipping["last_report"] = []

static func unit_price(state: GameState, item_id: String) -> int:
	var crop := CropDatabase.get_crop(item_id)
	if crop != null:
		var bonus := SkillSystem.crop_value_multiplier(state.player) if state != null else 1.0
		return int(round(float(crop.sell_price) * bonus))
	var item := ItemDatabase.get_item(item_id)
	return maxi(0, int(item.get("sell_price", 0)))

static func display_name(item_id: String) -> String:
	var crop := CropDatabase.get_crop(item_id)
	if crop != null:
		return crop.name
	var item := ItemDatabase.get_item(item_id)
	return String(item.get("name", item_id)) if not item.is_empty() else item_id

static func can_ship(state: GameState, item_id: String) -> bool:
	return unit_price(state, item_id) > 0

static func add(state: GameState, item_id: String, count: int = 1) -> Dictionary:
	ensure_state(state)
	if count <= 0:
		return {"ok": false, "message": "得放点东西进去。"}
	if not can_ship(state, item_id):
		return {"ok": false, "message": "这东西运输箱不收。"}
	var have := int(state.player.inventory.get(item_id, 0))
	if have < count:
		return {"ok": false, "message": "背包里没有那么多。"}
	state.player.inventory[item_id] = have - count
	if int(state.player.inventory[item_id]) <= 0:
		state.player.inventory.erase(item_id)
	state.shipping["items"][item_id] = int(state.shipping["items"].get(item_id, 0)) + count
	return {
		"ok": true, "item_id": item_id, "count": count,
		"message": "放进去 %d 个%s，明早结算。" % [count,
			display_name(item_id)],
	}

static func settle(state: GameState) -> Dictionary:
	ensure_state(state)
	var items: Dictionary = state.shipping.get("items", {})
	if items.is_empty():
		state.shipping["last_payout"] = 0
		state.shipping["last_report"] = []
		return {"ok": false, "total": 0, "items": [], "message": "运输箱里空着。"}
	var total := 0
	var report: Array = []
	for raw_id in items.keys():
		var item_id := String(raw_id)
		var count := int(items[raw_id])
		var unit := unit_price(state, item_id)
		if count <= 0 or unit <= 0:
			continue
		var subtotal := unit * count
		total += subtotal
		report.append({"item_id": item_id, "name": display_name(item_id),
			"count": count, "unit_price": unit,
			"total": subtotal})
	state.player.gold += total
	state.shipping["items"] = {}
	state.shipping["last_payout"] = total
	state.shipping["last_report"] = report
	state.shipping["lifetime"] = int(state.shipping.get("lifetime", 0)) + total
	if total > 0:
		SkillSystem.add_xp(state.player, "farming", 3)
	return {
		"ok": total > 0, "total": total, "items": report,
		"message": "运输箱结算：%d 文已记到账上。" % total if total > 0 else "运输箱里没有能卖的东西。",
	}

static func pending_value(state: GameState) -> int:
	ensure_state(state)
	var total := 0
	for raw_id in state.shipping.get("items", {}).keys():
		total += unit_price(state, String(raw_id)) * int(state.shipping["items"][raw_id])
	return total
