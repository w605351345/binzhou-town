extends Node2D
## 游戏根场景:农场 + HUD + 季节与农时提示。
##
## 黑龙江设定:春播秋收,冬季休耕时显示提示。
## HUD 常驻"当前可播种"与"秋霜倒计时" —— 这是风险 R2/R3 的对策,
## 让玩家一眼看出"现在该干嘛"。

@onready var hud_label: Label = $HUD/HBox/HudLabel
@onready var season_label: Label = $HUD/HBox/SeasonLabel
@onready var message_label: Label = $MessageLabel
@onready var tip_label: Label = $TipLabel
@onready var key_hint: Label = $KeyHint

var _calendar: GameCalendar
var _farm: FarmSystem

func _ready() -> void:
	_calendar = GameStateManager.state.calendar
	_farm = GameStateManager.state.farm
	_refresh_hud()
	GameStateManager.day_started.connect(_on_day_started)
	GameStateManager.season_changed.connect(_on_season_changed)

func _process(_delta: float) -> void:
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
	tip_label.text = _farming_tip()
	key_hint.text = "WASD 移动 · J 翻土 · K 浇水 · L 播种 · I 收获 · R 秋翻 · E 对话 · F 前往镇大街 · T 睡觉 · ESC 暂停" 

## 农时提示:现在该种什么 / 秋霜还有几天 / 冬歇提醒
func _farming_tip() -> String:
	var m := _calendar.get_real_month()
	var sowable := _farm.sowable_crop_ids()
	if _calendar.is_winter():
		return "【冬歇】地里歇着呢 · 可秋翻地积肥 · R 键深翻"
	if sowable.is_empty():
		return "【已过播种窗】%d月种不上了,等明年春" % m
	var names: Array = []
	for cid in sowable:
		var crop := CropDatabase.get_crop(cid)
		if crop != null:
			names.append(crop.name)
	var tip := "【可播种】%s" % ", ".join(names)
	# 秋霜倒计时:10 月霜降,9 月要开始抢收
	if m == 9:
		tip += " · 秋霜将至,晚收的别拖"
	elif m == 10:
		tip += " · ⚠ 秋霜就在眼前,赶紧割"
	return tip

func _on_day_started(_day: int) -> void:
	_refresh_hud()

func _on_season_changed(season: String) -> void:
	message_label.text = "【%s】%s" % [GameCalendar.season_cn(season), GameCalendar.season_desc(season)]
	_refresh_hud()
