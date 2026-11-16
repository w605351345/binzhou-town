extends RefCounted
class_name FishingSystem

## 一次钓鱼的纯逻辑状态机: waiting → bite → success/missed。

const FISH_PATH := "res://data/fish.json"
static var _fish: Array = []
static var _loaded := false

var state := "idle"
var _target: Dictionary = {}
var _elapsed := 0.0
var _bite_at := 0.0
var _bite_left := 0.0
var _window := 1.15
var _finished := false
var _result: Dictionary = {}

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(FISH_PATH, FileAccess.READ)
	if f == null:
		push_error("鱼种数据不存在: %s" % FISH_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_fish = Array(parsed.get("fish", []))

static func all_fish() -> Array:
	_ensure_loaded()
	return _fish.duplicate(true)

static func fish_for_season(season: String) -> Array:
	_ensure_loaded()
	var out: Array = []
	for raw in _fish:
		if Array(raw.get("seasons", [])).has(season):
			out.append(raw.duplicate(true))
	return out

func start(seed: int, season: String = "spring", bait_bonus: float = 0.0) -> void:
	_ensure_loaded()
	var pool := fish_for_season(season)
	if pool.is_empty():
		pool = _fish.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) ^ 16057
	var total := 0
	for fish in pool:
		total += int(fish.get("weight", 1))
	var pick := rng.randi_range(1, maxi(1, total))
	var cursor := 0
	_target = pool.back()
	for fish in pool:
		cursor += int(fish.get("weight", 1))
		if pick <= cursor:
			_target = fish
			break
	_elapsed = 0.0
	_bite_at = rng.randf_range(0.8, 2.8)
	_window = (0.8 + 0.15 * float(_target.get("difficulty", 1))) * (1.0 + maxf(0.0, bait_bonus))
	_bite_left = _window
	_finished = false
	_result = {}
	state = "waiting"

func target_fish() -> Dictionary:
	return _target.duplicate(true)

func tick(delta: float) -> String:
	if _finished or state == "idle":
		return state
	if state == "waiting":
		_elapsed += delta
		if _elapsed >= _bite_at:
			state = "bite"
		return state
	if state == "bite":
		_bite_left -= delta
		if _bite_left <= 0.0:
			_finished = true
			state = "missed"
			_result = {"ok": false, "reason": "missed", "message": "手慢了，鱼跑了。"}
	return state

func reel() -> Dictionary:
	if _finished:
		return _result.duplicate(true) if not _result.is_empty() else {
			"ok": false, "reason": "finished", "message": "这一竿已经收了。"}
	if state != "bite":
		return {"ok": false, "reason": "too_early", "message": "鱼还没咬钩，别急着拽。"}
	_finished = true
	state = "caught"
	var name := String(_target.get("name", "鱼"))
	_result = {
		"ok": true, "reason": "caught", "fish_id": String(_target.get("id", "")),
		"name": name, "count": 1, "message": "钓到一条%s！" % name,
	}
	return _result.duplicate(true)

func is_finished() -> bool:
	return _finished

func current_state() -> String:
	return state

func result() -> Dictionary:
	return _result.duplicate(true)
