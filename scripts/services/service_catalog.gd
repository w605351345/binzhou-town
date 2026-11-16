extends RefCounted
class_name ServiceCatalog

const PATH := "res://data/services.json"
static var _data: Dictionary = {}
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("服务数据不存在: %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_data = parsed

static func fishmonger() -> Dictionary:
	_ensure_loaded()
	return Dictionary(_data.get("fishmonger", {})).duplicate(true)

static func merchant_stock(state: GameState) -> Array:
	_ensure_loaded()
	var cfg: Dictionary = _data.get("merchant", {})
	var pool: Array = cfg.get("pool", [])
	if pool.is_empty():
		return []
	var day := state.calendar.abs_day() if state != null else 0
	var rng := RandomNumberGenerator.new()
	rng.seed = day * 1297 + 4411
	var candidates := pool.duplicate()
	var out: Array = []
	var size := mini(int(cfg.get("stock_size", 3)), candidates.size())
	var markup := float(cfg.get("markup", 1.25))
	for _i in size:
		var idx := rng.randi_range(0, candidates.size() - 1)
		var item_id := String(candidates[idx])
		candidates.remove_at(idx)
		var item := ItemDatabase.get_item(item_id)
		if item.is_empty():
			continue
		out.append({
			"item_id": item_id,
			"name": String(item.get("name", item_id)),
			"price": maxi(1, int(round(float(item.get("buy_price", 1)) * markup))),
			"desc": String(item.get("desc", "")),
		})
	return out

static func buy_merchant_item(state: GameState, item_id: String) -> Dictionary:
	if state == null:
		return {"ok": false, "message": "货郎不在。"}
	var entry: Dictionary = {}
	for candidate in merchant_stock(state):
		if String(candidate.get("item_id", "")) == item_id:
			entry = candidate
			break
	if entry.is_empty():
		return {"ok": false, "message": "今天的担子里没有这件货。"}
	var price := int(entry.get("price", 0))
	if state.player.gold < price:
		return {"ok": false, "message": "钱不够，货郎也不赊账。"}
	state.player.gold -= price
	state.player.inventory[item_id] = int(state.player.inventory.get(item_id, 0)) + 1
	QuestSystem.progress(state, "merchant_buy", 1)
	return {"ok": true, "message": "买了%s，花了 %d 文。" % [entry.get("name", item_id), price]}

static func buy_bait(state: GameState) -> Dictionary:
	var cfg := fishmonger()
	var item_id := String(cfg.get("bait_item", "bait_worm"))
	var bundle := int(cfg.get("bundle", 5))
	var price := int(cfg.get("bundle_price", 12))
	if state.player.gold < price:
		return {"ok": false, "message": "钱不够，一包鱼饵 %d 文。" % price}
	state.player.gold -= price
	state.player.inventory[item_id] = int(state.player.inventory.get(item_id, 0)) + bundle
	return {"ok": true, "message": "买了 %d 个鱼饵，花了 %d 文。" % [bundle, price]}

static func sell_fish(state: GameState) -> Dictionary:
	var cfg := fishmonger()
	var ratio := float(cfg.get("fish_buy_ratio", 0.82))
	var total := 0
	var sold: Array = []
	for raw_id in state.player.inventory.keys():
		var item_id := String(raw_id)
		if not item_id.begins_with("fish_"):
			continue
		var count := int(state.player.inventory[raw_id])
		if count <= 0:
			continue
		var unit := maxi(1, int(round(float(ItemDatabase.get_item(item_id).get("sell_price", 0)) * ratio)))
		var subtotal := unit * count
		total += subtotal
		sold.append("%s×%d" % [ItemDatabase.get_item(item_id).get("name", item_id), count])
		state.player.inventory.erase(raw_id)
	if total <= 0:
		return {"ok": false, "message": "鱼篓里没有能卖的鱼。"}
	state.player.gold += total
	SkillSystem.add_xp(state.player, "fishing", 4)
	return {"ok": true, "total": total,
		"message": "何水根把%s过了秤，给你 %d 文。" % ["、".join(sold), total]}
