extends RefCounted
class_name GameState

## 全局游戏状态(可序列化到存档)

const SCHEMA_VERSION := 3
const START_LOCATION := "L01"
## 开局给一小包种子,保证玩家第一次走到地里就能完成"翻土→播种"。
## 这不改变数值平衡,只是把原本需要先去杂货店买种子的第一步提前。
const STARTER_INVENTORY := {
	"seed_corn": 6,
	"seed_potato": 4,
	"food_sticky_bean_bun": 2,
}

var player: PlayerProfile = null
var calendar: GameCalendar = null
var clock: GameClock = null
var weather: WeatherSystem = null
var farm: FarmSystem = null
var world: Dictionary = {}
var quests: Dictionary = {}
var events: Dictionary = {}
var forage: Dictionary = {}
var postcards_collected: Array = []
var postcards_pending: Array = []
var _relationships: Dictionary = {}
## v2 键名。npc_relationships 保留为兼容别名，旧代码无需一次性迁移。
var relationships: Dictionary:
	get:
		return _relationships
	set(value):
		_relationships = value
var npc_relationships: Dictionary:
	get:
		return _relationships
	set(value):
		_relationships = value
## 语音开关保留为旧存档兼容字段；当前版本默认关闭 NPC 语音。
var voice_enabled: bool = false
var drama_progress: Dictionary = {}
var flags: Dictionary = {}
## v5.1 生活系统状态
var shipping: Dictionary = {"items": {}, "last_payout": 0, "lifetime": 0, "last_report": []}
var livestock: Dictionary = {"animals": [], "next_id": 1, "lifetime_products": 0}
var mine: Dictionary = {
	"floor": 1, "deepest": 1, "active": false, "ore_mined": 0,
	"monsters_defeated": 0, "visits": 0, "health": 100, "max_health": 100,
	"monster": {},
}
var museum: Dictionary = {"donated": [], "rewards": []}
var community: Dictionary = {"progress": {}, "completed": []}

func _init() -> void:
	player = PlayerProfile.new()
	player.inventory = STARTER_INVENTORY.duplicate(true)
	calendar = GameCalendar.new()
	clock = GameClock.new()
	weather = WeatherSystem.new()
	weather.refresh(calendar, weather.seed)
	farm = FarmSystem.new(calendar)
	flags = {
		"run_started_abs_day": calendar.abs_day(),
		"tutorial_talked": false,
	}
	var start_location := START_LOCATION
	var start_map := MapDatabase.get_map(start_location)
	var start_spawn := MapDatabase.spawn_point(start_map) if not start_map.is_empty() else Vector2(1510, 900)
	world = {
		"location_id": start_location,
		"player_x": start_spawn.x,
		"player_y": start_spawn.y,
	}
	quests = {"active": [], "completed": []}
	events = {"done": [], "done_days": {}, "flags": {}, "active": ""}
	forage = {"collected": {}, "last_day": -1}

## NPC 改名留下的旧存档键 → 新键(读档时自动迁移,好感度不丢)
const NPC_ID_MIGRATIONS := {
	"zhang_shen": "zhang_xiaofang",
}

## NPC 好感度(存档字段 npc_relationships:{npc_id: {affection: n}})
## NPC 对象每次进场景都会重建,好感度必须存在 GameState 里才不丢。
func npc_affection(npc_id: String) -> int:
	var rel: Dictionary = npc_relationships.get(npc_id, {})
	return int(rel.get("affection", 0))

func set_npc_affection(npc_id: String, value: int) -> void:
	var rel: Dictionary = npc_relationships.get(npc_id, {})
	rel["affection"] = maxi(0, value)
	npc_relationships[npc_id] = rel

func to_dict() -> Dictionary:
	var cal := calendar.to_dict()
	cal["minute_of_day"] = clock.minute_of_day
	return {
		"schema_version": SCHEMA_VERSION,
		"player": player.to_dict(),
		"calendar": cal,
		"clock": clock.to_dict(),
		"weather": weather.to_dict(),
		"farm": farm.to_dict(),
		"world": world.duplicate(true),
		"quests": quests.duplicate(true),
		"events": events.duplicate(true),
		"forage": forage.duplicate(true),
		"postcards_collected": postcards_collected,
		"postcards_pending": postcards_pending,
		"relationships": relationships.duplicate(true),
		"voice_enabled": voice_enabled,
		"drama_progress": drama_progress,
		"flags": flags,
		"shipping": shipping.duplicate(true),
		"livestock": livestock.duplicate(true),
		"mine": mine.duplicate(true),
		"museum": museum.duplicate(true),
		"community": community.duplicate(true),
	}

static func from_dict(d: Dictionary) -> GameState:
	var migrated := SaveMigrator.migrate(d)
	var s := GameState.new()
	s.player = PlayerProfile.from_dict(migrated.get("player", {}))
	s.calendar = GameCalendar.from_dict(migrated.get("calendar", {}))
	s.clock = GameClock.from_dict(migrated.get("clock", {}))
	s.weather = WeatherSystem.from_dict(migrated.get("weather", {}))
	s.farm = FarmSystem.from_dict(migrated.get("farm", {}), s.calendar)
	s.world = migrated.get("world", {}).duplicate(true)
	s.quests = migrated.get("quests", {}).duplicate(true)
	s.events = migrated.get("events", {}).duplicate(true)
	s.forage = migrated.get("forage", {}).duplicate(true)
	s.postcards_collected = migrated.get("postcards_collected", [])
	s.postcards_pending = migrated.get("postcards_pending", [])
	s.relationships = migrated.get("relationships", {}).duplicate(true)
	_migrate_npc_ids(s.npc_relationships)
	s.voice_enabled = bool(migrated.get("voice_enabled", false))
	s.drama_progress = migrated.get("drama_progress", {})
	s.flags = migrated.get("flags", {})
	s.shipping = migrated.get("shipping", s.shipping).duplicate(true)
	s.livestock = migrated.get("livestock", s.livestock).duplicate(true)
	s.mine = migrated.get("mine", s.mine).duplicate(true)
	s.museum = migrated.get("museum", s.museum).duplicate(true)
	s.community = migrated.get("community", s.community).duplicate(true)
	ShippingSystem.ensure_state(s)
	LivestockSystem.ensure_state(s)
	MiningSystem.ensure_state(s)
	MuseumSystem.ensure_state(s)
	CommunityProjectSystem.ensure_state(s)
	return s

## 把旧存档里的 NPC 键迁到新键(同名的新数据优先,不覆盖)
static func _migrate_npc_ids(rel: Dictionary) -> void:
	for old_id in NPC_ID_MIGRATIONS:
		if not rel.has(old_id):
			continue
		var new_id: String = NPC_ID_MIGRATIONS[old_id]
		if rel.has(new_id):
			rel.erase(old_id)
			continue
		rel[new_id] = rel[old_id]
		rel.erase(old_id)
