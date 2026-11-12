extends RefCounted
class_name StaminaSystem

## 体力系统(纯逻辑,可 headless 单测)
##
## 黑龙江设定:春播秋收是重体力活,一天干不动太多活。
## 每种农活消耗不同体力,体力耗尽当天干不动 —— 这是"一年一熟"之外的第二层节奏压力。
## 夜间休息回满,并额外回复一点(黑龙江农忙季睡得早,但也起得早)。

const MAX_ENERGY := 100

## 各类农活的体力消耗
const COST_TILL := 4          # 翻土
const COST_WATER := 2         # 浇水
const COST_PLANT := 1         # 播种
const COST_HARVEST := 3       # 收获
const COST_AUTUMN_PLOUGH := 6 # 秋翻地(深翻,最累)
const COST_INTERACT := 0      # 对话/商店不耗体力

## 睡一夜的回复量:回满 + 少量溢出(上限 110)
const OVERFLOW_MAX := 110

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

## 睡一夜:回满并给予少量溢出
func sleep() -> void:
	energy = OVERFLOW_MAX

## 恢复指定量(不超上限)
func restore(amount: int) -> void:
	energy = clampi(energy + amount, 0, OVERFLOW_MAX)

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
