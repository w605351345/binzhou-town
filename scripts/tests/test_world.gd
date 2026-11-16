extends SceneTree
## 世界地图自测:14 张地图、双向门、出生点、互动点、相机边界。
## 运行: godot --headless --script res://scripts/tests/test_world.gd

var _passed := 0
var _failed := 0

const EXPECTED := {
	"L01": {"name": "柳溪农场", "size": Vector2i(3200, 2240)},
	"L02": {"name": "农舍", "size": Vector2i(1280, 896)},
	"L03": {"name": "麦溪镇中心", "size": Vector2i(3840, 1920)},
	"L04": {"name": "杂货店", "size": Vector2i(1280, 896)},
	"L05": {"name": "老邮局", "size": Vector2i(1280, 896)},
	"L06": {"name": "玉梅旅店", "size": Vector2i(1536, 1024)},
	"L07": {"name": "麦溪诊所", "size": Vector2i(1280, 896)},
	"L08": {"name": "赵氏木工坊", "size": Vector2i(1280, 896)},
	"L09": {"name": "河湾", "size": Vector2i(2560, 1280)},
	"L10": {"name": "柳溪林", "size": Vector2i(2560, 1600)},
	"L11": {"name": "月桂剧场", "size": Vector2i(1920, 1280)},
	"L12": {"name": "北岭矿洞", "size": Vector2i(1600, 1152)},
	"L13": {"name": "牧云牧场", "size": Vector2i(2560, 1600)},
	"L14": {"name": "麦溪镇史馆", "size": Vector2i(1280, 896)},
}

func _initialize() -> void:
	await process_frame
	_run()

