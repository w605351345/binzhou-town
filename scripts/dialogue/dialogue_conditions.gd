extends RefCounted
class_name DialogueConditions

## 对话条件求值(纯逻辑,可 headless 单测)
##
## 条件是一段字典,支持以下键(全部可选,空条件 = 恒真):
##   "season"        : ["spring", "summer"]  当前季节在列表内
##   "month"         : [4, 5]               当前真实月份在列表内
##   "affection_min" : 10                   NPC 好感度 ≥ 值
##   "flag"          : "xxx"                该 flag 为真
##   "not_flag"      : "xxx"                该 flag 不为真
##   "has_item"      : {"id": "corn", "count": 3}  背包里至少有这么多
##   "gold_min"      : 100                  金币 ≥ 值
##   "time_from"     : "19:00"              当前游戏时间 ≥ 该时刻
##   "time_to"       : "21:00"              当前游戏时间 < 该时刻
##   "weather"       : ["rain", "snow"]     当前天气；rain/snow 是天气组
##   "weekday"       : [0, 3]               星期(0=周一)
##   "event_done"    : "zhang_e1"           指定好感事件已完成
##   "not_event_done": "zhang_e2"           指定好感事件尚未完成
##
## 上下文 ctx 字典需要提供:
##   {"calendar": GameCalendar, "player": PlayerProfile, "npc": NpcBase, "flags": Dictionary}

static func evaluate(condition: Dictionary, ctx: Dictionary) -> bool:
	if condition.is_empty():
		return true

	var calendar: GameCalendar = ctx.get("calendar", null)
	var player: PlayerProfile = ctx.get("player", null)
	var npc: NpcBase = ctx.get("npc", null)
	var flags: Dictionary = ctx.get("flags", {})
	var events: Dictionary = ctx.get("events", {})
	var clock: GameClock = ctx.get("clock", null)

	# 季节
	if condition.has("season"):
		var allowed := _as_list(condition.get("season", []))
		if calendar == null or not allowed.has(calendar.get_season()):
			return false

	# 真实月份
	if condition.has("month"):
		var months := _as_list(condition.get("month", []))
		if calendar == null or not months.has(calendar.get_real_month()):
			return false

	# 好感度
	if condition.has("affection_min"):
		if npc == null or npc.affection < int(condition.get("affection_min", 0)):
			return false

	# 标记
	if condition.has("flag"):
		if not bool(flags.get(String(condition.get("flag", "")), false)):
			return false
	if condition.has("not_flag"):
		if bool(flags.get(String(condition.get("not_flag", "")), false)):
			return false

	# 背包
	if condition.has("has_item"):
		var need: Dictionary = condition.get("has_item", {})
		if player == null:
			return false
		var have := int(player.inventory.get(String(need.get("id", "")), 0))
		if have < int(need.get("count", 1)):
			return false

	# 金币
	if condition.has("gold_min"):
		if player == null or player.gold < int(condition.get("gold_min", 0)):
			return false

	if condition.has("time_from") or condition.has("time_to"):
		if clock == null:
			return false
		if clock.minute_of_day < _minute(String(condition.get("time_from", "00:00"))):
			return false
		if clock.minute_of_day >= _minute(String(condition.get("time_to", "24:00"))):
			return false

	if condition.has("weather"):
		if calendar == null:
			return false
		if not _weather_matches(condition.get("weather", []), _ctx_weather(ctx)):
			return false

	if condition.has("weekday"):
		if calendar == null or not _as_list(condition.get("weekday", [])).has(
				calendar.abs_day() % 7):
			return false

	var done: Array = events.get("done", []) if events is Dictionary else []
	if condition.has("event_done") and not done.has(String(condition.get("event_done", ""))):
		return false
	if condition.has("not_event_done") \
			and done.has(String(condition.get("not_event_done", ""))):
		return false

	return true

static func _ctx_weather(ctx: Dictionary) -> String:
	var weather: Variant = ctx.get("weather", null)
	if weather is String:
		return String(weather)
	if weather is Dictionary:
		return String(weather.get("today", "sunny"))
	if weather is WeatherSystem:
		return weather.today
	return "sunny"

static func _weather_matches(wanted: Variant, actual: String) -> bool:
	for raw in _as_list(wanted):
		var item := String(raw)
		if item == actual:
			return true
		if item == "rain" and WeatherSystem.waters_crops(actual):
			return true
		if item == "snow" and WeatherSystem.is_snow(actual):
			return true
		if item == "storm" and actual in [WeatherSystem.BLIZZARD, "thunderstorm", "rainstorm"]:
			return true
	return false

static func _minute(hhmm: String) -> int:
	var parts := hhmm.split(":")
	if parts.size() < 2:
		return 0
	return int(parts[0]) * 60 + int(parts[1])

## 条件值统一成列表:写 "spring" 或 ["spring","summer"] 都认。
## 注意:Godot 的 JSON 解析会把所有数字读成 float,JSON 里的 [9, 10] 实际是 [9.0, 10.0],
## 所以这里要把数字统一转回 int,否则和 get_real_month() 的 int 对不上。
static func _as_list(value: Variant) -> Array:
	if value is Array:
		var out: Array = []
		for item in value:
			if item is float or item is int:
				out.append(int(item))
			else:
				out.append(item)
		return out
	if value == null:
		return []
	return [value]

## 生成"条件不满足"的原因,用于调试与自测输出
static func describe(condition: Dictionary, ctx: Dictionary) -> String:
	if evaluate(condition, ctx):
		return "满足"
	var parts: Array = []
	for key in condition.keys():
		parts.append("%s=%s" % [key, str(condition[key])])
	return "不满足(%s)" % " ".join(parts)
