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
	print("=== 《麦溪镇》场景集成自测 (headless scene test) ===")
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

	check("初始从自家农场开始", _world_name(world) == "Farm",
		"→ %s" % _world_name(world))
	var hud: Label = game.get_node_or_null("HUD/HBox/HudLabel")
	var almanac: Label = game.get_node_or_null("HUD/HBox/AlmanacLabel")
	var tip: Label = game.get_node_or_null("HUD/BottomBox/TipLabel")
	var key_hint: Label = game.get_node_or_null("HUD/BottomBox/KeyHint")
	var guide: Label = game.get_node_or_null("HUD/GuidePanel/GuideLabel")
	check("状态栏在", hud != null)
	check("农时倒计时标签在", almanac != null)
	check("农时提示行在", tip != null)
	check("今日指引在", guide != null)
	if hud != null:
		check("状态栏含日期", hud.text.contains("第1年") and hud.text.contains("春季"),
			"→ %s" % hud.text)
		var mgr: Node = root.get_node("GameStateManager")
		var weather_cn := WeatherSystem.weather_cn(mgr.state.weather.today)
		check("状态栏含时钟", hud.text.contains(":"), "→ %s" % hud.text)
		check("状态栏含天气", hud.text.contains(weather_cn), "→ %s" % hud.text)
	if almanac != null:
		check("倒计时标签含初霜", almanac.text.contains("初霜"), "→ %s" % almanac.text)
	if tip != null:
		check("提示行含春播提示", tip.text.contains("可播种"), "→ %s" % tip.text)
		check("提示行不随世界相机移动", tip.get_parent().get_parent() == game.get_node("HUD"))
		check("提示行默认隐藏", not tip.visible)
	if guide != null:
		check("今日指引指向翻地", guide.text.contains("翻土"), "→ %s" % guide.text)

	var pause_menu := game.get_node_or_null("PauseMenu")
	check("暂停菜单节点在", pause_menu != null)
	if pause_menu != null:
		pause_menu.open()
		await process_frame
		check("暂停菜单打开后存档按钮有焦点",
			game.get_viewport().gui_get_focus_owner() == pause_menu.save_button)
		pause_menu.save_button.pressed.emit()
		await process_frame
		check("本次暂停内存档后立即可以读档",
			not pause_menu.load_button.disabled and pause_menu.status_label.text == "已存档",
			"→ %s / %s" % [not pause_menu.load_button.disabled, pause_menu.status_label.text])
		pause_menu.close()

	# 走到镇大街
	world.get_child(0)._go_to_town()
	await create_timer(0.3).timeout
	check("已切到镇中心", _world_name(world) == "Town", "→ %s" % _world_name(world))
	check("切换后状态栏仍在", game.get_node_or_null("HUD/HBox/HudLabel") != null)
	var town := world.get_child(0)
	var viewport_rect: Rect2 = game.get_viewport_rect()
	for label_path in ["HUD/BottomBox/ContextLabel", "HUD/BottomBox/MessageLabel"]:
		var shell_label := game.get_node_or_null(label_path) as Control
		check("统一 HUD %s 在视口内" % label_path,
			shell_label != null and viewport_rect.encloses(shell_label.get_global_rect()),
			"→ %s / %s" % [shell_label.get_global_rect() if shell_label != null else "缺失",
				viewport_rect])
	if hud != null:
		check("切换后状态栏仍有日期", hud.text.contains("第1年"), "→ %s" % hud.text)
	if almanac != null:
		check("切换后农时倒计时仍在", almanac.text.contains("初霜"), "→ %s" % almanac.text)
	if key_hint != null:
		check("常驻按键条不再显示", key_hint == null or not key_hint.visible,
			"→ %s" % (key_hint.text if key_hint != null else "缺失"))

	# 走回自家院
	world.get_child(0)._go_to_farm()
	await create_timer(0.3).timeout
	check("已切回自家院", _world_name(world) == "Farm", "→ %s" % _world_name(world))
	check("切回后状态栏仍在", game.get_node_or_null("HUD/HBox/HudLabel") != null)
	if tip != null:
		check("切回后农时提示仍在", tip.text.contains("可播种"), "→ %s" % tip.text)

	game.queue_free()
	await create_timer(0.1).timeout

func _world_name(world: Node) -> String:
	if world == null or world.get_child_count() == 0:
		return "空"
	return String(world.get_child(0).name)