func _run() -> void:
	print("=== 世界地图与通用地点场景自测 ===")
	test_database()
	test_links()
	await test_scene_wrappers()
	await test_spatial_door()
	await test_sleep_requires_bed()
	await test_spatial_travel()
	print("--------------------------------------------------")
	print("结果: %d 通过 / %d 失败" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  ✅ %s %s" % [label, detail])
	else:
		_failed += 1
		print("  ❌ %s %s" % [label, detail])

func test_database() -> void:
	print("\n[1] 地图数据库")
	var ids := MapDatabase.all_ids()
	check("恰好 14 张地图", ids.size() == 14, "→ %d 张" % ids.size())
	for id in EXPECTED.keys():
		var map := MapDatabase.get_map(id)
		var expected: Dictionary = EXPECTED[id]
		check("%s 存在" % id, not map.is_empty())
		if map.is_empty():
			continue
		check("%s 名称正确" % id, String(map.get("name", "")) == String(expected["name"]),
			"→ %s" % map.get("name", ""))
		var size := MapDatabase.map_size(map)
		check("%s 尺寸正确" % id,
			size == Vector2i(expected["size"].x, expected["size"].y), "→ %s" % size)
		var spawn := MapDatabase.spawn_point(map)
		check("%s 出生点在界内" % id, Rect2(Vector2.ZERO, Vector2(size)).has_point(spawn),
			"→ %s" % spawn)
		check("%s 至少一个互动点" % id,
			Array(map.get("interactables", [])).size() >= 1)
		check("%s 场景文件存在" % id,
			FileAccess.file_exists(SceneRouter.scene_path(id)),
			"→ %s" % SceneRouter.scene_path(id))
	var farm := MapDatabase.get_map("L01")
	check("L01 有可扩建农田区域", farm.has("farm_area"))
	check("L02 是室内", bool(MapDatabase.get_map("L02").get("indoor", false)))
	check("L09 是户外河岸", not bool(MapDatabase.get_map("L09").get("indoor", true)))

func test_links() -> void:
	print("\n[2] 门双向可达")
	var errors := MapDatabase.validate_links()
	check("门与出生点全部合法", errors.is_empty(), "→ %s" % str(errors))
	for id in MapDatabase.all_ids():
		var map := MapDatabase.get_map(id)
		var start := MapDatabase.spawn_point(map)
		var unreachable: Array = []
		for door in map.get("doors", []):
			if not MapDatabase.is_reachable(map, start,
					MapDatabase.door_rect(door).get_center()):
				unreachable.append(String(door.get("id", "?")))
		check("%s 每扇门都能从出生点走到" % id, unreachable.is_empty(),
			"→ %s" % str(unreachable))
	var door_count := 0
	for id in MapDatabase.all_ids():
		door_count += Array(MapDatabase.get_map(id).get("doors", [])).size()
	check("每张图都有出口", _all_have_doors(), "→ %d 道门" % door_count)
	check("设计图 L01↔L02 双向",
		_has_link("L01", "L02") and _has_link("L02", "L01"))
	check("设计图 L03↔L05 双向",
		_has_link("L03", "L05") and _has_link("L05", "L03"))
	check("设计图 L09↔L10 双向",
		_has_link("L09", "L10") and _has_link("L10", "L09"))

func _all_have_doors() -> bool:
	for id in MapDatabase.all_ids():
		if Array(MapDatabase.get_map(id).get("doors", [])).is_empty():
			return false
	return true

func _has_link(from_id: String, to_id: String) -> bool:
	for door in MapDatabase.get_map(from_id).get("doors", []):
		if String(door.get("target", "")) == to_id:
			return true
	return false

func test_scene_wrappers() -> void:
	print("\n[3] 14 个地点场景可加载")
	for id in MapDatabase.all_ids():
		var path := SceneRouter.scene_path(id)
		var packed: PackedScene = load(path)
		check("%s 场景可实例化" % id, packed != null)
		if packed == null:
			continue
		var node: Node = packed.instantiate()
		check("%s 带地点 id" % id, String(node.get("location_id")) == id)
		root.add_child(node)
		await create_timer(0.12).timeout
		check("%s 有地图渲染器" % id, node.get_node_or_null("MapRenderer") != null)
		check("%s 有玩家" % id, node.get_node_or_null("Player") != null)
		if id == "L01":
			var plots: Node = node.get_node_or_null("PlotContainer")
			check("L01 默认农场按 3 列排布", plots != null and plots.get_child_count() == 9,
				"→ %s 块" % (plots.get_child_count() if plots != null else 0))
			if plots != null and plots.get_child_count() >= 4:
				check("L01 地块横纵间距正确",
					plots.get_child(1).position.x - plots.get_child(0).position.x == 88.0
					and plots.get_child(3).position.x == plots.get_child(0).position.x,
					"→ %s / %s" % [plots.get_child(1).position, plots.get_child(3).position])
		var camera: Camera2D = node.get_node_or_null("Player/Camera2D")
		check("%s 相机存在" % id, camera != null)
		if camera != null:
			var size := MapDatabase.map_size(MapDatabase.get_map(id))
			check("%s 相机边界钳制" % id,
				camera.limit_left == 0 and camera.limit_top == 0
				and camera.limit_right == size.x and camera.limit_bottom == size.y,
				"→ %d,%d,%d,%d" % [camera.limit_left, camera.limit_top,
					camera.limit_right, camera.limit_bottom])
		node.queue_free()
		await create_timer(0.05).timeout

func test_spatial_door() -> void:
	print("\n[4] 空间门触发")
	var packed: PackedScene = load(SceneRouter.scene_path("L01"))
	var farm: Node = packed.instantiate()
	root.add_child(farm)
	await create_timer(0.15).timeout
	var door: Dictionary = farm.door_at(Vector2(1890, 1774))
	check("农场南门可识别", String(door.get("target", "")) == "L03",
		"→ %s" % door.get("target", "无"))
	var indoors: Dictionary = farm.door_at(Vector2(1400, 800))
	check("农舍门可识别", String(indoors.get("target", "")) == "L02",
		"→ %s" % indoors.get("target", "无"))
	check("空地不误触发", farm.door_at(Vector2(50, 50)).is_empty())
	farm.queue_free()
	await create_timer(0.05).timeout

func test_sleep_requires_bed() -> void:
	print("\n[5] 只能回农舍木床睡觉")
	var mgr: Node = root.get_node("GameStateManager")
	var saved_state: Variant = mgr.state
	mgr.state = GameState.new()
	var home: Node = load(SceneRouter.scene_path("L02")).instantiate()
	root.add_child(home)
	await create_timer(0.15).timeout
	var day_before: int = int(mgr.state.calendar.abs_day())
	home.player.position = Vector2(640, 720)
	check("离木床远时不能跳天", not home._try_sleep())
	check("拒绝后日期不变", mgr.state.calendar.abs_day() == day_before)
	check("提示走近木床", home.message_label.text.contains("木床"),
		"→ %s" % home.message_label.text)
	home.player.position = Vector2(280, 400)
	check("靠近木床可以睡到次日", home._try_sleep()
		and mgr.state.calendar.abs_day() == day_before + 1)
	home.queue_free()
	mgr.state = saved_state
	await create_timer(0.05).timeout

func test_spatial_travel() -> void:
	print("\n[6] 走进门自动换图")
	var packed: PackedScene = load("res://scenes/game.tscn")
	var game: Node = packed.instantiate()
	root.add_child(game)
	await create_timer(0.3).timeout
	var world: Node = game.get_node("World")
	var farm: Node = world.get_child(0)
	var player: Node2D = farm.get_node("Player")
	player.position = Vector2(1890, 1774)
	await create_timer(1.0).timeout
	check("从农场南门进入镇中心", String(world.get_child(0).name) == "Town",
		"→ %s" % world.get_child(0).name)
	check("存档位置更新为 L03",
		String(root.get_node("GameStateManager").state.world.get("location_id", "")) == "L03")
	var town: Node = world.get_child(0)
	var town_player: Node2D = town.get_node("Player")
	check("落点在镇中心北侧", town_player.position.distance_to(Vector2(1920, 220)) < 4.0,
		"→ %s" % town_player.position)
	town_player.position = Vector2(1900, 50)
	await create_timer(1.0).timeout
	check("从镇中心北门回农场", String(world.get_child(0).name) == "Farm",
		"→ %s" % world.get_child(0).name)
	game.queue_free()
	await create_timer(0.1).timeout
