extends SceneTree
## headless 输入映射自测:手柄必须能覆盖全部可玩动作。
##
## 运行: godot --headless --script res://scripts/tests/test_input_map.gd
##
## 这组测试守住一条底线:**手柄玩家不能因为漏绑而玩不了**。
## Steam Deck 与主机玩家只有手柄,漏绑一个动作就等于玩不了那一半内容。

var _passed := 0
var _failed := 0

## 每个动作都必须有手柄绑定
const REQUIRED_JOYPAD_ACTIONS := [
	"move_left", "move_right", "move_up", "move_down",
	"interact",
	"tool_till", "tool_water", "tool_seed", "tool_harvest", "tool_plough",
	"sleep", "travel",
	"ui_pause", "ui_inventory",
]

## 这些动作必须同时保留键盘绑定(键鼠玩家不能被手柄改动牵连)
const REQUIRED_KEY_ACTIONS := [
	"move_left", "move_right", "move_up", "move_down",
	"interact", "tool_till", "tool_water", "tool_seed", "tool_harvest",
	"tool_plough", "sleep", "travel", "ui_pause", "ui_inventory",
]

func _init() -> void:
	print("=== 《宾州小镇》输入映射自测 (手柄 / 键鼠) ===")
	print("--------------------------------------------------")
	_test_actions_exist()
	_test_joypad_covered()
	_test_keyboard_kept()
	_test_no_duplicate_conflicts()
	print("--------------------------------------------------")
	print("结果: %d 通过 / %d 失败" % [_passed, _failed])
	if _failed > 0:
		print("❌ TEST FAILED")
		quit(1)
	else:
		print("✅ ALL TESTS PASSED")
		quit(0)

func check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ✅ %s %s" % [label, detail])
	else:
		_failed += 1
		print("  ❌ %s %s" % [label, detail])

func _test_actions_exist() -> void:
	print("\n[1] 动作都存在")
	for action in REQUIRED_KEY_ACTIONS:
		check("动作存在:%s" % action, InputMap.has_action(action))

func _test_joypad_covered() -> void:
	print("\n[2] 手柄覆盖全部动作")
	for action in REQUIRED_JOYPAD_ACTIONS:
		var events := InputMap.action_get_events(action)
		var joy_count := 0
		for e in events:
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				joy_count += 1
		check("手柄已绑定:%s" % action, joy_count > 0, "(%d 个事件)" % joy_count)

func _test_keyboard_kept() -> void:
	print("\n[3] 键盘绑定仍在")
	for action in REQUIRED_KEY_ACTIONS:
		var events := InputMap.action_get_events(action)
		var key_count := 0
		for e in events:
			if e is InputEventKey:
				key_count += 1
		check("键盘仍可用:%s" % action, key_count > 0, "(%d 个按键)" % key_count)

func _test_no_duplicate_conflicts() -> void:
	print("\n[4] 手柄按钮不重复占用")
	# 一个手柄按钮被两个互斥动作抢(比如翻土和浇水同一个键)就是 bug
	var used := {}
	var conflicts: Array = []
	for action in REQUIRED_JOYPAD_ACTIONS:
		for e in InputMap.action_get_events(action):
			if not (e is InputEventJoypadButton):
				continue
			var idx: int = (e as InputEventJoypadButton).button_index
			if used.has(idx):
				conflicts.append("%s 与 %s 抢 %d 号键" % [used[idx], action, idx])
			else:
				used[idx] = action
	check("无按钮冲突", conflicts.is_empty(),
		"" if conflicts.is_empty() else "→ " + ", ".join(conflicts))
