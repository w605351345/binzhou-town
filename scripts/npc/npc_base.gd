extends RefCounted
class_name NpcBase

## NPC 基类(纯逻辑,可 headless 单测)
##
## 宾州镇的人物。MVP 只有张晓芳一人,先把结构立住,
## 后续加人物时只继承本类。对话内容统一放在 data/dialogues.json。

var id: String = ""
var name: String = ""
var position: Vector2 = Vector2.ZERO
## 每日所在位置(定时换位)
var daily_positions: Array = []
## 当前是第几天(用于换位)
var current_day: int = 0
## 好感度
var affection: int = 0
## 是否收购玩家作物
var buys_crops: bool = false
## 收购价倍率(1.0 = 原价)
var buy_ratio: float = 1.0

func _init(p_id: String = "", p_name: String = "") -> void:
	id = p_id
	name = p_name

## 今日所在位置
func today_position() -> Vector2:
	if daily_positions.is_empty():
		return position
	var idx := current_day % daily_positions.size()
	return daily_positions[idx]

## 跨天:换位
func on_day_changed(day: int) -> void:
	current_day = day

## 收购作物。返回 {ok, message, total}
func buy_crop(player: PlayerProfile, crop_id: String, amount: int) -> Dictionary:
	if not buys_crops:
		return {"ok": false, "message": "%s不收庄稼" % name, "total": 0}
	var crop := CropDatabase.get_crop(crop_id)
	if crop == null:
		return {"ok": false, "message": "没有这种庄稼", "total": 0}
	var have := int(player.inventory.get(crop_id, 0))
	if have < amount or amount <= 0:
		return {"ok": false, "message": "你手里没有那么多%s" % crop.name, "total": 0}
	var price := int(round(float(crop.sell_price) * buy_ratio))
	var total := price * amount
	player.inventory[crop_id] = have - amount
	player.gold += total
	return {
		"ok": true,
		"message": "%s收了%d个%s,给你%d文钱" % [name, amount, crop.name, total],
		"total": total,
	}

func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "position": position,
		"current_day": current_day, "affection": affection,
	}

static func from_dict(d: Dictionary) -> NpcBase:
	var n := NpcBase.new(String(d.get("id", "")), String(d.get("name", "")))
	n.position = d.get("position", Vector2.ZERO)
	n.current_day = int(d.get("current_day", 0))
	n.affection = int(d.get("affection", 0))
	return n
