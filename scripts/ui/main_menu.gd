extends Control
## 主菜单:四季场景板轮播、性别选择(双主角)与存档入口。

const SEASON_BOARDS := [
	"res://assets/art/concept/season_spring.png",
	"res://assets/art/concept/season_summer.png",
	"res://assets/art/concept/season_autumn.png",
	"res://assets/art/concept/season_winter.png",
]
const SEASON_KEYS := ["spring", "summer", "autumn", "winter"]
const BOARD_INTERVAL := 7.0

@onready var title_label: Label = $Center/VBox/Title
@onready var subtitle_label: Label = $Center/VBox/Subtitle
@onready var gender_label: Label = $Center/VBox/GenderRow/GenderLabel
@onready var start_button: Button = $Center/VBox/StartButton
@onready var continue_button: Button = $Center/VBox/ContinueButton
@onready var quit_button: Button = $Center/VBox/QuitButton
@onready var season_label: Label = $Center/VBox/SeasonLabel
@onready var background: TextureRect = $Background

var _gender: int = PlayerProfile.Gender.MALE
var _season_index: int = 3
var _board_clock := 0.0

func _ready() -> void:
	title_label.text = "宾 州 小 镇"
	subtitle_label.text = "黑龙江黑土地 · 一年一熟 · 春播秋收"
	gender_label.text = "主角性别：男 / 女（双主角支持）"
	season_label.text = GameCalendar.season_desc("winter")
	_apply_look()
	_show_season_board()
	continue_button.disabled = not GameStateManager.has_save(0)
	start_button.pressed.connect(_on_start)
	continue_button.pressed.connect(_on_continue)
	quit_button.pressed.connect(_on_quit)
	start_button.grab_focus()

func _process(delta: float) -> void:
	_board_clock += delta
	if _board_clock < BOARD_INTERVAL:
		return
	_board_clock = 0.0
	_season_index = (_season_index + 1) % SEASON_BOARDS.size()
	_show_season_board()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_gender = PlayerProfile.Gender.FEMALE if _gender == PlayerProfile.Gender.MALE else PlayerProfile.Gender.MALE
		_refresh()
func _refresh() -> void:
	gender_label.text = "主角性别：%s（← → 切换）" % PlayerProfile.gender_cn(_gender)

func current_season() -> String:
	return SEASON_KEYS[_season_index]

func _show_season_board() -> void:
	if background == null:
		return
	var path: String = SEASON_BOARDS[_season_index]
	if ResourceLoader.exists(path):
		background.texture = load(path) as Texture2D
	season_label.text = GameCalendar.season_desc(SEASON_KEYS[_season_index]) \
		+ " · 四季轮转"
	if is_inside_tree():
		background.modulate.a = 0.35
		var tween := create_tween()
		tween.tween_property(background, "modulate:a", 1.0, 0.75) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _apply_look() -> void:
	title_label.add_theme_color_override("font_color", Color(0.98, 0.90, 0.70))
	title_label.add_theme_color_override("font_shadow_color", Color(0.08, 0.05, 0.03, 0.9))
	title_label.add_theme_constant_override("shadow_offset_x", 3)
	title_label.add_theme_constant_override("shadow_offset_y", 4)
	subtitle_label.add_theme_color_override("font_color", Color(0.90, 0.84, 0.70))
	season_label.add_theme_color_override("font_color", Color(0.96, 0.76, 0.42))

func _on_start() -> void:
	GameStateManager.new_session()
	GameStateManager.state.player.gender = _gender
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_continue() -> void:
	if GameStateManager.load_game(0):
		get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_quit() -> void:
	get_tree().quit()
