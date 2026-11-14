extends Node2D
## 老邮局(L03):寄信、等回信、翻收藏册。
##
## E/A 打开邮册,F/右摇杆回镇大街,T/RT 把日子往前推一天等邮差。

@onready var player: CharacterBody2D = $Player
@onready var message_label: Label = $HUD/MessageLabel

func _unhandled_input(event: InputEvent) -> void:
	if GameStateManager.input_locked:
		return
	if event.is_action_pressed("interact"):
		_open_postbox()
	elif event.is_action_pressed("travel"):
		_go_to_town()
	elif event.is_action_pressed("sleep"):
		_wait_one_day()

func _open_postbox() -> void:
	GameStateManager.post_office_requested.emit()

func _go_to_town() -> void:
	if not SceneRouter.is_implemented("L02"):
		return
	GameStateManager.travel_requested.emit("L02")

func _wait_one_day() -> void:
	GameStateManager.advance_day()
	_show_message("邮车没来,先把日子过到明天 · %s" % GameStateManager.state.calendar.date_string())

func _show_message(text: String) -> void:
	if message_label != null:
		message_label.text = text
