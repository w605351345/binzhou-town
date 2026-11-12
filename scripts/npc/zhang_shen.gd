extends NpcBase
class_name ZhangShen

## 张婶 —— 镇大街上的婶子,收购玩家的庄稼(Week 2/3)
##
## 说话带东北味儿,但每句都跟黑龙江的农时挂钩 —— 她是玩家理解"一年一熟"的活教材。
## 收购价略低于市价,给的是熟人情分;好感度高时会多给一点。

func _init() -> void:
	super("zhang_shen", "张婶")
	buys_crops = true
	buy_ratio = 0.9
	daily_positions = [
		Vector2(760, 520),   # 早市
		Vector2(980, 560),   # 晌午
		Vector2(640, 620),   # 傍晚
	]

## 对话:按当前月份给出符合黑龙江农时的说法
func dialogue() -> String:
	var cal := GameCalendar.new()
	var m := cal.get_real_month()
	if m >= 11 or m <= 3:
		return "张婶:歇着吧?这节气儿啥也种不了,猫冬呢,炕上待着吧。"
	if m == 4:
		return "张婶:地化冻了,抓紧把地翻了,晚霜一过就没时候啦。"
	if m == 5:
		return "张婶:五月初头还能补种,再晚可就误了秋收喽。"
	if m <= 8:
		return "张婶:庄稼正长呢,别忘了浇水,黑土地也怕旱。"
	return "张婶:秋了,霜要下来了,赶紧收,晚收的冻地里就白瞎了。"

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
