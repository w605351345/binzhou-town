extends CharacterBody2D
## 主角节点:输入 → PlayerController(纯逻辑)→ 位移 + 动画。
##
## 逻辑全部在 PlayerController 里,这里只负责表现与物理,便于 headless 单测。

const SPRITE_MALE := "res://assets/sprites/player_body.png"
const SPRITE_FEMALE := "res://assets/sprites/player_female.png"
## 精灵表单帧尺寸
const FRAME_SIZE := Vector2i(32, 48)
## 精灵表行数(下/上/侧)
const SHEET_ROWS := 3

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var shadow: Sprite2D = $Shadow

var controller: PlayerController = null
## 当前所在地图(边界裁剪用)
var world: WorldMap = null
## 性别 -> 精灵表
var _female := false

func _ready() -> void:
	controller = PlayerController.new()
	_apply_sprite(false)
	if world == null:
		world = WorldMap.new(Rect2(Vector2.ZERO, get_parent_area_size()))

func _apply_sprite(female: bool) -> void:
	_female = female
	var path := SPRITE_FEMALE if female else SPRITE_MALE
	var tex: Texture2D = load(path)
	if tex == null:
		return
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var anim_names: Array = ["walk_down", "walk_up", "walk_side"]
	for row in SHEET_ROWS:
		var anim: String = anim_names[row]
		frames.add_animation(anim)
		frames.set_animation_speed(anim, 1.0 / PlayerController.FRAME_DURATION)
		frames.set_animation_loop(anim, true)
		for frame in PlayerController.FRAMES_PER_DIRECTION:
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(
				Vector2(frame * FRAME_SIZE.x, row * FRAME_SIZE.y),
				Vector2(FRAME_SIZE.x, FRAME_SIZE.y))
			frames.add_frame(anim, atlas)
	sprite.sprite_frames = frames
	sprite.animation = "walk_down"

## 按主角性别切换精灵表(D10)
func set_female(female: bool) -> void:
	if _female == female:
		return
	_apply_sprite(female)

func _physics_process(delta: float) -> void:
	# 界面占着输入时不挪窝 —— 边看台词边乱走会错过张婶的话
	if GameStateManager.input_locked:
		velocity = Vector2.ZERO
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	controller.set_input(dir)
	velocity = controller.velocity()
	move_and_slide()

	# 边界裁剪(Week 2 验收点:不出地图)
	if world != null:
		global_position = world.clamp_position(global_position)

	# 动画帧
	if controller.is_moving:
		var row := controller.sheet_row()
		var anim: String = ["walk_down", "walk_up", "walk_side"][row]
		sprite.animation = anim
		sprite.frame = controller.advance_animation(delta)
		sprite.flip_h = controller.is_flipped()
	else:
		sprite.frame = 0

## 当前朝向向量(供交互系统判定)
func facing_vector() -> Vector2:
	match controller.facing:
		PlayerController.Facing.UP:
			return Vector2.UP
		PlayerController.Facing.DOWN:
			return Vector2.DOWN
		PlayerController.Facing.LEFT:
			return Vector2.LEFT
		PlayerController.Facing.RIGHT:
			return Vector2.RIGHT
	return Vector2.DOWN

func get_parent_area_size() -> Vector2:
	return Vector2(1920, 1080)
