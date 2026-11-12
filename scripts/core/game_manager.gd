extends Node
## 全局管理器(autoload):持有 GameState,负责日推进与存档。

signal day_started(day: int)
signal season_changed(season: String)
signal game_saved(slot: int)

const SAVE_DIR := "user://saves"

var state: GameState = null
var _paused := false
var _last_season := ""

func _ready() -> void:
	state = GameState.new()
	_last_season = state.calendar.get_season()
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func _process(delta: float) -> void:
	if _paused or state == null:
		return
	# MVP:每 12 现实分钟推进 1 游戏日,这里用较短周期便于测试
	# 正式版按 GameCalendar.REAL_SECONDS_PER_GAME_DAY
	pass

## 推进一个游戏日(供 UI/调试调用)
func advance_day() -> void:
	state.farm.advance_day()
	state.calendar.advance_day()
	var s := state.calendar.get_season()
	if s != _last_season:
		_last_season = s
		season_changed.emit(s)
	day_started.emit(state.calendar.day_of_year)

## 存档
func save_game(slot: int = 0) -> bool:
	var f := FileAccess.open("%s/slot_%d.json" % [SAVE_DIR, slot], FileAccess.WRITE)
	if f == null:
		push_error("存档写入失败 slot=%d" % slot)
		return false
	f.store_string(JSON.stringify(state.to_dict()))
	f.close()
	game_saved.emit(slot)
	return true

## 读档
func load_game(slot: int = 0) -> bool:
	var path := "%s/slot_%d.json" % [SAVE_DIR, slot]
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	state = GameState.from_dict(parsed)
	_last_season = state.calendar.get_season()
	return true

func has_save(slot: int = 0) -> bool:
	return FileAccess.file_exists("%s/slot_%d.json" % [SAVE_DIR, slot])

func set_paused(p: bool) -> void:
	_paused = p
