extends RefCounted
class_name StaminaSystem

## 体力系统(纯逻辑,可 headless 单测)
##
## 西境农庄设定:一天能完成一小片田的照料,但干不完整个农场。
## 数值按 100 体力、晴朗天气给出清晰预算:约 14 次翻土,或 30 次浇水。
## 界面会在靠近地块时显示当前动作与体力是否足够。

const MAX_ENERGY := 100

## 各类农活的体力消耗
const COST_TILL := 7          # 翻土
const COST_WATER := 3         # 浇水
const COST_PLANT := 2         # 播种
const COST_HARVEST := 4       # 收获
const COST_AUTUMN_PLOUGH := 10 # 深翻养地(最累)
const COST_INTERACT := 0      # 对话/商店不耗体力

## 兼容旧存档常量。体力上限就是 100,不再做 110 的隐藏溢出,
## 否则 HUD 会出现"110/100"这种自相矛盾的读数。
const OVERFLOW_MAX := MAX_ENERGY

var energy: int = MAX_ENERGY

func _init(p_energy: int = MAX_ENERGY) -> void:
	energy = clampi(p_energy, 0, OVERFLOW_MAX)

## 是否还有足够体力
func has(cost: int) -> bool:
	return energy >= cost

## 消耗体力。体力不足返回 false。
func consume(cost: int) -> bool:
	if cost <= 0:
		return true
	if not has(cost):
		return false
	energy -= cost
	return true

## 睡一夜:回满
func sleep() -> void:
	energy = MAX_ENERGY

## 恢复指定量(不超上限)
func restore(amount: int) -> void:
	energy = clampi(energy + amount, 0, MAX_ENERGY)

## 当前体力的中文描述
func status_cn() -> String:
	if energy <= 0:
		return "筋疲力尽"
	if energy < 30:
		return "有些乏了"
	if energy < 60:
		return "还行"
	if energy < 90:
		return "有劲"
	return "精神头足"
