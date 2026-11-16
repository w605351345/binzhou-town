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
## 好感事件请求:地点场景判定后交给常驻外壳播放。
signal event_requested(event: Dictionary)
## 活动请求:钓鱼 / 烹饪 / 节日活动由常驻外壳打开。
signal activity_requested(kind: String)
## 公告板请求:由镇中心场景发出,常驻外壳打开任务面板。
signal quest_board_requested
## 邮局柜台请求:地点场景只负责判定,面板由常驻游戏外壳打开。
signal post_office_requested
## 杂货店/集市柜台:购买面板由常驻游戏外壳打开。
signal shop_requested
## 农舍储物柜:复用背包面板,但由场景互动触发。
signal inventory_requested
## 功能 NPC / 工作台 / 运输箱 / 矿洞 / 工程板：由常驻外壳打开统一服务面板。
signal service_requested(service_type: String)
## 月桂剧场:地点场景只发请求，古戏剧本面板由常驻外壳打开。
signal drama_requested
## 邮差送到的明信片(可能一次收到多张,正常每天最多一张)。
signal postcards_delivered(cards: Array)
signal clock_changed(minute_of_day: int)
## 地点场景把"当前能做什么"交给常驻 HUD 统一显示,避免地点自己再叠一套
## 消息/提示标签。三个字段分别是:最近消息、附近交互提示、地块状态。
signal location_context_changed(message: String, prompt: String, plot_info: String)
signal player_collapsed
signal shipping_settled(report: Dictionary)
signal livestock_produced(report: Dictionary)

const SAVE_DIR := "user://saves"

var state: GameState = null
var _paused := false
var _last_season := ""
var pending_spawn: Vector2 = Vector2(-1, -1)
var modal_stack: ModalStack = ModalStack.new()
## 输入是否被界面占着(对话 / 背包 / 商店)
var input_locked: bool:
	get:
		return modal_stack.is_locked()

var dialogue_open: bool:
	get:
		return modal_stack.has("dialogue")

var inventory_open: bool:
	get:
		return modal_stack.has("inventory")

var postcard_open: bool:
	get:
		return modal_stack.has("postcard")

func _ready() -> void:
	new_session()
	apply_capture_options(state, OS.get_cmdline_user_args())
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

## 截图/美术验收用：允许从命令行锁定季节、时刻和天气。
## 正常启动没有 user args，因此不会影响玩家存档或游戏流程。
func apply_capture_options(p_state: GameState, args: PackedStringArray) -> Dictionary:
	if p_state == null or args.is_empty():
		return {}
	var season := ""
	var time_value := ""
	var weather_id := ""
	var day_in_season := 15
	var location_id := ""
	var spawn := Vector2(-99999, -99999)
	for arg in args:
		if not String(arg).begins_with("--") or not String(arg).contains("="):
			continue
		var pair := String(arg).substr(2).split("=", true, 1)
		if pair.size() != 2:
			continue
		match pair[0]:
			"season": season = pair[1]
			"time": time_value = pair[1]
			"weather": weather_id = pair[1]
			"day": day_in_season = clampi(int(pair[1]), 1, 30)
			"location": location_id = pair[1]
			"spawn":
				var coords := pair[1].split(",", true, 1)
				if coords.size() == 2:
					spawn = Vector2(float(coords[0]), float(coords[1]))
	if season in MapRenderer.SEASONS:
		p_state.calendar.advance_to_season(season, day_in_season)
	if time_value != "":
		var minute := _parse_capture_time(time_value)
		if minute >= 0:
			p_state.clock.minute_of_day = minute
	if weather_id != "":
		p_state.weather.today = weather_id
		p_state.weather.tomorrow = weather_id
	else:
		p_state.weather.refresh(p_state.calendar, p_state.weather.seed)
	if location_id != "":
		var target_map := MapDatabase.get_map(location_id)
		if not target_map.is_empty():
			var target_spawn := MapDatabase.spawn_point(target_map)
			if spawn.x > -9999.0 and spawn.y > -9999.0:
				target_spawn = spawn
			p_state.world["location_id"] = location_id
			p_state.world["player_x"] = target_spawn.x
			p_state.world["player_y"] = target_spawn.y
	elif spawn.x > -9999.0 and spawn.y > -9999.0:
		p_state.world["player_x"] = spawn.x
		p_state.world["player_y"] = spawn.y
	_last_season = p_state.calendar.get_season()
	return {
		"applied": season != "" or time_value != "" or weather_id != "" \
			or location_id != "" or spawn.x > -9999.0,
		"season": p_state.calendar.get_season(),
		"minute_of_day": p_state.clock.minute_of_day,
		"weather": p_state.weather.today,
		"location_id": p_state.world.get("location_id", ""),
	}

func _parse_capture_time(value: String) -> int:
	var parts := value.split(":", true, 1)
	if parts.size() != 2:
		return -1
	var hour := int(parts[0])
	var minute := int(parts[1])
	if hour < 0 or hour > 26 or minute < 0 or minute > 59:
		return -1
	return clampi(hour * 60 + minute, GameClock.DAY_START_MINUTE, GameClock.DAY_END_MINUTE)

func _process(delta: float) -> void:
	if state == null or is_paused() or input_locked:
		return
	var advanced := state.clock.tick(delta)
	if advanced <= 0:
		return
	clock_changed.emit(state.clock.minute_of_day)
	if state.clock.should_force_sleep():
		_collapse_from_exhaustion()

