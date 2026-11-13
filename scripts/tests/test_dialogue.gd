extends SceneTree
## headless 对话系统自测:条件求值 + 对话推进 + 选项与动作
##
## 对话走向全在 DialogueRunner(纯逻辑)里,所以这里能在 headless 下
## 把张晓芳的每一句话、每一个分支都走一遍。
##
## 运行: godot --headless --script res://scripts/tests/test_dialogue.gd

var _passed := 0
var _failed := 0

func _init() -> void:
	print("=== 《宾州小镇》对话系统自测 (dialogue test) ===")
	print("设定:张晓芳是玩家理解『一年一熟』的活教材 —— 台词必须挂在农时上")
	print("--------------------------------------------------")

	test_dialogue_data()
	test_conditions()
	test_seasonal_greeting()
	test_option_filter()
	test_topic_navigation()
	test_shop_actions()
	test_flag_and_affection_actions()
	test_integration_with_npc()

	print("--------------------------------------------------")
	print("结果: %d 通过 / %d 失败" % [_passed, _failed])
	if _failed > 0:
		print("❌ TEST FAILED")
		quit(1)
	else:
		print("✅ ALL TESTS PASSED")
		quit(0)

func check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  ✅ %s %s" % [label, detail])
	else:
		_failed += 1
		print("  ❌ %s %s" % [label, detail])

func _make_ctx(month: int = 4, affection: int = 0, flags: Dictionary = {}) -> Dictionary:
	var cal := GameCalendar.new()
	cal.advance_to_month(month, 1)
	var player := PlayerProfile.new()
	player.gold = 500
	var npc := ZhangXiaofang.new()
	npc.affection = affection
	return {"calendar": cal, "player": player, "npc": npc, "flags": flags}

# --- 对话数据 ---
func test_dialogue_data() -> void:
	print("\n[1] 对话数据(dialogues.json)")
	check("dialogues.json 可读", not DialogueData.load_all().is_empty())
	check("张晓芳的对话存在", not DialogueData.get_dialogue("zhang_xiaofang").is_empty())
	check("能按 NPC 找到对话",
		String(DialogueData.dialogue_for_npc("zhang_xiaofang").get("id", "")) == "zhang_xiaofang")
	var lines: Array = DialogueData.get_dialogue("zhang_xiaofang").get("lines", [])
	check("张晓芳对话条目 >= 7 条(Week 4 要求完整对话)", lines.size() >= 7,
		"→ %d 条" % lines.size())

	# 每条对话都该有个像样的开场白
	var greet: Dictionary = {}
	for line in lines:
		if String(line.get("id", "")) == "greet":
			greet = line
	check("有开场白条目", not greet.is_empty())
	var variants: Array = greet.get("texts", [])
	check("开场白覆盖四季", variants.size() == 4, "→ %d 个变体" % variants.size())
	for v in variants:
		var variant_text := String(v.get("text", ""))
		check("开场白变体有文本且不空",
			variant_text != "" and variant_text.ends_with("。"),
			variant_text.substr(0, 12) + "…")

	# 台词必须跟农时挂钩(设计核心:她是活教材)
	var all_text := ""
	for line in lines:
		for v in line.get("texts", [line]):
			all_text += String(v.get("text", "")) + String(line.get("text", ""))
	check("台词提到播种/下种", all_text.contains("种"), "")
	check("台词提到霜", all_text.contains("霜"), "")
	check("台词提到翻地/秋翻", all_text.contains("翻"), "")
	check("台词提到冬天/猫冬", all_text.contains("冬"), "")

