extends Node
## 全局管理器(autoload):持有 GameState,负责日推进与存档。

signal day_started(day: int)
signal season_changed(season: String)
signal game_saved(slot: int)
## 场景切换请求:由各地点场景发出,由游戏外壳(Game)接收并替换世界容器。
## 刻意不直接 change_scene_to_file —— 否则会把常驻 HUD 一起销毁。
signal travel_requested(location_id: String)
## 对话请求:地点场景判定玩家能交互后发出,由游戏外壳接管(和 travel_requested 一个套路)。
## 传的是 NPC 本体 —— 好感度、收购价都在 NPC 上,换场景重建后靠 GameState 恢复。
signal dialogue_requested(npc: NpcBase)

const SAVE_DIR := "user://saves"

var state: GameState = null
var _paused := false
var _last_season := ""
## 对话进行中:锁住主角移动,免得一边看台词一边乱走
var dialogue_open: bool = false
## 背包面板打开中:同样锁住移动
var inventory_open: bool = false
## 输入是否被界面占着(对话 / 背包 / 商店)
var input_locked: bool:
	get:
		return dialogue_open or inventory_open

func _ready() -> void:
	state = GameState.new()
	_last_season = state.calendar.get_season()
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

## 睡醒后体力回满(黑龙江农活是重体力活,一天干不动太多活)
func rest_and_recover() -> void:
	if state.player.stamina != null:
		state.player.stamina.sleep()

## 推进一个游戏日(供 UI/调试/自动推进调用)
func advance_day() -> void:
	state.farm.advance_day()
	state.calendar.advance_day()
	rest_and_recover()
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

## 对话开始/结束时占用或归还输入
func set_dialogue_open(v: bool) -> void:
	dialogue_open = v

## 背包开合时占用或归还输入
func set_inventory_open(v: bool) -> void:
	inventory_open = v
