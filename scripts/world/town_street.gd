extends Node2D
## 宾州镇大街(L02):张婶的所在地,玩家卖粮的地方。
##
## 黑龙江小镇的镇大街:一条土路,两边是门市和院墙。

@onready var player: CharacterBody2D = $Player
@onready var message_label: Label = $HUD/MessageLabel
@onready var npc_container: Node2D = $NpcContainer

var _npc_node: NpcNode = null

func _ready() -> void:
	_spawn_npcs()

func _spawn_npcs() -> void:
	var zhang := ZhangShen.new()
	# 加载带 Label / Body 子节点的 NPC 场景,再填入数据
	var packed: PackedScene = load("res://scenes/npc_zhangshen.tscn")
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
	var npc := _npc_node.npc
	var facing: Vector2 = Vector2.DOWN
	if player.has_method("facing_vector"):
		facing = player.facing_vector()
	if not InteractionSystem.can_interact(player.global_position, facing, npc.today_position()):
		_show_message("走近点再说话")
		return
	_show_message(npc.dialogue())
	# 顺手把背包里的作物卖掉一部分(张婶是收购商)
	var player_state: PlayerProfile = GameStateManager.state.player
	for crop_id in player_state.inventory.keys():
		var amount := int(player_state.inventory[crop_id])
		if amount <= 0:
			continue
		var res := npc.buy_crop(player_state, crop_id, amount)
		if bool(res.get("ok", false)):
			_show_message(String(res.get("message", "")))
			break

func _show_message(text: String) -> void:
	if message_label != null:
		message_label.text = text
