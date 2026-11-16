extends SceneTree
## 存档 v3 自测:新字段往返、v1 迁移、农场扩建、原子写入。
## 运行: godot --headless --script res://scripts/tests/test_save_v2.gd

var _passed := 0
var _failed := 0

func _init() -> void:
	print("=== 存档 v3 与农场扩建自测 ===")
	test_v2_roundtrip()
	test_v1_migration()
	test_legacy_winter_start_migration()
	test_farm_expand()
	test_atomic_write()
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

func test_v2_roundtrip() -> void:
	print("\n[1] v3 全字段往返")
	var state := GameState.new()
	state.clock.advance_minutes(150)
	state.weather.today = "rain"
	state.weather.tomorrow = "cloudy"
	state.weather.seed = 123456
	state.world = {"location_id": "L03", "player_x": 640, "player_y": 480}
	state.quests = {"active": ["q_mail"], "completed": ["q_intro"]}
	state.events = {"done": ["zhang_e1"], "flags": {"zhang_choice": "honest"}}
	state.forage = {"collected": {"birch_mushroom": 12}, "last_day": 12}
	state.relationships["zhang_xiaofang"] = {
		"affection": 42, "gifted_today": true, "events_done": ["zhang_e1"],
	}
	state.farm.ensure_size(20)
	state.farm.plots[16].till()
	state.farm.plots[16].plant("corn", "spring", 4)

	var data := state.to_dict()
	check("存档带 schema_version=3", int(data.get("schema_version", 0)) == 3,
		"→ %s" % data.get("schema_version", "缺"))
	check("时钟单独入档", data.has("clock"))
	check("天气入档", data.has("weather"))
	check("关系使用 v2 relationships 键",
		data.has("relationships") and not data.has("npc_relationships"))
	check("农场带宽高", data.get("farm", {}).has("width") and data.get("farm", {}).has("height"))

	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	check("JSON 可解析", typeof(parsed) == TYPE_DICTIONARY)
	var loaded := GameState.from_dict(parsed)
	check("时钟保留", loaded.clock.minute_of_day == 8 * 60 + 30,
		loaded.clock.time_string())
	check("天气保留", loaded.weather.today == "rain" and loaded.weather.tomorrow == "cloudy"
		and loaded.weather.seed == 123456)
	check("世界位置保留", loaded.world.get("location_id") == "L03"
		and int(loaded.world.get("player_x", 0)) == 640)
	check("任务保留", loaded.quests.get("active", []).has("q_mail")
		and loaded.quests.get("completed", []).has("q_intro"))
	check("事件与选择保留", loaded.events.get("done", []).has("zhang_e1")
		and loaded.events.get("flags", {}).get("zhang_choice") == "honest")
	check("采集状态保留", int(loaded.forage.get("last_day", -1)) == 12)
	check("关系留存 v2 结构", loaded.npc_affection("zhang_xiaofang") == 42
		and bool(loaded.relationships.get("zhang_xiaofang", {}).get("gifted_today", false)))
	check("扩建后的农场尺寸保留", loaded.farm.width == 5 and loaded.farm.height == 4
		and loaded.farm.plots.size() == 20)
	check("扩建后的地块作物保留", loaded.farm.get_plot(16).crop_id == "corn")

func test_v1_migration() -> void:
	print("\n[2] v1 旧档迁移")
	var v1 := {
		"player": {"given_name": "旧档主角", "gold": 321},
		"calendar": {"year": 2, "day_of_year": 100},
		"farm": {"plots": [{"index": 0, "state": FarmPlot.State.TILLED,
			"crop_id": "", "days_grown": 0.0, "days_watered": 0,
			"last_watered_day": -1, "autumn_plowed": true}]},
		"npc_relationships": {"zhang_shen": {"affection": 17}},
		"postcards_collected": ["p_dawn"],
		"postcards_pending": [{"recipient_id": "aunt_inland", "arrive_day": 45}],
		"voice_enabled": false,
		"flags": {"old_flag": true},
	}
	var loaded := GameState.from_dict(v1)
	check("v1 年/日迁成绝对日", loaded.calendar.abs_day() == GameCalendar.DAYS_PER_YEAR + 100,
		"→ %d" % loaded.calendar.abs_day())
	check("v1 没时钟时补 06:00", loaded.clock.minute_of_day == GameClock.DAY_START_MINUTE,
		loaded.clock.time_string())
	check("v1 没天气时补默认天气", loaded.weather.today != "")
	check("v1 农场补成 3×3", loaded.farm.width == 3 and loaded.farm.height == 3
		and loaded.farm.plots.size() == 9)
	check("v1 地块状态不丢", loaded.farm.get_plot(0).state == FarmPlot.State.TILLED
		and loaded.farm.is_autumn_plowed(0))
	check("v1 世界补默认出生点", loaded.world.get("location_id") == "L01")
	check("v1 任务/事件/采集有默认结构", loaded.quests.has("active")
		and loaded.events.has("done") and loaded.forage.has("collected"))
	check("旧 NPC id 迁移", loaded.npc_affection("zhang_xiaofang") == 17)
	check("旧关系升级出礼物与事件字段",
		loaded.relationships["zhang_xiaofang"].has("gifted_today")
		and loaded.relationships["zhang_xiaofang"].has("events_done"))
	check("旧明信片与语音开关不丢", loaded.postcards_collected.has("p_dawn")
		and not loaded.voice_enabled and bool(loaded.flags.get("old_flag", false)))

