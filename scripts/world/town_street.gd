extends Node2D
## 宾州镇大街(L02):张晓芳的所在地,玩家卖粮的地方。
##
## 黑龙江小镇的镇大街:一条土路,两边是门市和院墙。

@onready var player: CharacterBody2D = $Player
@onready var message_label: Label = $HUD/MessageLabel
@onready var npc_container: Node2D = $NpcContainer

var _npc_node: NpcNode = null

func _ready() -> void:
	_spawn_npcs()

func _spawn_npcs() -> void:
	var zhang := ZhangXiaofang.new()
	# 好感度存在存档里 —— NPC 每次进场景都重建,得从 GameState 恢复
	zhang.affection = GameStateManager.state.npc_affection(zhang.id)
	# 张晓芳每天换摊位(早市/晌午/傍晚)—— 当前第几天从日历取,
	# 这样不管场景怎么重建,她站的位置都对得上日子
	zhang.current_day = GameStateManager.state.calendar.day_of_year
	# 加载带 Label / Body 子节点的 NPC 场景,再填入数据
	var packed: PackedScene = load("res://scenes/npc_zhangxiaofang.tscn")
	if packed == null:
		push_error("镇大街: NPC 场景加载失败")
		return
	var node: NpcNode = packed.instantiate()
	node.setup(zhang)
	npc_container.add_child(node)
	_npc_node = node

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("travel"):
		_go_to_farm()

## 回自家院(L01)
func _go_to_farm() -> void:
	if not SceneRouter.is_implemented("L01"):
		return
	GameStateManager.travel_requested.emit("L01")

func _interact() -> void:
	if _npc_node == null or _npc_node.npc == null:
		return
	# 对话/商店开着的时候不再重开对话 —— 商店里按 E 会把谈话重置掉
	if GameStateManager.input_locked:
		return
	var npc := _npc_node.npc
	var facing: Vector2 = Vector2.DOWN
	if player.has_method("facing_vector"):
		facing = player.facing_vector()
	if not InteractionSystem.can_interact(player.global_position, facing, npc.today_position()):
		_show_message("走近点再说话")
		return
	# 交给游戏外壳开对话框(对话系统住在外壳里,换地点也不会丢)
	GameStateManager.dialogue_requested.emit(npc)

func _show_message(text: String) -> void:
	if message_label != null:
		message_label.text = text
