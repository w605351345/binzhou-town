extends RefCounted
class_name WorldMap

## 场景边界与可行走区域(纯逻辑,可 headless 单测)
##
## MVP 用矩形边界即可;后续换 TileMap 时,把边界判定委托给地图数据源即可。
## 主角与 NPC 都通过本类裁剪位置,保证"不出地图"(Week 2 验收点)。

var bounds: Rect2 = Rect2(0, 0, 1920, 1080)

func _init(p_bounds: Rect2 = Rect2(0, 0, 1920, 1080)) -> void:
	bounds = p_bounds

## 是否在可行走区域内
func is_inside(pos: Vector2) -> bool:
	return bounds.has_point(pos)

## 裁剪到边界内
func clamp_position(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, bounds.position.x, bounds.position.x + bounds.size.x),
		clampf(pos.y, bounds.position.y, bounds.position.y + bounds.size.y)
	)

## 移动后是否越界(用于测试):判断"原始位移后的点"是否落在边界外
func would_leave(from: Vector2, delta: Vector2) -> bool:
	return not is_inside(from + delta)

## 地图中心
func center() -> Vector2:
	return bounds.position + bounds.size * 0.5
