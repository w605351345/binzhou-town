extends SceneTree
## 游戏性打磨回归：移动、时间、碰撞辨识、音频、语音、HUD 与亮度。

const MUSIC_DIR := "res://assets/audio/music/"

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_run()

func check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  ✅ %s %s" % [label, detail])
	else:
		_failed += 1
		print("  ❌ %s %s" % [label, detail])

func _run() -> void:
	print("=== 《麦溪镇》游戏性打磨回归 (gameplay polish test) ===")
	_test_movement()
	_test_clock()
	_test_collision_and_identity()
	_test_assets_and_defaults()
	await _test_music()
	await _test_game_shell()

	print("--------------------------------------------------")
	print("结果: %d 通过 / %d 失败" % [_passed, _failed])
	if _failed > 0:
		quit(1)
	else:
		quit(0)

func _test_movement() -> void:
	print("\n[1] 八方向移动与行进稳定性")
	var controller := PlayerController.new()
	controller.set_input(Vector2.ONE)
	var diagonal := controller.velocity()
	check("斜向移动同时推进两个轴", diagonal.x > 0.0 and diagonal.y > 0.0,
		"→ %s" % diagonal)
	check("斜向移动做了归一化", is_equal_approx(diagonal.length(), PlayerController.WALK_SPEED),
		"→ %.2f / %.2f" % [diagonal.length(), PlayerController.WALK_SPEED])
	controller.set_input(Vector2(4.0, 0.0))
	check("超长输入仍不超过行走速度",
		controller.velocity().length() <= PlayerController.WALK_SPEED + 0.01,
		"→ %.2f" % controller.velocity().length())
	var player_script = load("res://scripts/player/player.gd")
	check("加速与减速参数都已启用",
		player_script.ACCELERATION > 0.0 and player_script.DECELERATION > 0.0,
		"→ %.0f / %.0f" % [player_script.ACCELERATION, player_script.DECELERATION])

	var renderer := MapRenderer.new()
	renderer.setup(MapDatabase.get_map("L03"), "spring")
	var marker := renderer.get_node_or_null("FocusMarker")
	check("焦点动画拆成独立节点", marker is FocusMarker,
		"→ %s" % (marker.get_class() if marker != null else "缺失"))
	if marker is FocusMarker:
		var focus := marker as FocusMarker
		focus.set_target(Vector2(120, 120), "interact")
		check("焦点标记可独立更新", focus.is_processing())
	renderer.free()

func _test_clock() -> void:
	print("\n[2] 游戏时间流速")
	check("每分钟现实秒数为 0.9",
		is_equal_approx(GameClock.REAL_SECONDS_PER_GAME_MINUTE, 0.9),
		"→ %.2f" % GameClock.REAL_SECONDS_PER_GAME_MINUTE)
	var real_seconds := float(GameClock.MINUTES_PER_DAY) \
		* GameClock.REAL_SECONDS_PER_GAME_MINUTE
	check("完整游戏日约 18 分钟", absf(real_seconds - 18.0 * 60.0) < 0.1,
		"→ %.0f 秒" % real_seconds)
	var clock := GameClock.new()
	check("半分钟现实时间只推进 33 个游戏分钟",
		clock.tick(30.0) == 33 and clock.minute_of_day == GameClock.DAY_START_MINUTE + 33,
		"→ %s" % clock.time_string())

func _test_collision_and_identity() -> void:
	print("\n[3] 建筑碰撞与场景辨识")
	var house := {"type": "house", "rect": [100, 100, 400, 300], "label": "老邮局"}
	var full := MapDatabase.rect_from_array(house["rect"])
	var solid := MapDatabase.prop_solid_rect(house)
	check("建筑只挡底部落地部分", solid.size.y < full.size.y,
		"→ %.1f / %.1f" % [solid.size.y, full.size.y])
	check("碰撞底边与建筑底边对齐", is_equal_approx(solid.end.y, full.end.y),
		"→ %.1f / %.1f" % [solid.end.y, full.end.y])
	check("建筑碰撞宽度留有视觉边距", solid.size.x < full.size.x,
		"→ %.1f / %.1f" % [solid.size.x, full.size.x])
	var tree := {"type": "tree", "rect": [0, 0, 220, 300], "label": "老树"}
	var trunk := MapDatabase.prop_solid_rect(tree)
	check("树木只挡树干", trunk.size.x < 220.0 * 0.35 and trunk.size.y < 300.0 * 0.3,
		"→ %s" % trunk)
	check("非实体装饰不产生碰撞",
		MapDatabase.prop_solid_rect({"type": "lantern", "rect": [0, 0, 40, 60]}).size == Vector2.ZERO)

	var renderer := MapRenderer.new()
	var post_badge := renderer._building_badge_text("老邮局")
	var clinic_badge := renderer._building_badge_text("卫生所")
	var restaurant_badge := renderer._building_badge_text("玉梅饭馆")
	check("邮局/卫生所/饭馆有不同功能徽章",
		post_badge != clinic_badge and clinic_badge != restaurant_badge
		and post_badge != restaurant_badge,
		"→ %s / %s / %s" % [post_badge, clinic_badge, restaurant_badge])
	check("不同功能建筑使用不同主色",
		renderer._building_accent_color("老邮局")
		!= renderer._building_accent_color("玉梅饭馆"))
	renderer.free()

	check("NPC 名牌识别范围足够大", NpcNode.NAMEPLATE_RANGE >= 350.0,
		"→ %.0f" % NpcNode.NAMEPLATE_RANGE)
	check("NPC 场景显示尺寸已放大", NpcNode.BODY_SCALE > 1.0,
		"→ %.2f" % NpcNode.BODY_SCALE)