# --- 条件求值 ---
func test_conditions() -> void:
	print("\n[2] 对话条件求值")
	var ctx := _make_ctx(4)
	check("空条件恒真", DialogueConditions.evaluate({}, ctx))
	check("季节条件命中",
		DialogueConditions.evaluate({"season": ["spring"]}, ctx))
	check("季节条件不命中",
		not DialogueConditions.evaluate({"season": ["winter"]}, ctx))
	check("月份条件命中",
		DialogueConditions.evaluate({"month": [4, 5]}, ctx))
	check("月份条件不命中",
		not DialogueConditions.evaluate({"month": [7]}, ctx))
	check("好感度条件命中",
		DialogueConditions.evaluate({"affection_min": 10}, _make_ctx(4, 20)))
	check("好感度条件不命中",
		not DialogueConditions.evaluate({"affection_min": 30}, _make_ctx(4, 20)))
	check("flag 条件命中",
		DialogueConditions.evaluate({"flag": "met"}, _make_ctx(4, 0, {"met": true})))
	check("flag 条件不命中",
		not DialogueConditions.evaluate({"flag": "met"}, _make_ctx(4, 0, {})))
	check("not_flag 条件命中",
		DialogueConditions.evaluate({"not_flag": "met"}, _make_ctx(4, 0, {})))
	check("金币条件命中",
		DialogueConditions.evaluate({"gold_min": 100}, ctx))
	check("金币条件不命中",
		not DialogueConditions.evaluate({"gold_min": 9999}, ctx))

	# 背包条件
	ctx["player"].inventory["corn"] = 3
	check("背包条件命中",
		DialogueConditions.evaluate({"has_item": {"id": "corn", "count": 3}}, ctx))
	check("背包条件不够时",
		not DialogueConditions.evaluate({"has_item": {"id": "corn", "count": 5}}, ctx))
	check("背包里没有的物品",
		not DialogueConditions.evaluate({"has_item": {"id": "potato", "count": 1}}, ctx))

# --- 开场白随季节变化 ---
func test_seasonal_greeting() -> void:
	print("\n[3] 开场白随季节变化(张晓芳的农时活教材)")
	var expected := {
		4: "地化冻",
		7: "庄稼正长",
		10: "霜要下来了",
		1: "猫冬",
	}
	for month in expected.keys():
		var cal := GameCalendar.new()
		cal.advance_to_month(int(month), 1)
		var runner := DialogueRunner.new()
		runner.setup(_lines(), PlayerProfile.new(), cal, ZhangXiaofang.new(), {})
		runner.start()
		check("%d 月开场白对得上农时" % int(month),
			runner.current_text().contains(String(expected[month])),
			"→ " + runner.current_text().substr(0, 20) + "…")

# --- 选项按条件过滤 ---
func test_option_filter() -> void:
	print("\n[4] 选项按条件过滤")
	var cal := GameCalendar.new()
	cal.advance_to_month(4, 1)
	var runner := DialogueRunner.new()
	runner.setup(_lines(), PlayerProfile.new(), cal, ZhangXiaofang.new(), {})
	runner.start()
	var options := runner.current_options()
	check("开场白有选项", options.size() > 0, "→ %d 个" % options.size())
	var texts: Array = []
	for o in options:
		texts.append(String(o.get("text", "")))
	check("有『卖粮』选项", texts.has("卖粮"))
	check("有『买种子』选项", texts.has("买种子"))
	check("有『秋霜啥时候来?』选项", texts.has("秋霜啥时候来?"))
	check("有收尾选项", texts.has("没别的了,走了"))

	# 带条件的选项:好感度不够时不该出现
	var runner2 := DialogueRunner.new()
	runner2.setup(_familiar_lines(), PlayerProfile.new(), cal, ZhangXiaofang.new(), {})
	runner2.start()
	check("低好感度看不到熟络台词",
		not runner2.current_text().contains("记着"),
		"→ " + runner2.current_text().substr(0, 16) + "…")
	var npc_hi := ZhangXiaofang.new()
	npc_hi.affection = 30
	var runner3 := DialogueRunner.new()
	runner3.setup(_familiar_lines(), PlayerProfile.new(), cal, npc_hi, {})
	runner3.start()
	check("高好感度能看到熟络台词",
		runner3.current_text().contains("记着"),
		"→ " + runner3.current_text().substr(0, 16) + "…")

# --- 话题跳转 ---
func test_topic_navigation() -> void:
	print("\n[5] 话题跳转(问一句答一句)")
	var cal := GameCalendar.new()
	cal.advance_to_month(9, 15)
	var runner := DialogueRunner.new()
	runner.setup(_lines(), PlayerProfile.new(), cal, ZhangXiaofang.new(), {})
	runner.start()
	check("开场白是秋收那句", runner.current_text().contains("霜"), "→ " + runner.current_text().substr(0, 18) + "…")

	# 选『秋霜啥时候来?』
	var idx := _find_option(runner, "秋霜啥时候来?")
	check("找到秋霜话题选项", idx >= 0)
	var result := runner.choose(idx)
	check("跳转成功", String(result.get("type", "")) == "line",
		"→ " + String(result.get("type", "")))
	check("答的是霜的事", runner.current_text().contains("霜降"),
		"→ " + runner.current_text().substr(0, 20) + "…")
	check("话题里没有选项时给『继续』", runner.current_options().size() == 1
		and String(runner.current_options()[0].get("text", "")) == "知道了")

	# 答完可以回到开场白
	var back := runner.choose(0)
	check("回到开场白", String(back.get("type", "")) == "line"
		and runner.current_text().contains("霜"), "→ " + runner.current_text().substr(0, 18) + "…")

	# 收尾选项结束对话
	var end_idx := _find_option(runner, "没别的了,走了")
	var end_result := runner.choose(end_idx)
	check("选『走了』结束对话", String(end_result.get("type", "")) == "end")
	check("对话标记为结束", runner.is_finished())

