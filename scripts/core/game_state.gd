extends RefCounted
class_name GameState

## 全局游戏状态(可序列化到存档)

var player: PlayerProfile = null
var calendar: GameCalendar = null
var farm: FarmSystem = null
var postcards_collected: Array = []
var postcards_pending: Array = []
var npc_relationships: Dictionary = {}
## 语音开关(玩家在暂停菜单里可关;存档记住这个选择)
var voice_enabled: bool = true
var drama_progress: Dictionary = {}
var flags: Dictionary = {}

func _init() -> void:
	player = PlayerProfile.new()
	calendar = GameCalendar.new()
	farm = FarmSystem.new(calendar)

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
	return {
		"player": player.to_dict(),
		"calendar": calendar.to_dict(),
		"farm": farm.to_dict(),
		"postcards_collected": postcards_collected,
		"postcards_pending": postcards_pending,
		"npc_relationships": npc_relationships,
		"voice_enabled": voice_enabled,
		"drama_progress": drama_progress,
		"flags": flags,
	}

static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.player = PlayerProfile.from_dict(d.get("player", {}))
	s.calendar = GameCalendar.from_dict(d.get("calendar", {}))
	s.farm = FarmSystem.from_dict(d.get("farm", {}), s.calendar)
	s.postcards_collected = d.get("postcards_collected", [])
	s.postcards_pending = d.get("postcards_pending", [])
	s.npc_relationships = d.get("npc_relationships", {})
	_migrate_npc_ids(s.npc_relationships)
	s.voice_enabled = bool(d.get("voice_enabled", true))
	s.drama_progress = d.get("drama_progress", {})
	s.flags = d.get("flags", {})
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
