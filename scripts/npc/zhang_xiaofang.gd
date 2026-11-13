extends NpcBase
class_name ZhangXiaofang

## 张晓芳 —— 镇大街上的收购大户,收购玩家的庄稼(Week 2/3)
##
## 说话带东北味儿,但每句都跟黑龙江的农时挂钩 —— 她是玩家理解"一年一熟"的活教材。
## 收购价略低于市价,给的是熟人情分;好感度高时会多给一点。

func _init() -> void:
	super("zhang_xiaofang", "张晓芳")
	buys_crops = true
	buy_ratio = 0.9
	daily_positions = [
		Vector2(380, 300),   # 早市
		Vector2(490, 320),   # 晌午
		Vector2(320, 340),   # 傍晚
	]

## 收购加成:好感度越高,给的价越好
func effective_ratio() -> float:
	return buy_ratio + minf(float(affection) * 0.01, 0.1)

func buy_crop(player: PlayerProfile, crop_id: String, amount: int) -> Dictionary:
	var crop := CropDatabase.get_crop(crop_id)
	if crop == null:
		return {"ok": false, "message": "没有这种庄稼", "total": 0}
	var have := int(player.inventory.get(crop_id, 0))
	if have < amount or amount <= 0:
		return {"ok": false, "message": "你手里没有那么多%s" % crop.name, "total": 0}
	var price := int(round(float(crop.sell_price) * effective_ratio()))
	var total := price * amount
	player.inventory[crop_id] = have - amount
	player.gold += total
	return {
		"ok": true,
		"message": "%s收了%d个%s,给你%d文钱" % [name, amount, crop.name, total],
		"total": total,
	}
