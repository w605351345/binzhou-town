extends RefCounted
class_name NpcBase

## NPC 基类(纯逻辑,可 headless 单测)
##
## 宾州镇的人物。MVP 只有张晓芳一人,先把结构立住,
## 后续加人物时只继承本类。对话内容统一放在 data/dialogues.json。

var id: String = ""
var name: String = ""
var title: String = ""
var gender: String = "unspecified"
var age: int = 0
var birthday_month: int = 1
var birthday_day: int = 1
var sprite_path: String = ""
var winter_sprite_path: String = ""
var portrait_path: String = ""
var home_location: String = ""
var home_position: Vector2 = Vector2.ZERO
var likes: Array = []
var dislikes: Array = []
var schedule: Array = []
var activity: String = ""
var schedule_available: bool = true
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
var affection_max: int = 100

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

## 冬季使用更厚的棉袄差分；缺图时回退到常服。
func sprite_path_for(season: String) -> String:
	if season == "winter" and winter_sprite_path != "":
		return winter_sprite_path
	return sprite_path

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
	var price := int(round(float(crop.sell_price) * effective_ratio()))
	var total := price * amount
	player.inventory[crop_id] = have - amount
	player.gold += total
	return {
		"ok": true,
		"message": "%s收了%d个%s,给你%d文钱" % [name, amount, crop.name, total],
		"total": total,
	}

## 好感度会一点点抬高收购价，但最多只到市价。
func effective_ratio() -> float:
	return minf(buy_ratio + minf(float(affection) * 0.01, 0.1), 1.0)

static func from_data(data: Dictionary) -> NpcBase:
	var n := NpcBase.new(String(data.get("id", "")), String(data.get("name", "")))
	n.title = String(data.get("title", ""))
	n.gender = String(data.get("gender", "unspecified"))
	n.age = int(data.get("age", 0))
	n.birthday_month = int(data.get("birthday_month", 1))
	n.birthday_day = int(data.get("birthday_day", 1))
	n.sprite_path = String(data.get("sprite_path", ""))
	n.winter_sprite_path = String(data.get("winter_sprite_path", ""))
	n.portrait_path = String(data.get("portrait_path", ""))
	n.home_location = String(data.get("home_location", ""))
	var home: Array = data.get("home_position", [0, 0])
	n.home_position = Vector2(float(home[0]), float(home[1]))
	n.likes = Array(data.get("likes", [])).duplicate()
	n.dislikes = Array(data.get("dislikes", [])).duplicate()
	n.schedule = Array(data.get("schedules", [])).duplicate(true)
	n.buys_crops = bool(data.get("buys_crops", false))
	n.buy_ratio = float(data.get("buy_ratio", 1.0))
	n.affection_max = int(data.get("affection_max", 100))
	return n

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
