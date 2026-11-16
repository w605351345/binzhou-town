extends RefCounted
class_name InteractionSystem

## 主角与 NPC 的距离判定(纯逻辑,可 headless 单测)
##
## E 键交互的判定依据:在半径内且大致朝向该 NPC。
## 半径用像素,MVP 取 72(约 1.5 个身位)。

const DEFAULT_RANGE := 72.0
## 朝向容差(度)。90 = 正前方象限。
const DEFAULT_FACING_TOLERANCE := 100.0

## 判断是否可交互。npc_pos 为 NPC 世界坐标。
static func can_interact(player_pos: Vector2, facing: Vector2, npc_pos: Vector2,
		interact_range: float = DEFAULT_RANGE,
		facing_tolerance: float = DEFAULT_FACING_TOLERANCE) -> bool:
	var to_npc := npc_pos - player_pos
	if to_npc.length() > interact_range:
		return false
	# 距离过近时不做朝向判定,避免"贴脸反而不能交互"
	if to_npc.length() < 8.0:
		return true
	var f := facing.normalized()
	if f == Vector2.ZERO:
		return true
	var angle := rad_to_deg(f.angle_to(to_npc))
	return absf(angle) <= facing_tolerance * 0.5

## 从候选列表中选出最佳交互目标(最近且在朝向内)。返回索引,无则 -1。
static func find_target(player_pos: Vector2, facing: Vector2, targets: Array,
		interact_range: float = DEFAULT_RANGE,
		facing_tolerance: float = DEFAULT_FACING_TOLERANCE) -> int:
	var best := -1
	var best_dist := INF
	for i in targets.size():
		var t: Dictionary = targets[i]
		var pos: Vector2 = t.get("position", Vector2.ZERO)
		if not can_interact(player_pos, facing, pos, interact_range, facing_tolerance):
			continue
		var d := player_pos.distance_to(pos)
		if d < best_dist:
			best_dist = d
			best = i
	return best

## 最近可交互目标,不要求玩家精确朝向。
## 小镇里的 E/A 是"靠近就能搭话",不是动作游戏里的正面判定;
## 旧版 100° 朝向门槛导致玩家贴着 NPC 按 E 仍然得到"附近没东西"。
static func find_nearest(player_pos: Vector2, targets: Array,
		interact_range: float = DEFAULT_RANGE) -> int:
	var best := -1
	var best_dist := INF
	for i in targets.size():
		var t: Dictionary = targets[i]
		var pos: Vector2 = t.get("position", Vector2.ZERO)
		var d := player_pos.distance_to(pos)
		if d <= interact_range and d < best_dist:
			best_dist = d
			best = i
	return best
