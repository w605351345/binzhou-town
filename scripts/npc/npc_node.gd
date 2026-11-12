extends Node2D
class_name NpcNode
## NPC 的场景节点:显示占位形象 + 头顶名字 + 交互提示。

@onready var label: Label = $Label
@onready var body: Node2D = $Body

var npc: NpcBase = null

func setup(p_npc: NpcBase) -> void:
	npc = p_npc
	if label != null:
		label.text = p_npc.name
	_refresh_position()

func _refresh_position() -> void:
	if npc == null:
		return
	global_position = npc.today_position()

func _process(_delta: float) -> void:
	_refresh_position()

func _draw() -> void:
	# 占位形象:粗布衫 + 头,颜色按性别
	var female := npc != null and npc.name == "张婶"
	var coat := Color(0.42, 0.24, 0.26) if female else Color(0.28, 0.32, 0.40)
	var skin := Color(0.94, 0.82, 0.70)
	draw_circle(Vector2(0, -30), 11.0, skin)
	draw_rect(Rect2(-13, -18, 26, 26), coat, true)
	draw_rect(Rect2(-13, -18, 26, 26), Color(0, 0, 0, 0.35), false, 2.0)
	draw_circle(Vector2(0, 44), 12.0, Color(0, 0, 0, 0.22))
