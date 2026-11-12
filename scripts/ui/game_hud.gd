extends Node2D
## 游戏根场景(MVP):农场 + HUD + 季节显示。
## 黑龙江设定:春播秋收,冬季休耕时显示提示。

@onready var hud_label: Label = $HUD/HBox/HudLabel
@onready var season_label: Label = $HUD/HBox/SeasonLabel
@onready var message_label: Label = $MessageLabel

var _calendar: GameCalendar
var _farm: FarmSystem

func _ready() -> void:
	_calendar = GameStateManager.state.calendar
	_farm = GameStateManager.state.farm
	_refresh_hud()
	GameStateManager.day_started.connect(_on_day_started)
	GameStateManager.season_changed.connect(_on_season_changed)

func _process(delta: float) -> void:
	_refresh_hud()

func _refresh_hud() -> void:
	var p := GameStateManager.state.player
	var stats := _farm.get_stats()
	hud_label.text = "第%d年 %d月%d日  %s | 金币 %d | 体力 %d/%d | 已种 %d 可收 %d" % [
		_calendar.year, _calendar.get_real_month(), _calendar.get_day_of_month(),
		GameCalendar.season_cn(_calendar.get_season()),
		p.gold, p.energy, p.max_energy,
		stats.get("planted", 0), stats.get("ready", 0),
	]
	season_label.text = GameCalendar.season_desc(_calendar.get_season())

func _on_day_started(day: int) -> void:
	_refresh_hud()

func _on_season_changed(season: String) -> void:
	message_label.text = "【%s】%s" % [GameCalendar.season_cn(season), GameCalendar.season_desc(season)]
	_refresh_hud()
