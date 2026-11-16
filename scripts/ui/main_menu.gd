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
@onready var shade: ColorRect = $Shade
@onready var center: CenterContainer = $Center

var _gender: int = PlayerProfile.Gender.MALE
var _season_index: int = 3
var _board_clock := 0.0

func _ready() -> void:
	title_label.text = "麦 溪 镇"
	subtitle_label.text = "Meadowbrook · 种田、来信与月桂剧场"
	gender_label.text = "主角性别：男 / 女（双主角支持）"
	season_label.text = GameCalendar.season_desc("winter")
	_build_menu_card()
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
	if shade != null:
		shade.color = Color(0.03, 0.05, 0.03, 0.20)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.91, 0.58))
	title_label.add_theme_color_override("font_shadow_color", Color(0.12, 0.18, 0.10, 1.0))
	title_label.add_theme_constant_override("shadow_offset_x", 3)
	title_label.add_theme_constant_override("shadow_offset_y", 5)
	subtitle_label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.87))
	season_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.42))
	gender_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.80))
	_style_button(start_button, "开始新农庄")
	_style_button(continue_button, "继续农庄")
	_style_button(quit_button, "离开小镇")

func _build_menu_card() -> void:
	var card := PanelContainer.new()
	card.name = "MenuCard"
	card.custom_minimum_size = Vector2(720, 650)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.12, 0.075, 0.78)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.82, 0.66, 0.31, 0.92)
	style.corner_radius_top_left = 22
	style.corner_radius_top_right = 22
	style.corner_radius_bottom_left = 22
	style.corner_radius_bottom_right = 22
	style.shadow_color = Color(0.01, 0.02, 0.01, 0.45)
	style.shadow_size = 18
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)
	center.move_child(card, 0)

func _style_button(button: Button, label: String) -> void:
	if button == null:
		return
	button.text = label
	button.add_theme_font_size_override("font_size", 23)
	button.add_theme_color_override("font_color", Color(0.20, 0.13, 0.07))
	button.add_theme_color_override("font_hover_color", Color(0.12, 0.09, 0.04))
	button.add_theme_color_override("font_focus_color", Color(0.12, 0.09, 0.04))
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.50, 0.42))
	button.add_theme_stylebox_override("normal", _button_style(
		Color(0.96, 0.88, 0.67), Color(0.79, 0.57, 0.25)))
	button.add_theme_stylebox_override("hover", _button_style(
		Color(1.0, 0.95, 0.76), Color(1.0, 0.72, 0.28)))
	button.add_theme_stylebox_override("pressed", _button_style(
		Color(0.88, 0.77, 0.55), Color(0.62, 0.38, 0.16)))
	button.add_theme_stylebox_override("focus", _button_style(
		Color(1.0, 0.95, 0.76), Color(1.0, 0.72, 0.28)))
	button.add_theme_stylebox_override("disabled", _button_style(
		Color(0.52, 0.49, 0.40, 0.82), Color(0.68, 0.62, 0.48, 0.8)))

func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = border
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func _on_start() -> void:
	GameStateManager.new_session()
	GameStateManager.state.player.gender = _gender
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_continue() -> void:
	if GameStateManager.load_game(0):
		get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_quit() -> void:
	get_tree().quit()