func _test_assets_and_defaults() -> void:
	print("\n[4] 音频、语音与头像资源")
	var state := GameState.new()
	check("新存档默认关闭 NPC 语音", not state.voice_enabled)
	var dialogue_script = load("res://scripts/ui/dialogue_box.gd")
	check("对话脚本也默认静音", not dialogue_script.VOICE_ENABLED)

	var npcs := _npc_data()
	var missing_portraits: Array[String] = []
	var wrong_sizes: Array[String] = []
	for raw in npcs:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var path := String(raw.get("portrait_path", ""))
		if path == "" or not ResourceLoader.exists(path):
			missing_portraits.append(String(raw.get("id", "?")))
			continue
		var texture: Texture2D = load(path)
		if texture == null or texture.get_size() != Vector2(256, 256):
			wrong_sizes.append(String(raw.get("name", raw.get("id", "?"))))
	check("11 位 NPC 都有对话头像", npcs.size() == 11 and missing_portraits.is_empty(),
		"→ %d 位 / 缺失 %s" % [npcs.size(), missing_portraits])
	check("对话头像统一 256×256", wrong_sizes.is_empty(), "→ %s" % [wrong_sizes])

func _test_music() -> void:
	print("\n[5] 场景背景音乐")
	var missing: Array[String] = []
	for map in MapDatabase.all_maps():
		var ambience := String(map.get("ambience", ""))
		var path := MUSIC_DIR + ambience + ".wav"
		if ambience == "" or not ResourceLoader.exists(path):
			missing.append("%s:%s" % [map.get("id", "?"), ambience])
	check("每张地图都有对应配乐", missing.is_empty(), "→ 缺失 %s" % [missing])

	var director := MusicDirector.new()
	root.add_child(director)
	await process_frame
	director.play_ambience("river")
	check("河湾可切换到河岸配乐", director.current_track() == "river",
		"→ %s" % director.current_track())
	director.play_ambience("theater")
	check("剧场可切换到戏剧配乐", director.current_track() == "theater",
		"→ %s" % director.current_track())
	director.stop_music()
	director.queue_free()
	await process_frame

func _test_game_shell() -> void:
	print("\n[6] 无黑边提示与画面亮度")
	var packed: PackedScene = load("res://scenes/game.tscn")
	if packed == null:
		check("游戏场景可加载", false)
		return
	var game := packed.instantiate()
	root.add_child(game)
	await create_timer(0.4).timeout

	var manager: Node = root.get_node("GameStateManager")
	manager.state.clock.minute_of_day = 12 * 60
	manager.state.weather.today = "sunny"
	game._refresh_environment()
	await process_frame

	var guide_backdrop := game.get_node_or_null("HUD/GuideBackdrop") as ColorRect
	var bottom_backdrop := game.get_node_or_null("HUD/BottomBackdrop") as ColorRect
	check("引导提示不再带黑色底板",
		guide_backdrop != null and not guide_backdrop.visible)
	check("底部提示不再带黑色底板",
		bottom_backdrop != null and not bottom_backdrop.visible)
	check("正午环境色整体提亮", game._environment_tint.color.r > 1.0,
		"→ %s" % game._environment_tint.color)

	var pause_menu = game.get_node("PauseMenu")
	check("暂停菜单不再显示语音入口",
		pause_menu.voice_button != null and not pause_menu.voice_button.visible)
	check("开场按农场场景播放配乐",
		game._music != null and game._music.current_track() == "farm",
		"→ %s" % (game._music.current_track() if game._music != null else "缺失"))

	game.queue_free()
	await create_timer(0.1).timeout

func _npc_data() -> Array:
	var file := FileAccess.open("res://data/npcs.json", FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	return parsed.get("npcs", [])
