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
const NAMEPLATE_RANGE := 350.0
const BODY_SCALE := 1.12

@onready var label: Label = $Label
@onready var body: Node2D = $Body
@onready var sprite: AnimatedSprite2D = $Body/Sprite

var npc: NpcBase = null
var _sprite_path := SHEET_PATH
var _nameplate: ColorRect = null
var _near_player := false

func _ready() -> void:
	body.scale = Vector2.ONE * BODY_SCALE
	_build_frames()
	_build_collision()
	_build_nameplate()

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
	_update_nameplate()

func _draw() -> void:
	var tint := Color(0.98, 0.78, 0.35, 0.24) if _near_player \
		else Color(0.92, 0.84, 0.62, 0.12)
	var radius := 25.0 if _near_player else 20.0
	draw_set_transform(Vector2(0, -1), 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, radius, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func nameplate_visible() -> bool:
	return _nameplate != null and _nameplate.visible

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
	# 发行包只保留导入后的 .ctex,源 PNG 不一定作为普通文件存在。
	# FileAccess 判断会把可加载的导入资源误判为缺失;ResourceLoader 才准确。
	if not ResourceLoader.exists(path):
		path = SHEET_PATH
	if not ResourceLoader.exists(path):
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

## NPC 也是实体,不能和主角互相穿过去。碰撞体只覆盖脚边一小块,
## 头顶名字与立绘不受影响。
func _build_collision() -> void:
	if get_node_or_null("Solid") != null:
		return
	var body := StaticBody2D.new()
	body.name = "Solid"
	body.collision_layer = 4
	body.collision_mask = 2
	var collision := CollisionShape2D.new()
	collision.name = "Collision"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(26, 30)
	collision.shape = shape
	collision.position = Vector2(0, -15)
	body.add_child(collision)
	add_child(body)

## 暖色小名牌比黑色底板更融入场景，也更不容易被雪地和木地板吞掉。
func _build_nameplate() -> void:
	if label == null or get_node_or_null("NamePlate") != null:
		return
	var plate := ColorRect.new()
	plate.name = "NamePlate"
	plate.color = Color(0.44, 0.31, 0.17, 0.78)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.position = Vector2(-54, -90)
	plate.size = Vector2(108, 28)
	plate.z_index = 1
	add_child(plate)
	_nameplate = plate
	label.position = Vector2(-54, -92)
	label.size = Vector2(108, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0.28, 0.17, 0.08, 0.9))
	label.z_index = 2

func _update_nameplate() -> void:
	if _nameplate == null:
		return
	var tree := get_tree()
	if tree == null:
		return
	var player := tree.get_first_node_in_group("player") as Node2D
	if player == null:
		_nameplate.visible = true
		return
	var near := global_position.distance_to(player.global_position) <= NAMEPLATE_RANGE
	_nameplate.visible = near
	if label != null:
		label.visible = near
	if near != _near_player:
		_near_player = near
		queue_redraw()

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