# --- 商店动作 ---
func test_shop_actions() -> void:
	print("\n[6] 商店动作(卖粮/买种子)")
	var cal := GameCalendar.new()
	cal.advance_to_month(9, 15)
	var runner := DialogueRunner.new()
	runner.setup(_lines(), PlayerProfile.new(), cal, ZhangXiaofang.new(), {})
	runner.start()
	var sell_idx := _find_option(runner, "卖粮")
	var r1 := runner.choose(sell_idx)
	check("『卖粮』触发商店动作",
		String(r1.get("type", "")) == "action"
		and String(r1.get("action", "")) == "shop_sell",
		"→ " + String(r1.get("action", "")))
	check("商店动作后对话还开着(可以接着聊)", not runner.is_finished())

	var buy_idx := _find_option(runner, "买种子")
	var r2 := runner.choose(buy_idx)
	check("『买种子』触发商店动作",
		String(r2.get("type", "")) == "action"
		and String(r2.get("action", "")) == "shop_buy",
		"→ " + String(r2.get("action", "")))

# --- flag / 好感度动作 ---
func test_flag_and_affection_actions() -> void:
	print("\n[7] 标记与好感度动作")
	var flags := {}
	var cal := GameCalendar.new()
	cal.advance_to_month(4, 1)
	var npc := ZhangXiaofang.new()
	var runner := DialogueRunner.new()
	runner.setup(_action_lines(), PlayerProfile.new(), cal, npc, flags)
	runner.start()
	var aff_idx := _find_option(runner, "聊得挺好")
	runner.choose(aff_idx)
	check("好感度加了", npc.affection > 0, "→ %d" % npc.affection)

	var flag_idx := _find_option(runner, "记个事")
	runner.choose(flag_idx)
	check("flag 写进去了", bool(flags.get("talked_sow", false)), "→ " + str(flags))

# --- 与 NPC 串起来 ---
func test_integration_with_npc() -> void:
	print("\n[8] 与张晓芳本体串起来")
	var cal := GameCalendar.new()
	cal.advance_to_month(4, 10)
	var npc := ZhangXiaofang.new()
	var player := PlayerProfile.new()
	player.inventory["corn"] = 4
	var runner := DialogueRunner.new()
	runner.setup(_lines(), player, cal, npc, {})
	runner.start()
	check("能拿到张晓芳的台词", runner.current_text() != "", "→ " + runner.current_text().substr(0, 18) + "…")

	# 卖粮后金币增加(走 NpcBase.buy_crop,和对话用同一套价格)
	var gold_before := player.gold
	var sell := npc.buy_crop(player, "corn", 4)
	check("卖粮成功", bool(sell.get("ok")), "→ " + String(sell.get("message", "")))
	check("金币涨了", player.gold > gold_before,
		"→ %d → %d" % [gold_before, player.gold])
	check("背包清空了", int(player.inventory.get("corn", 0)) == 0)

# --- 工具 ---

func _lines() -> Array:
	return DialogueData.get_dialogue("zhang_xiaofang").get("lines", [])

func _familiar_lines() -> Array:
	for line in _lines():
		if String(line.get("id", "")) == "familiar":
			return [line]
	return []

func _action_lines() -> Array:
	return [
		{
			"id": "act",
			"text": "随便说两句",
			"options": [
				{"text": "聊得挺好", "action": "add_affection", "data": {"amount": 5}},
				{"text": "记个事", "action": "set_flag", "data": {"flag": "talked_sow", "value": true}},
			],
		},
	]

func _find_option(runner: DialogueRunner, text: String) -> int:
	var options := runner.current_options()
	for i in options.size():
		if String(options[i].get("text", "")) == text:
			return i
	return -1
