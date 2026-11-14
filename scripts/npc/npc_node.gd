extends Node2D
class_name NpcNode
## NPC 的场景节点:精灵形象 + 头顶名字。
##
## 张晓芳用自己的精灵表(assets/sprites/npc_zhangxiaofang.png,帧 48×72),
## 站立时用第 0 / 第 4 帧循环做呼吸感 —— 她不做巡逻 AI,只站在摊位上。

const SHEET_PATH := "res://assets/sprites/npc_zhangxiaofang.png"
const FRAME_SIZE := Vector2i(48, 72)
## 呼吸动画用哪两帧(走路循环里身体起伏最大的那一对)
const IDLE_FRAMES := [0, 4]
const IDLE_FPS := 1.4

@onready var label: Label = $Label
@onready var body: Node2D = $Body
@onready var sprite: AnimatedSprite2D = $Body/Sprite

var npc: NpcBase = null
var _sprite_path := SHEET_PATH

func _ready() -> void:
	_build_frames()

func setup(p_npc: NpcBase) -> void:
	npc = p_npc
	if label != null:
		label.text = p_npc.name
	_refresh_position()
	_build_frames()

func _refresh_position() -> void:
	if npc == null:
		return
	global_position = npc.today_position()

func _process(_delta: float) -> void:
	_refresh_position()

## 用精灵表的前两帧拼一个站立呼吸动画
func _build_frames() -> void:
	if sprite == null:
		return
	var requested := SHEET_PATH
	if npc != null:
		var season := "spring"
		var manager := _state_manager()
		if manager != null and manager.state != null and manager.state.calendar != null:
			season = manager.state.calendar.get_season()
		var selected := npc.sprite_path_for(season)
		if selected != "":
			requested = selected
	var path := requested
	if not FileAccess.file_exists(path):
		path = SHEET_PATH
	if not FileAccess.file_exists(path):
		push_warning("NpcNode: 找不到 NPC 精灵表 %s" % requested)
		return
	_sprite_path = path
	var tex: Texture2D = load(path)
	if tex == null:
		push_warning("NpcNode: 找不到 NPC 精灵表 %s" % path)
		return
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("idle")
	frames.set_animation_speed("idle", IDLE_FPS)
	frames.set_animation_loop("idle", true)
	for idx in IDLE_FRAMES:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(
			Vector2(float(idx) * FRAME_SIZE.x, 0.0),
			Vector2(FRAME_SIZE.x, FRAME_SIZE.y))
		frames.add_frame("idle", atlas)
	sprite.sprite_frames = frames
	sprite.animation = "idle"

## 实际加载成功的贴图路径。数据路径缺失时会回退到通用占位图。
func resolved_sprite_path() -> String:
	return _sprite_path

## 不在编译期引用 autoload 全局名: headless --script 会在 autoload 注册前
## 预编译主脚本的依赖,直接写 GameStateManager 会留下假性 Compile Error。
func _state_manager() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	return loop.root.get_node_or_null("GameStateManager")
