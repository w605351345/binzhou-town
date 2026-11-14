extends SceneTree
## 美术资源验收：NPC 独特性、立绘、四季地形、道具贴图与季节场景板。
## 运行: godot --headless --script res://scripts/tests/test_art.gd

var _passed := 0
var _failed := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== 《宾州小镇》美术资源自测 (art test) ===")
	_test_npc_sprites()
	_test_npc_winter_sprites()
	_test_portraits()
	_test_terrain_and_props()
	_test_season_boards()
	_test_renderer_wiring()
	_test_ground_details()
	_test_visual_geometry()
	_test_capture_options()
	_test_weather_overlay()
	_test_dialogue_portrait_wiring()
	await _test_main_menu_board()
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

func _npc_data() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/npcs.json"))
	return Array(parsed.get("npcs", [])) if typeof(parsed) == TYPE_DICTIONARY else []

func _image_size(path: String) -> Vector2i:
	if not FileAccess.file_exists(path):
		return Vector2i.ZERO
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	return img.get_size() if img != null else Vector2i.ZERO

func _bytes_hash(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	return hash(FileAccess.get_file_as_bytes(path))

func _test_npc_sprites() -> void:
	print("\n[1] 六名 NPC 独立精灵")
	var npcs := _npc_data()
	check("NPC 数据为 6 人", npcs.size() == 6, "→ %d" % npcs.size())
	var seen := {}
	for npc in npcs:
		var path := String(npc.get("sprite_path", ""))
		var npc_name := String(npc.get("name", npc.get("id", "")))
		check("%s 精灵存在" % npc_name, FileAccess.file_exists(path), "→ " + path)
		check("%s 精灵尺寸 384×216" % npc_name,
			_image_size(path) == Vector2i(384, 216), "→ %s" % _image_size(path))
		var key := _bytes_hash(path)
		check("%s 精灵不是共用复制品" % npc_name, not seen.has(key),
			"→ hash %d" % key)
		seen[key] = true

func _test_npc_winter_sprites() -> void:
	print("\n[1b] 六名 NPC 冬装差分")
	var seen := {}
	for npc in _npc_data():
		var path := String(npc.get("winter_sprite_path", ""))
		var npc_name := String(npc.get("name", npc.get("id", "")))
		check("%s 冬装精灵路径存在" % npc_name, path != "", "→ " + path)
		check("%s 冬装精灵存在" % npc_name, FileAccess.file_exists(path), "→ " + path)
		check("%s 冬装精灵尺寸 384×216" % npc_name,
			_image_size(path) == Vector2i(384, 216), "→ %s" % _image_size(path))
		var key := _bytes_hash(path)
		check("%s 冬装不是春秋装复制品" % npc_name,
			key != 0 and key != _bytes_hash(String(npc.get("sprite_path", ""))),
			"→ hash %d" % key)
		check("%s 冬装与其他 NPC 不同" % npc_name, not seen.has(key), "→ hash %d" % key)
		seen[key] = true
	var sample := NpcBase.from_data(_npc_data()[0])
	check("NpcBase 冬季选择冬装差分",
		sample.sprite_path_for("winter") == sample.winter_sprite_path)
	check("NpcBase 春季回退常服",
		sample.sprite_path_for("spring") == sample.sprite_path)

func _test_portraits() -> void:
	print("\n[2] 六名 NPC 立绘")
	for npc in _npc_data():
		var path := String(npc.get("portrait_path", ""))
		var npc_name := String(npc.get("name", npc.get("id", "")))
		check("%s 立绘存在" % npc_name, FileAccess.file_exists(path), "→ " + path)
		check("%s 立绘尺寸 256×256" % npc_name,
			_image_size(path) == Vector2i(256, 256), "→ %s" % _image_size(path))

func _test_terrain_and_props() -> void:
	print("\n[3] 四季地形与道具贴图")
	var terrains := ["grass", "grass_dark", "moss", "dirt", "soil", "road", "plaza",
		"sand", "water", "wall", "floor_wood", "floor_tile", "rug", "stage_floor"]
	for season in ["spring", "summer", "autumn", "winter"]:
		var missing: Array = []
		for terrain in terrains:
			var path := MapRenderer.terrain_texture_path(season, terrain)
			if not FileAccess.file_exists(path):
				missing.append(terrain)
		check("%s 季地形贴图齐全" % season, missing.is_empty(), "→ %s" % [missing])

	var props := ["house", "building", "barn", "tree", "birch", "well", "woodpile",
		"fence", "dock", "board", "stall", "lamp", "counter", "shelf", "bed", "stove",
		"table", "chest", "calendar", "bench", "stage", "backstage", "instrument",
		"lantern", "fallen_log", "mushroom_log", "shrine", "reeds", "boat", "crate",
		"workbench", "exam_bed", "medicine_cabinet", "mailboxes", "desk", "lumber",
		"saw", "half_built", "sign", "sofa", "barrel", "tool_rack", "plow", "cart",
		"gravestone", "haystack", "water_trough", "fish_rack", "clothesline",
		"mud_puddle", "ice_block"]
	var missing_props: Array = []
	for prop in props:
		if not FileAccess.file_exists(MapRenderer.prop_texture_path(prop)):
			missing_props.append(prop)
	check("地点地标与道具贴图齐全", missing_props.is_empty(), "→ %s" % [missing_props])

func _test_season_boards() -> void:
	print("\n[4] 四季场景板")
	for season in ["spring", "summer", "autumn", "winter"]:
		var path := "res://assets/art/concept/season_%s.png" % season
		check("%s 场景板存在" % season, FileAccess.file_exists(path), "→ " + path)
		check("%s 场景板为 960×540" % season,
			_image_size(path) == Vector2i(960, 540), "→ %s" % _image_size(path))

func _test_renderer_wiring() -> void:
	print("\n[5] 地图渲染器接入四季贴图")
	var renderer := MapRenderer.new()
	renderer.setup(MapDatabase.get_map("L01"), "winter")
	root.add_child(renderer)
	check("MapRenderer 接受季节参数", renderer.season == "winter", "→ %s" % renderer.season)
	check("冬季草地纹理已载入", renderer._terrain_texture("grass") != null)
	check("冬季道路纹理已载入", renderer._terrain_texture("road") != null)
	check("农舍道具纹理已载入", renderer._prop_texture("house") != null)
	check("老井道具纹理已载入", renderer._prop_texture("well") != null)
	renderer.set_season("autumn")
	check("换季后渲染器同步", renderer.season == "autumn", "→ %s" % renderer.season)
	check("换季后重新载入秋季纹理", renderer._terrain_texture("grass") != null)
	renderer.queue_free()

func _test_ground_details() -> void:
	print("\n[5b] 地图地面细节层")
	var farm := MapRenderer.new()
	farm.setup(MapDatabase.get_map("L01"), "spring")
	var spring_a: Array = farm.ground_detail_specs()
	var spring_b: Array = farm.ground_detail_specs()
	check("农场春天地面细节足够密", spring_a.size() >= 60,
		"→ %d 个" % spring_a.size())
	check("地面细节可复现", str(spring_a) == str(spring_b))
	farm.set_season("winter")
	var winter: Array = farm.ground_detail_specs()
	check("雪地有独立的雪堆与枯枝细节", not winter.is_empty(),
		"→ %d 个" % winter.size())
	check("季节切换会改变细节组成",
		_day_detail_kinds(spring_a) != _day_detail_kinds(winter),
		"→ %s / %s" % [_day_detail_kinds(spring_a), _day_detail_kinds(winter)])
	var home := MapRenderer.new()
	home.setup(MapDatabase.get_map("L02"), "spring")
	var indoor: Array = home.ground_detail_specs()
	check("室内只保留轻微生活痕迹", not indoor.is_empty() and indoor.size() < spring_a.size(),
		"→ %d / %d" % [indoor.size(), spring_a.size()])
	farm.queue_free()
	home.queue_free()

func _day_detail_kinds(specs: Array) -> Array:
	var kinds := {}
	for spec in specs:
		kinds[String(spec.get("kind", ""))] = true
	var out := kinds.keys()
	out.sort()
	return out

func _test_visual_geometry() -> void:
	print("\n[5c] 道具等比与地形边缘")
	var bench := MapRenderer.aspect_fit_rect(Rect2(40, 80, 600, 220), Vector2(210, 120))
	var bench_aspect := bench.size.x / maxf(1.0, bench.size.y)
	check("长椅不会被横向压扁", absf(bench_aspect - 210.0 / 120.0) < 0.02,
		"→ %.2f" % bench_aspect)
	check("宽道具底部贴地", absf(bench.end.y - 300.0) < 0.01, "→ %.2f" % bench.end.y)
	check("宽道具水平居中", absf(bench.get_center().x - 340.0) < 0.01,
		"→ %.2f" % bench.get_center().x)
	var tree := MapRenderer.aspect_fit_rect(Rect2(0, 0, 120, 240), Vector2(150, 210))
	check("树保持窄高比例", absf(tree.size.x / maxf(1.0, tree.size.y) - 150.0 / 210.0) < 0.02,
		"→ %.2f" % (tree.size.x / maxf(1.0, tree.size.y)))
	check("室外草地不画硬边", MapRenderer.terrain_border_width("grass", false) == 0.0)
	check("室外道路不画硬边", MapRenderer.terrain_border_width("road", false) == 0.0)
	check("室内地板保留轻微收边", MapRenderer.terrain_border_width("floor_wood", true) > 0.0,
		"→ %.1f" % MapRenderer.terrain_border_width("floor_wood", true))
	check("冬季农舍屋顶有积雪", MapRenderer.needs_winter_roof_cap("house", "winter"))
	check("夏季农舍屋顶无积雪", not MapRenderer.needs_winter_roof_cap("house", "summer"))
	check("冬季树木不加屋顶积雪", not MapRenderer.needs_winter_roof_cap("tree", "winter"))
	check("冬季地块盖雪", FarmPlotView.season_overlay_for("winter").a >= 0.7,
		"→ %.2f" % FarmPlotView.season_overlay_for("winter").a)
	check("春季地块只做湿润压色", FarmPlotView.season_overlay_for("spring").a < 0.2,
		"→ %.2f" % FarmPlotView.season_overlay_for("spring").a)
	check("栅栏采用分段绘制", MapRenderer.should_tile_prop("fence"))
	check("长椅不重复铺成多张", not MapRenderer.should_tile_prop("bench"))

func _test_capture_options() -> void:
	print("\n[5d] 四季截图参数")
	var mgr := root.get_node("GameStateManager")
	check("截图参数入口存在", mgr.has_method("apply_capture_options"))
	if not mgr.has_method("apply_capture_options"):
		return
	var state := GameState.new()
	var applied: Dictionary = mgr.apply_capture_options(state, [
		"--season=summer", "--time=12:00", "--weather=sunny",
	])
	check("截图参数被识别", bool(applied.get("applied", false)))
	check("截图能锁定夏季", state.calendar.get_season() == "summer",
		"→ %s" % state.calendar.get_season())
	check("截图能锁定正午", state.clock.minute_of_day == 12 * 60,
		"→ %s" % state.clock.time_string())
	check("截图能锁定晴天", state.weather.today == "sunny",
		"→ %s" % state.weather.today)
	var winter := GameState.new()
	mgr.apply_capture_options(winter, ["--season=winter", "--time=15:30"])
	check("冬季截图落在白天", winter.calendar.get_season() == "winter"
		and winter.clock.minute_of_day == 15 * 60 + 30,
		"→ %s %s" % [winter.calendar.get_season(), winter.clock.time_string()])
	var location_state := GameState.new()
	mgr.apply_capture_options(location_state,
		["--location=L01", "--spawn=1510,900", "--season=autumn"])
	check("截图能锁定地点", String(location_state.world.get("location_id", "")) == "L01",
		"→ %s" % location_state.world.get("location_id", ""))
	check("截图能锁定出生点", Vector2(location_state.world.get("player_x", 0.0),
		location_state.world.get("player_y", 0.0)) == Vector2(1510, 900),
		"→ %s,%s" % [location_state.world.get("player_x"), location_state.world.get("player_y")])

func _test_weather_overlay() -> void:
	print("\n[5e] 四季天气粒子")
	var script: Script = load("res://scripts/ui/weather_overlay.gd")
	check("天气粒子脚本存在", script != null)
	if script == null:
		return
	var spring = script.new()
	var summer = script.new()
	var autumn = script.new()
	var winter = script.new()
	var rain = script.new()
	var blizzard = script.new()
	check("春季晴天飘花瓣", spring.particle_kind_for("spring", "sunny") == "petal")
	check("夏季晴天有花粉", summer.particle_kind_for("summer", "sunny") == "pollen")
	check("秋季晴天落叶", autumn.particle_kind_for("autumn", "sunny") == "leaf")
	check("冬季晴天落雪", winter.particle_kind_for("winter", "sunny") == "snow")
	check("雨天画雨线", rain.particle_kind_for("spring", "rain") == "rain")
	check("室内不会下雪", winter.particle_kind_for("winter", "snow", true) == "dust")
	check("室内不会下雨", rain.particle_kind_for("spring", "rain", true) == "dust")
	check("室内粒子更克制",
		winter.particle_count_for("winter", "blizzard", true)
		< winter.particle_count_for("winter", "blizzard"),
		"→ %d / %d" % [winter.particle_count_for("winter", "blizzard", true),
			winter.particle_count_for("winter", "blizzard")])
	check("暴风雪比普通雪更密",
		blizzard.particle_count_for("winter", "blizzard")
		> winter.particle_count_for("winter", "snow"),
		"→ %d / %d" % [blizzard.particle_count_for("winter", "blizzard"),
			winter.particle_count_for("winter", "snow")])
	for node in [spring, summer, autumn, winter, rain, blizzard]:
		node.free()

func _test_dialogue_portrait_wiring() -> void:
	print("\n[6] 对话框接入 NPC 立绘")
	var npcs := _npc_data()
	if npcs.is_empty():
		check("有 NPC 数据可测试", false)
		return
	var npc := NpcBase.from_data(npcs[0])
	var runner := DialogueRunner.new()
	runner.setup([{"id": "art_portrait", "text": "立绘接线测试。"}],
		PlayerProfile.new(), GameCalendar.new(), npc)
	runner.start()
	# --script 模式下 autoload 尚不是全局标识符，按脚本路径加载可避开编译顺序问题。
	var box = load("res://scripts/ui/dialogue_box.gd").new()
	root.add_child(box)
	box.setup(npc, runner)
	check("立绘框可见", box.portrait_visible())
	check("立绘纹理不是空", box.portrait_texture() != null)
	if box.portrait_texture() != null:
		check("立绘纹理尺寸 256×256",
			box.portrait_texture().get_size() == Vector2(256, 256),
			"→ %s" % box.portrait_texture().get_size())
	box.queue_free()

func _test_main_menu_board() -> void:
	print("\n[7] 主菜单接入四季场景板")
	var packed: PackedScene = load("res://scenes/main_menu.tscn")
	if packed == null:
		check("主菜单场景可加载", false)
		return
	var menu := packed.instantiate()
	root.add_child(menu)
	await process_frame
	menu._show_season_board()
	var background := menu.get_node_or_null("Background") as TextureRect
	check("主菜单有背景图层", background != null)
	var winter_path := "res://assets/art/concept/season_winter.png"
	check("场景板资源可被 Godot 加载", ResourceLoader.exists(winter_path)
		and load(winter_path) is Texture2D, "→ exists=%s" % ResourceLoader.exists(winter_path))
	check("主菜单脚本持有背景图层", menu.background != null)
	check("主菜单加载了场景板纹理", background != null and background.texture != null,
		"→ %s" % [background.texture if background != null else null])
	check("主菜单默认展示冬景", String(menu.current_season()) == "winter",
		"→ %s" % menu.current_season())
	menu.queue_free()
