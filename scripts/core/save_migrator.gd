extends RefCounted
class_name SaveMigrator

## 存档 schema 迁移与原子写入。
## v1 → v2 补齐时钟、天气、世界、任务、事件、采集和关系事件字段；
## 旧键 npc_relationships 会升级为 v2 的 relationships。

const CURRENT_VERSION := 2

static func atomic_write(path: String, payload: String) -> bool:
	if path.strip_edges() == "":
		return false
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		if DirAccess.make_dir_recursive_absolute(dir) != OK:
			return false
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("存档临时文件写入失败: %s" % tmp)
		return false
	f.store_string(payload)
	f.flush()
	f.close()

	var err := DirAccess.rename_absolute(tmp, path)
	if err == OK:
		return true

	# Windows 上目标文件已存在时 rename 可能失败。先把旧档移到备份，
	# 新档替换成功后再删备份；任一步失败都恢复旧档。
	var backup := path + ".bak"
	if not FileAccess.file_exists(path):
		DirAccess.remove_absolute(tmp)
		return false
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	if DirAccess.rename_absolute(path, backup) != OK:
		DirAccess.remove_absolute(tmp)
		return false
	if DirAccess.rename_absolute(tmp, path) == OK:
		DirAccess.remove_absolute(backup)
		return true
	DirAccess.rename_absolute(backup, path)
	DirAccess.remove_absolute(tmp)
	return false

static func migrate(source: Dictionary) -> Dictionary:
	var d: Dictionary = source.duplicate(true)
	d["schema_version"] = CURRENT_VERSION

	var cal: Dictionary = _dict(d.get("calendar", {}))
	if not cal.has("absolute_day"):
		var year := maxi(1, int(cal.get("year", 1)))
		var day_of_year := clampi(int(cal.get("day_of_year", 0)), 0,
			GameCalendar.DAYS_PER_YEAR - 1)
		cal["absolute_day"] = (year - 1) * GameCalendar.DAYS_PER_YEAR + day_of_year
	d["calendar"] = cal

	var clock_data: Dictionary = _dict(d.get("clock", {}))
	if not clock_data.has("minute_of_day"):
		clock_data["minute_of_day"] = int(cal.get("minute_of_day", GameClock.DAY_START_MINUTE))
	d["clock"] = clock_data

	var weather: Dictionary = _dict(d.get("weather", {}))
	if String(weather.get("today", "")) == "":
		weather["today"] = WeatherSystem.DEFAULT_TODAY
	if String(weather.get("tomorrow", "")) == "":
		weather["tomorrow"] = WeatherSystem.DEFAULT_TOMORROW
	if not weather.has("seed"):
		weather["seed"] = 0
	d["weather"] = weather

	var world: Dictionary = _dict(d.get("world", {}))
	if String(world.get("location_id", "")) == "":
		world["location_id"] = "L01"
	if not world.has("player_x"):
		var start_map := MapDatabase.get_map("L01")
		var start_spawn := MapDatabase.spawn_point(start_map)
		world["player_x"] = start_spawn.x
	if not world.has("player_y"):
		var start_map_y := MapDatabase.get_map("L01")
		var start_spawn_y := MapDatabase.spawn_point(start_map_y)
		world["player_y"] = start_spawn_y.y
	d["world"] = world

	var quests: Dictionary = _dict(d.get("quests", {}))
	if not quests.has("active"):
		quests["active"] = []
	if not quests.has("completed"):
		quests["completed"] = []
	d["quests"] = quests

	var events: Dictionary = _dict(d.get("events", {}))
	if not events.has("done"):
		events["done"] = []
	if not events.has("flags"):
		events["flags"] = {}
	if not events.has("done_days"):
		events["done_days"] = {}
	if not events.has("active"):
		events["active"] = ""
	d["events"] = events

	var forage: Dictionary = _dict(d.get("forage", {}))
	if not forage.has("collected"):
		forage["collected"] = {}
	if not forage.has("last_day"):
		forage["last_day"] = -1
	d["forage"] = forage

	var relationships: Dictionary = _dict(d.get("relationships", d.get("npc_relationships", {})))
	var upgraded: Dictionary = {}
	for npc_id in relationships.keys():
		var entry: Dictionary = _dict(relationships[npc_id]).duplicate(true)
		entry["affection"] = maxi(0, int(entry.get("affection", 0)))
		if not entry.has("gifted_today"):
			entry["gifted_today"] = false
		if not entry.has("talked_today"):
			entry["talked_today"] = false
		if not entry.has("events_done"):
			entry["events_done"] = []
		upgraded[String(npc_id)] = entry
	d["relationships"] = upgraded
	d.erase("npc_relationships")

	var farm: Dictionary = _dict(d.get("farm", {}))
	if not farm.has("width"):
		farm["width"] = FarmSystem.DEFAULT_WIDTH
	if not farm.has("height"):
		farm["height"] = FarmSystem.DEFAULT_HEIGHT
	if not farm.has("plots"):
		farm["plots"] = []
	d["farm"] = farm
	return d

static func _dict(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
