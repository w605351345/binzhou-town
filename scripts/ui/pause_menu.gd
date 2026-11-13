extends CanvasLayer
## 暂停菜单(ESC):存档 / 读档 / 回主菜单 / 退出。
##
## 黑龙江小镇的节奏是慢的,暂停菜单给玩家"歇口气"的正当理由。

signal resume_requested
signal menu_requested

@onready var panel: Control = $Root/Panel
@onready var save_button: Button = $Root/Panel/SaveButton
@onready var load_button: Button = $Root/Panel/LoadButton
@onready var voice_button: Button = $Root/Panel/VoiceButton
@onready var menu_button: Button = $Root/Panel/MenuButton
@onready var quit_button: Button = $Root/Panel/QuitButton
@onready var status_label: Label = $Root/Panel/StatusLabel

var _visible_before := false

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	save_button.pressed.connect(_on_save)
	load_button.pressed.connect(_on_load)
	voice_button.pressed.connect(_on_toggle_voice)
	menu_button.pressed.connect(_on_menu)
	quit_button.pressed.connect(_on_quit)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_pause"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()

func open() -> void:
	visible = true
	GameStateManager.set_paused(true)
	get_tree().paused = true
	_refresh()

func close() -> void:
	visible = false
	GameStateManager.set_paused(false)
	get_tree().paused = false
	resume_requested.emit()

func _refresh() -> void:
	_refresh_voice_label()
	var has_save := GameStateManager.has_save(0)
	load_button.disabled = not has_save
	if has_save:
		status_label.text = "存档 1 已存在"
	else:
		status_label.text = "还没有存档"

## 语音开关:关掉后 NPC 不再出声(字幕照常)
func _on_toggle_voice() -> void:
	if GameStateManager.state != null:
		GameStateManager.state.voice_enabled = not GameStateManager.state.voice_enabled
	_refresh_voice_label()

func _refresh_voice_label() -> void:
	if voice_button == null:
		return
	var on := GameStateManager.state == null or GameStateManager.state.voice_enabled
	voice_button.text = "语音:开" if on else "语音:关"

func _on_save() -> void:
	if GameStateManager.save_game(0):
		status_label.text = "已存档"
	else:
		status_label.text = "存档失败"

func _on_load() -> void:
	if GameStateManager.load_game(0):
		close()
		get_tree().reload_current_scene()
	else:
		status_label.text = "读档失败"

func _on_menu() -> void:
	get_tree().paused = false
	GameStateManager.set_paused(false)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_quit() -> void:
	get_tree().paused = false
	get_tree().quit()
