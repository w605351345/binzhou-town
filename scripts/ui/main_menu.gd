extends Control
## 主菜单(MVP):支持性别选择(双主角)、存档入口。

@onready var title_label: Label = $Center/VBox/Title
@onready var subtitle_label: Label = $Center/VBox/Subtitle
@onready var gender_label: Label = $Center/VBox/GenderRow/GenderLabel
@onready var start_button: Button = $Center/VBox/StartButton
@onready var continue_button: Button = $Center/VBox/ContinueButton
@onready var quit_button: Button = $Center/VBox/QuitButton
@onready var season_label: Label = $Center/VBox/SeasonLabel

var _gender: int = PlayerProfile.Gender.MALE

func _ready() -> void:
	title_label.text = "宾 州 小 镇"
	subtitle_label.text = "黑龙江黑土地 · 一年一熟 · 春播秋收"
	gender_label.text = "主角性别：男 / 女（双主角支持）"
	season_label.text = GameCalendar.season_desc("winter")
	continue_button.disabled = not GameStateManager.has_save(0)
	start_button.pressed.connect(_on_start)
	continue_button.pressed.connect(_on_continue)
	quit_button.pressed.connect(_on_quit)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_gender = PlayerProfile.Gender.FEMALE if _gender == PlayerProfile.Gender.MALE else PlayerProfile.Gender.MALE
		_refresh()
	if event.is_action_pressed("ui_accept"):
		_on_start()

func _refresh() -> void:
	gender_label.text = "主角性别：%s（← → 切换）" % PlayerProfile.gender_cn(_gender)

func _on_start() -> void:
	GameStateManager.state = GameState.new()
	GameStateManager.state.player.gender = _gender
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_continue() -> void:
	if GameStateManager.load_game(0):
		get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_quit() -> void:
	get_tree().quit()
