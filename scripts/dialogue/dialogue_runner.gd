extends RefCounted
class_name DialogueRunner

## 对话运行时:按对话表推进,处理玩家选项与动作。
##
## 刻意做成纯逻辑(不碰节点)—— UI 层(dialogue_box)只负责显示文本与转发点击。
## 这样对话内容与走向可以在 headless 下完整自测。

## 动作:由 UI 层接手
const ACTION_SHOP_SELL := "shop_sell"
const ACTION_SHOP_BUY := "shop_buy"
## 动作:运行时自己执行
const ACTION_SET_FLAG := "set_flag"
const ACTION_ADD_AFFECTION := "add_affection"
const ACTION_GIVE_ITEM := "give_item"

var _lines: Array = []
var _index: int = -1
var _player: PlayerProfile = null
var _calendar: GameCalendar = null
var _npc: NpcBase = null
var _flags: Dictionary = {}
var _finished: bool = true
var _visited: Array = []

func setup(lines: Array, player: PlayerProfile, calendar: GameCalendar,
		npc: NpcBase = null, flags: Dictionary = {}) -> void:
	_lines = lines
	_player = player
	_calendar = calendar
	_npc = npc
	_flags = flags
	_index = -1
	_finished = true
	_visited.clear()

## 开始对话:定位到第一条满足条件的条目
func start() -> void:
	_index = -1
	_finished = false
	_visited.clear()
	_move_to_next_valid()

## 当前条目
func current_line() -> Dictionary:
	if _index < 0 or _index >= _lines.size():
		return {}
	return _lines[_index]

## 当前台词文本
func current_text() -> String:
	var line := current_line()
	# 一个条目可以有多个文本变体(如同一句开场白分春夏秋冬),
	# 取第一个满足条件的变体;没有变体就用条目自身的 text。
	var texts: Array = line.get("texts", [])
	for variant in texts:
		if variant is Dictionary and DialogueConditions.evaluate(variant.get("condition", {}), _ctx()):
			return String(variant.get("text", ""))
	return String(line.get("text", ""))

## 当前条目的 id(语音包按 <npc>__<line>__<variant> 命名,要靠它定位音频)
func current_line_id() -> String:
	return String(current_line().get("id", ""))

## 当前台词是第几个文本变体(0 起)。语音包按变体分别录制,这里给出下标。
func current_variant_index() -> int:
	var line := current_line()
	var texts: Array = line.get("texts", [])
	for i in texts.size():
		var variant: Variant = texts[i]
		if variant is Dictionary and DialogueConditions.evaluate(variant.get("condition", {}), _ctx()):
			return i
	return 0

## 当前条目可见的选项(条件不满足的已过滤掉)
func current_options() -> Array:
	var out: Array = []
	for opt in current_line().get("options", []):
		if opt is Dictionary and DialogueConditions.evaluate(opt.get("condition", {}), _ctx()):
			out.append(opt)
	return out

func is_finished() -> bool:
	return _finished

## 已走过的条目 id(用于"这个话题聊过了"这类判断)
func visited() -> Array:
	return _visited.duplicate()

func _ctx() -> Dictionary:
	return {
		"calendar": _calendar,
		"player": _player,
		"npc": _npc,
		"flags": _flags,
	}

## 推进到下一条满足条件的条目(无选项条目靠它往下走)
## 返回 true = 还有话可说;false = 对话结束
func advance() -> bool:
	if _finished:
		return false
	if not current_line().get("options", []).is_empty():
		return true  # 有选项时必须让玩家选,不能自己跳过
	_move_to_next_valid()
	return not _finished

## 玩家选了第 index 个选项。
## 返回:
##   {"type": "line", "text": "..."}          跳到了新条目
##   {"type": "action", "action": "...", "data": {...}}  需要 UI 执行的动作
##   {"type": "end"}                          对话结束
func choose(option_index: int) -> Dictionary:
	var options := current_options()
	if option_index < 0 or option_index >= options.size():
		return {"type": "end"}
	var opt: Dictionary = options[option_index]

	# 先处理动作:选项可以既做动作又跳转(如"今年我也翻"→ 记标记 + 回到开场白)。
	# 顺序反了的话,带 next 的选项会把 action 悄悄吞掉。
	if opt.has("action"):
		var action := String(opt.get("action", ""))
		var data: Dictionary = opt.get("data", {})
		var handled := _run_action(action, data)
		if handled:
			# 需要 UI 接手(商店),先不跳转
			return {"type": "action", "action": action, "data": data}

	# 再处理跳转
	var has_next := opt.has("next")
	var next_raw: Variant = opt.get("next", "")
	var next_id := "" if next_raw == null else String(next_raw)
	if has_next and next_id != "":
		_goto_line(next_id)
		if _finished:
			return {"type": "end"}
		return {"type": "line", "text": current_text()}

	# 走到这里 = 选项没有 next 也没有 action(或动作已内部处理完)
	_finished = true
	return {"type": "end"}

## 内部动作:改 flag / 加好感度 / 给东西
func _run_action(action: String, data: Dictionary) -> bool:
	match action:
		ACTION_SET_FLAG:
			_flags[String(data.get("flag", ""))] = bool(data.get("value", true))
			return false
		ACTION_ADD_AFFECTION:
			if _npc != null:
				_npc.affection = maxi(0, _npc.affection + int(data.get("amount", 1)))
			return false
		ACTION_GIVE_ITEM:
			if _player != null:
				var item_id := String(data.get("id", ""))
				if item_id != "":
					var count := int(data.get("count", 1))
					_player.inventory[item_id] = int(_player.inventory.get(item_id, 0)) + count
			return false
	return true  # 商店这类动作交给 UI

## 跳到指定条目;找不到或条件不满足则结束对话
func _goto_line(line_id: String) -> void:
	for i in _lines.size():
		var line: Dictionary = _lines[i]
		if String(line.get("id", "")) != line_id:
			continue
		if not DialogueConditions.evaluate(line.get("condition", {}), _ctx()):
			_finished = true
			return
		_index = i
		_visited.append(line_id)
		return
	_finished = true

## 往下找第一条满足条件的条目
func _move_to_next_valid() -> void:
	for i in range(_index + 1, _lines.size()):
		var line: Dictionary = _lines[i]
		if not DialogueConditions.evaluate(line.get("condition", {}), _ctx()):
			continue
		_index = i
		_visited.append(String(line.get("id", "")))
		return
	_finished = true