func test_legacy_winter_start_migration() -> void:
	print("\n[2b] 旧版冬季空档自动迁到春播起点")
	var legacy := {
		"schema_version": 2,
		"player": {"gold": 500, "inventory": {}, "energy": 100},
		"calendar": {"year": 1, "day_of_year": 0},
		"clock": {"minute_of_day": GameClock.DAY_START_MINUTE},
		"farm": {"width": 3, "height": 3, "plots": []},
		"world": {"location_id": "L02", "player_x": 640, "player_y": 760},
		"quests": {"active": [], "completed": []},
		"events": {"done": [], "flags": {}, "done_days": {}},
		"relationships": {},
		"postcards_collected": [],
		"postcards_pending": [],
	}
	var loaded := GameState.from_dict(legacy)
	check("旧空档迁到春季第 1 天", loaded.calendar.get_season() == "spring"
		and loaded.calendar.get_season_day() == 1,
		"→ %s" % loaded.calendar.date_string())
	check("旧空档迁到自家农场", String(loaded.world.get("location_id", "")) == "L01",
		"→ %s" % loaded.world.get("location_id", ""))
	check("旧空档补发开局种子",
		int(loaded.player.inventory.get("seed_corn", 0)) >= 6,
		"→ %s" % str(loaded.player.inventory))

	var progressed := legacy.duplicate(true)
	progressed["calendar"] = {"year": 1, "day_of_year": 0}
	progressed["relationships"] = {"zhang_xiaofang": {"affection": 12}}
	var kept := GameState.from_dict(progressed)
	check("已有进度的冬季旧档不被重开",
		kept.calendar.get_season() == "winter" and kept.calendar.abs_day() == 0,
		"→ %s" % kept.calendar.date_string())

func test_farm_expand() -> void:
	print("\n[3] 农场扩建保留旧地块")
	var farm := FarmSystem.new(GameCalendar.new())
	check("默认 3×3", farm.width == 3 and farm.height == 3 and farm.plots.size() == 9)
	farm.plots[0].till()
	farm.plots[0].autumn_plough()
	farm.ensure_size(16)
	check("扩到 4×4", farm.width == 4 and farm.height == 4 and farm.plots.size() == 16)
	check("旧地块状态保留", farm.plots[0].state == FarmPlot.State.TILLED
		and farm.plots[0].autumn_plowed)
	farm.ensure_size(20)
	check("继续扩到 5×4", farm.width == 5 and farm.height == 4 and farm.plots.size() == 20)
	farm.ensure_size(12)
	check("ensure_size 不缩地", farm.plots.size() == 20)
	var restored := FarmSystem.from_dict(JSON.parse_string(JSON.stringify(farm.to_dict())),
		GameCalendar.new())
	check("扩建宽高可往返", restored.width == 5 and restored.height == 4
		and restored.plots.size() == 20)

func test_atomic_write() -> void:
	print("\n[4] 存档原子写入")
	var path := "user://bzc_save_v2_%d.json" % Time.get_ticks_usec()
	var tmp := path + ".tmp"
	check("首次写入成功", SaveMigrator.atomic_write(path, "{\"schema_version\":2,\"value\":1}"))
	check("读回首次内容", _read(path).contains("\"value\":1"))
	check("不残留临时文件", not FileAccess.file_exists(tmp))
	check("覆盖写入成功", SaveMigrator.atomic_write(path, "{\"schema_version\":2,\"value\":2}"))
	check("读回覆盖内容", _read(path).contains("\"value\":2"))
	check("覆盖后仍无临时文件", not FileAccess.file_exists(tmp))
	DirAccess.remove_absolute(path)

func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text