## 农活不只是扣体力,也应当消耗当天时间。否则玩家可以在 06:00 一口气干完
## 所有活,游戏日却完全没有流动感。
func spend_time(minutes: int) -> void:
	if state == null or minutes <= 0:
		return
	state.clock.advance_minutes(minutes)
	clock_changed.emit(state.clock.minute_of_day)
	if state.clock.should_force_sleep():
		_collapse_from_exhaustion()

## 新游戏/回主菜单后统一重置会话级状态,避免上一局的锁和季节缓存残留。
func new_session() -> void:
	state = GameState.new()
	state.weather.refresh(state.calendar, state.weather.seed)
	_last_season = state.calendar.get_season()
	modal_stack.clear()
	_paused = false

## 睡醒后体力回满(麦溪镇农活是重体力活,一天干不动太多活)
func rest_and_recover() -> void:
	if state.player.stamina != null:
		state.player.stamina.sleep()

## 推进一个游戏日(供 UI/调试/自动推进调用)
func advance_day() -> void:
	state.calendar.advance_day()
	state.weather.refresh(state.calendar, state.weather.seed)
	state.farm.apply_weather(state.weather.today, state.calendar.abs_day())
	state.farm.advance_day()
	var shipping_report := ShippingSystem.settle(state)
	var livestock_report := LivestockSystem.advance_day(state)
	CraftingSystem.apply_sprinklers(state)
	var delivered := PostcardSystem.deliver_due(state, state.calendar)
	rest_and_recover()
	state.clock.reset()
	var s := state.calendar.get_season()
	if s != _last_season:
		_last_season = s
		season_changed.emit(s)
	day_started.emit(state.calendar.day_of_year)
	if not delivered.is_empty():
		postcards_delivered.emit(delivered)
	if bool(shipping_report.get("ok", false)):
		shipping_settled.emit(shipping_report)
	if bool(livestock_report.get("ok", false)):
		livestock_produced.emit(livestock_report)

## 02:00 未睡:强制结算，次日体力只有六成，不死亡、不删档。
func _collapse_from_exhaustion() -> void:
	state.flags["collapsed_last_night"] = true
	advance_day()
	state.player.stamina.energy = 60
	player_collapsed.emit()

## 存档
func save_game(slot: int = 0) -> bool:
	var path := "%s/slot_%d.json" % [SAVE_DIR, slot]
	var payload := JSON.stringify(state.to_dict())
	if not SaveMigrator.atomic_write(path, payload):
		push_error("存档原子写入失败 slot=%d" % slot)
		return false
	if SaveSync.is_configured() and not SaveSync.push_slot(slot, payload):
		push_warning("本地存档成功,但云目录镜像失败 slot=%d" % slot)
	game_saved.emit(slot)
	return true

## 读档
func load_game(slot: int = 0) -> bool:
	var path := "%s/slot_%d.json" % [SAVE_DIR, slot]
	var payload := ""
	var from_cloud := false
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			payload = f.get_as_text()
			f.close()
	if payload == "":
		payload = SaveSync.pull_slot(slot)
		from_cloud = payload != ""
	if payload == "":
		return false
	var parsed: Variant = JSON.parse_string(payload)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	# 云端档校验通过后落一份本地缓存,下次离线启动仍然能继续。
	if from_cloud:
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)
		var cache := FileAccess.open(path, FileAccess.WRITE)
		if cache != null:
			cache.store_string(payload)
			cache.close()
	state = GameState.from_dict(parsed)
	_last_season = state.calendar.get_season()
	modal_stack.clear()
	_paused = false
	return true

func has_save(slot: int = 0) -> bool:
	return FileAccess.file_exists("%s/slot_%d.json" % [SAVE_DIR, slot]) \
		or SaveSync.has_slot(slot)

func set_paused(p: bool) -> void:
	_paused = p

func is_paused() -> bool:
	return _paused

## 空间门请求:连同目标出生点一起交给游戏外壳，避免落点正好压在返程门上。
func request_travel(location_id: String, spawn: Vector2 = Vector2(-1, -1)) -> void:
	pending_spawn = spawn
	travel_requested.emit(location_id)

## 对话开始/结束时占用或归还输入
func set_dialogue_open(v: bool) -> void:
	if v:
		modal_stack.push("dialogue")
	else:
		modal_stack.pop("dialogue")

## 背包开合时占用或归还输入
func set_inventory_open(v: bool) -> void:
	if v:
		modal_stack.push("inventory")
	else:
		modal_stack.pop("inventory")

## 邮册开合时占用或归还输入
func set_postcard_open(v: bool) -> void:
	if v:
		modal_stack.push("postcard")
	else:
		modal_stack.pop("postcard")

func set_shop_open(v: bool) -> void:
	if v:
		modal_stack.push("shop")
	else:
		modal_stack.pop("shop")

func set_fishing_open(v: bool) -> void:
	if v:
		modal_stack.push("fishing")
	else:
		modal_stack.pop("fishing")

func set_cooking_open(v: bool) -> void:
	if v:
		modal_stack.push("cooking")
	else:
		modal_stack.pop("cooking")

func set_quest_open(v: bool) -> void:
	if v:
		modal_stack.push("quest")
	else:
		modal_stack.pop("quest")

func set_service_open(v: bool) -> void:
	if v:
		modal_stack.push("service")
	else:
		modal_stack.pop("service")

func set_drama_open(v: bool) -> void:
	if v:
		modal_stack.push("drama")
	else:
		modal_stack.pop("drama")

func set_gift_open(v: bool) -> void:
	if v:
		modal_stack.push("gift")
	else:
		modal_stack.pop("gift")
