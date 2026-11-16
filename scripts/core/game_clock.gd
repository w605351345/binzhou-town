extends RefCounted
class_name GameClock

## 游戏内时钟。一天 06:00 开始,26:00(次日 02:00)强制结算。
## 纯逻辑,可在 headless 下测试;真实秒到游戏分钟的换算由 tick() 负责。

const DAY_START_MINUTE := 6 * 60
const DAY_END_MINUTE := 26 * 60
const MINUTES_PER_DAY := DAY_END_MINUTE - DAY_START_MINUTE
## 1 游戏分钟 = 0.9 现实秒，完整一天约 18 分钟。
const REAL_SECONDS_PER_GAME_MINUTE := 0.9

var minute_of_day: int = DAY_START_MINUTE
var _accum: float = 0.0

func _init(p_minute: int = DAY_START_MINUTE) -> void:
	minute_of_day = clampi(p_minute, DAY_START_MINUTE, DAY_END_MINUTE)

## 推进现实时间。返回本次推进了多少游戏分钟。
func tick(real_delta: float) -> int:
	if real_delta <= 0.0:
		return 0
	_accum += real_delta
	var advanced := int(floor(_accum / REAL_SECONDS_PER_GAME_MINUTE))
	if advanced <= 0:
		return 0
	_accum -= float(advanced) * REAL_SECONDS_PER_GAME_MINUTE
	advance_minutes(advanced)
	return advanced

func advance_minutes(minutes: int) -> void:
	if minutes <= 0:
		return
	minute_of_day = mini(minute_of_day + minutes, DAY_END_MINUTE)

func reset() -> void:
	minute_of_day = DAY_START_MINUTE
	_accum = 0.0

func should_force_sleep() -> bool:
	return minute_of_day >= DAY_END_MINUTE

func is_night() -> bool:
	return minute_of_day >= 18 * 60

func is_late_night() -> bool:
	return minute_of_day >= 24 * 60

func phase() -> String:
	if minute_of_day < 8 * 60:
		return "dawn"
	if minute_of_day < 12 * 60:
		return "morning"
	if minute_of_day < 14 * 60:
		return "noon"
	if minute_of_day < 18 * 60:
		return "afternoon"
	if minute_of_day < 21 * 60:
		return "dusk"
	if minute_of_day < 24 * 60:
		return "night"
	return "late_night"

func time_string() -> String:
	var hour := int(floor(float(minute_of_day) / 60.0)) % 24
	var minute := minute_of_day % 60
	return "%02d:%02d" % [hour, minute]

func phase_cn() -> String:
	match phase():
		"dawn": return "清晨"
		"morning": return "上午"
		"noon": return "正午"
		"afternoon": return "下午"
		"dusk": return "黄昏"
		"night": return "夜晚"
		"late_night": return "深夜"
	return "深夜"

func to_dict() -> Dictionary:
	return {"minute_of_day": minute_of_day}

static func from_dict(d: Dictionary) -> GameClock:
	return GameClock.new(int(d.get("minute_of_day", DAY_START_MINUTE)))
