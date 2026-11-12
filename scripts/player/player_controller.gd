extends RefCounted
class_name PlayerController

## 玩家移动核心逻辑(纯逻辑,可 headless 单测)
##
## 4 方向 × 8 帧行走动画。左右方向复用同一张行(sheet 第 3 行),靠 flip_h 镜像,
## 这样精灵表只需 3 行,美术后续替换也只改一处资源。
##
## 速度单位:像素/秒。WorldMap 负责地图边界裁剪,本类只负责"想去哪"。

enum Facing { DOWN, UP, LEFT, RIGHT }

## 精灵表行序(与 assets/sprites/player_body.png 对齐)
const SHEET_ROW_DOWN := 0
const SHEET_ROW_UP := 1
const SHEET_ROW_SIDE := 2

## 每方向帧数
const FRAMES_PER_DIRECTION := 8
## 单帧时长(秒),8 帧一轮 ≈ 0.64s 一步
const FRAME_DURATION := 0.08

## 行走速度
const WALK_SPEED := 220.0

var facing: int = Facing.DOWN
var is_moving: bool = false

var _animation_time: float = 0.0

## 设置朝向与移动意图。dir 为归一化前的输入向量(任意长度均可)。
func set_input(dir: Vector2) -> void:
	if dir.length_squared() < 0.0001:
		is_moving = false
		return
	is_moving = true
	# 斜向时取绝对值较大的轴,避免 8 向移动
	if absf(dir.x) > absf(dir.y):
		facing = Facing.RIGHT if dir.x > 0.0 else Facing.LEFT
	else:
		facing = Facing.DOWN if dir.y > 0.0 else Facing.UP

## 当前移动速度向量
func velocity() -> Vector2:
	if not is_moving:
		return Vector2.ZERO
	match facing:
		Facing.UP:
			return Vector2.UP * WALK_SPEED
		Facing.DOWN:
			return Vector2.DOWN * WALK_SPEED
		Facing.LEFT:
			return Vector2.LEFT * WALK_SPEED
		Facing.RIGHT:
			return Vector2.RIGHT * WALK_SPEED
	return Vector2.ZERO

## 推进动画计时,返回当前帧序号(0-7)
func advance_animation(delta: float) -> int:
	if not is_moving:
		_animation_time = 0.0
		return 0
	_animation_time += delta
	var total := _animation_time / FRAME_DURATION
	return int(total) % FRAMES_PER_DIRECTION

## 当前动画帧序号(不推进)
func current_frame() -> int:
	if not is_moving:
		return 0
	return int(_animation_time / FRAME_DURATION) % FRAMES_PER_DIRECTION

## 精灵表行号
func sheet_row() -> int:
	match facing:
		Facing.UP:
			return SHEET_ROW_UP
		Facing.DOWN:
			return SHEET_ROW_DOWN
	return SHEET_ROW_SIDE

## 是否需要水平翻转(向左时)
func is_flipped() -> bool:
	return facing == Facing.LEFT

## 朝向中文名(调试与 HUD)
func facing_cn() -> String:
	match facing:
		Facing.UP:
			return "上"
		Facing.DOWN:
			return "下"
		Facing.LEFT:
			return "左"
		Facing.RIGHT:
			return "右"
	return "?"
