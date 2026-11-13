extends RefCounted
class_name Shop

## 商店结算(纯逻辑,可 headless 自测)
##
## 张晓芳既是邻居也是收购商:买她的种子,卖自己的庄稼。
## 价格全部来自数据表(items.json / crops.json),这里只管结算 —— 钱算错了整条循环就断了。
##
## 收购价 = 作物售价 × 收购比(0.9,收购商压价)+ 好感度加成(最多 +0.1)

## 收购比默认值(与 items.json 的 crop_buy_prices 一致)
const DEFAULT_BUY_RATIO := 0.9

## 买道具(种子/工具/吃食)。返回 {ok, message, item_id, count, price, gold}
static func buy_item(player: PlayerProfile, item_id: String, count: int = 1) -> Dictionary:
	if player == null:
		return _fail("人都没有,买什么")
	if count <= 0:
		return _fail("买几个?说个正数")
	var item := ItemDatabase.get_item(item_id)
	if item.is_empty():
		return _fail("镇上没有这玩意儿")
	var price := int(item.get("buy_price", 0))
	var total := price * count
	if player.gold < total:
		return _fail("钱不够了(要 %d 文,兜里就 %d 文)" % [total, player.gold])
	player.gold -= total
	player.inventory[item_id] = int(player.inventory.get(item_id, 0)) + count
	return {
		"ok": true,
		"message": "买了 %d 个%s,花了 %d 文" % [count, item.get("name", ""), total],
		"item_id": item_id,
		"count": count,
		"price": price,
		"gold": player.gold,
	}

## 卖作物给收购商。返回 {ok, message, crop_id, amount, total}
static func sell_crop(player: PlayerProfile, npc: NpcBase, crop_id: String,
		amount: int) -> Dictionary:
	if player == null or npc == null:
		return _fail("没人收你的粮")
	if not npc.buys_crops:
		return _fail("%s不收庄稼" % npc.name)
	if amount <= 0:
		return _fail("卖几个?说个正数")
	var res := npc.buy_crop(player, crop_id, amount)
	res["crop_id"] = crop_id
	res["amount"] = amount
	return res

## 背包里能卖的作物(给商店 UI 列清单)
## npc 为空时按基础收购比算价(不含好感度加成)
static func sellable_crops(player: PlayerProfile, npc: NpcBase = null) -> Array:
	var out: Array = []
	if player == null:
		return out
	for crop_id in player.inventory.keys():
		var amount := int(player.inventory[crop_id])
		if amount <= 0:
			continue
		var crop := CropDatabase.get_crop(String(crop_id))
		if crop == null:
			continue
		var unit := unit_price(crop_id, npc)
		out.append({
			"crop_id": String(crop_id),
			"name": crop.name,
			"amount": amount,
			"unit_price": unit,
			"total": unit * amount,
		})
	return out

## 某作物的收购单价
static func unit_price(crop_id: String, npc: NpcBase = null) -> int:
	var crop := CropDatabase.get_crop(crop_id)
	if crop == null:
		return 0
	var ratio := DEFAULT_BUY_RATIO
	if npc != null:
		ratio = _effective_ratio(npc)
	return int(round(float(crop.sell_price) * ratio))

## 收购商的有效收购比(含好感度加成,最多 +0.1)
static func _effective_ratio(npc: NpcBase) -> float:
	var ratio := npc.buy_ratio
	if npc.has_method("effective_ratio"):
		ratio = float(npc.effective_ratio())
	return minf(ratio + minf(float(npc.affection) * 0.01, 0.1), 1.0)

## 商店在售清单(给商店 UI 列清单)
static func purchasable_items(player: PlayerProfile) -> Array:
	var out: Array = []
	for item in ItemDatabase.all_items():
		if not bool(item.get("mvp", true)):
			continue
		var price := int(item.get("buy_price", 0))
		out.append({
			"item_id": String(item.get("id", "")),
			"name": String(item.get("name", "")),
			"category": String(item.get("category", "")),
			"price": price,
			"desc": String(item.get("desc", "")),
			"affordable": player != null and player.gold >= price,
		})
	return out

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message, "total": 0, "gold": 0}
