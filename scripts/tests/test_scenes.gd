extends SceneTree
## headless 场景集成自测:游戏外壳常驻 HUD,切换地点只换世界容器。
##
## 运行: godot --headless --script res://scripts/tests/test_scenes.gd
##
## 这组测试守住一条架构底线:**换地点不能把 HUD 一起销毁**。
## 农时提示、日期、金币、体力必须全程可见 —— 玩家任何时候都得知道"现在该干嘛"。

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== 《宾州小镇》场景集成自测 (headless scene test) ===")
	await _test_shell_hud_persists()
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

func _test_shell_hud_persists() -> void:
	print("\n[1] 游戏外壳:换地点只换世界,HUD 常驻")
	var packed: PackedScene = load("res://scenes/game.tscn")
	if packed == null:
		check("game.tscn 可加载", false)
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	await create_timer(0.3).timeout

	var world: Node2D = game.get_node_or_null("World")
	check("外壳有 World 容器", world != null)
	if world == null:
		game.queue_free()
		return

	check("初始装载自家院", _world_name(world) == "FarmScene", "→ %s" % _world_name(world))
	var hud: Label = game.get_node_or_null("HUD/HBox/HudLabel")
	var almanac: Label = game.get_node_or_null("HUD/HBox/AlmanacLabel")
	var tip: Label = game.get_node_or_null("TipLabel")
	check("状态栏在", hud != null)
	check("农时倒计时标签在", almanac != null)
	check("农时提示行在", tip != null)
	if hud != null:
		check("状态栏含日期与金币", hud.text.contains("第1年") and hud.text.contains("金币"),
			"→ %s" % hud.text)
	if almanac != null:
		check("倒计时标签含秋霜", almanac.text.contains("秋霜"), "→ %s" % almanac.text)
	if tip != null:
		check("提示行含冬歇提示", tip.text.contains("冬歇"), "→ %s" % tip.text)

	# 走到镇大街
	world.get_child(0)._go_to_town()
	await create_timer(0.3).timeout
	check("已切到镇大街", _world_name(world) == "TownStreet", "→ %s" % _world_name(world))
	check("切换后状态栏仍在", game.get_node_or_null("HUD/HBox/HudLabel") != null)
	if hud != null:
		check("切换后状态栏仍有日期", hud.text.contains("第1年"), "→ %s" % hud.text)
	if almanac != null:
		check("切换后农时倒计时仍在", almanac.text.contains("秋霜"), "→ %s" % almanac.text)
	var key_hint: Label = game.get_node_or_null("KeyHint")
	if key_hint != null:
		check("按键提示随地点变化", key_hint.text.contains("回自家院"), "→ %s" % key_hint.text)

	# 走回自家院
	world.get_child(0)._go_to_farm()
	await create_timer(0.3).timeout
	check("已切回自家院", _world_name(world) == "FarmScene", "→ %s" % _world_name(world))
	check("切回后状态栏仍在", game.get_node_or_null("HUD/HBox/HudLabel") != null)
	if tip != null:
		check("切回后农时提示仍在", tip.text.contains("冬歇"), "→ %s" % tip.text)

	game.queue_free()
	await create_timer(0.1).timeout

func _world_name(world: Node) -> String:
	if world == null or world.get_child_count() == 0:
		return "空"
	return String(world.get_child(0).name)
