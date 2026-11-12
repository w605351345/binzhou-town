extends RefCounted
class_name GameState

## 全局游戏状态(可序列化到存档)

var player: PlayerProfile = null
var calendar: GameCalendar = null
var farm: FarmSystem = null
var postcards_collected: Array = []
var postcards_pending: Array = []
var npc_relationships: Dictionary = {}
var drama_progress: Dictionary = {}
var flags: Dictionary = {}

func _init() -> void:
	player = PlayerProfile.new()
	calendar = GameCalendar.new()
	farm = FarmSystem.new(calendar)

func to_dict() -> Dictionary:
	return {
		"player": player.to_dict(),
		"calendar": calendar.to_dict(),
		"farm": farm.to_dict(),
		"postcards_collected": postcards_collected,
		"postcards_pending": postcards_pending,
		"npc_relationships": npc_relationships,
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
	s.drama_progress = d.get("drama_progress", {})
	s.flags = d.get("flags", {})
	return s
