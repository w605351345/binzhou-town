extends Node2D
class_name LocationScene

## 通用地点场景:L01-L11 共用一套数据驱动外壳。
## 负责地图渲染、玩家/相机、空间门、互动点、NPC 容器和 L01 农场操作。

@export var location_id: String = ""

const PLAYER_SCENE := "res://scenes/player.tscn"
const NPC_SCENE := "res://scenes/npc_zhangxiaofang.tscn"

var map: Dictionary = {}
var player: CharacterBody2D = null
var camera: Camera2D = null
var map_renderer: MapRenderer = null
var npc_container: Node2D = null
var plot_container: Node2D = null
var message_label: Label = null
var prompt_label: Label = null
var plot_info_label: Label = null

var _entry_spawn: Vector2 = Vector2(-1, -1)
var _views: Array = []
var _selected_crop: String = ""
var _door_cooldown := 0.8
var _npc_nodes: Array = []
var _npc_signature := ""
var _nearby_interactable: Dictionary = {}
var _collision_root: StaticBody2D = null
var _standalone_hud := true
var _last_message := ""
var _last_prompt := ""
var _last_plot_info := ""
var _highlighted_plot := -1
var _seed_crop_id := ""

func setup(p_location_id: String, p_spawn: Vector2 = Vector2(-1, -1)) -> void:
	location_id = p_location_id
	_entry_spawn = p_spawn

func _ready() -> void:
	if location_id == "":
		location_id = "L01"
	map = MapDatabase.get_map(location_id)
	if map.is_empty():
		push_error("未知地图: %s" % location_id)
		return
	_build_scene()
	_spawn_npcs()
	_maybe_trigger_event.call_deferred()
	if map.has("farm_area"):
		_build_farm_plots()
		_seed_crop_id = ToolBar.default_seed_crop(GameStateManager.state.farm)
		_selected_crop = _seed_crop_id
	GameStateManager.day_started.connect(_on_day_started)
	GameStateManager.clock_changed.connect(_on_clock_changed)
	GameStateManager.season_changed.connect(_on_season_changed)
	# 地点名和季节已经在常驻 HUD 里,这里只留交互/事件消息,避免重复占屏。
	_show_message("")

func _build_scene() -> void:
	var size := MapDatabase.map_size(map)
	map_renderer = MapRenderer.new()
	map_renderer.name = "MapRenderer"
	map_renderer.setup(map, GameStateManager.state.calendar.get_season())
	add_child(map_renderer)
	_build_collision()

	npc_container = Node2D.new()
	npc_container.name = "NpcContainer"
	npc_container.z_index = 8
	add_child(npc_container)

	plot_container = Node2D.new()
	plot_container.name = "PlotContainer"
	add_child(plot_container)

	var packed: PackedScene = load(PLAYER_SCENE)
	player = packed.instantiate()
	player.name = "Player"
	player.set("world", WorldMap.new(Rect2(Vector2.ZERO, Vector2(size))))
	var spawn := MapDatabase.spawn_point(map)
	if _entry_spawn.x >= 0.0 and _entry_spawn.y >= 0.0:
		spawn = _entry_spawn
	elif String(GameStateManager.state.world.get("location_id", "")) == location_id:
		spawn = Vector2(float(GameStateManager.state.world.get("player_x", spawn.x)),
			float(GameStateManager.state.world.get("player_y", spawn.y)))
	player.position = spawn
	player.z_index = 20
	add_child(player)

	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.zoom = Vector2(1.35, 1.35)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = size.x
	camera.limit_bottom = size.y
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	player.add_child(camera)
	camera.make_current()
	camera.reset_smoothing()

	_build_hud()
	GameStateManager.state.world["location_id"] = location_id
	GameStateManager.state.world["player_x"] = player.position.x
	GameStateManager.state.world["player_y"] = player.position.y

func _build_hud() -> void:
	_standalone_hud = not _has_shell_hud()
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	layer.visible = _standalone_hud
	add_child(layer)
	message_label = Label.new()
	message_label.name = "MessageLabel"
	message_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	message_label.offset_left = 40
	message_label.offset_top = -194
	message_label.offset_right = -40
	message_label.offset_bottom = -140
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 22)
	message_label.add_theme_color_override("font_color", Color(0.96, 0.91, 0.76))
	layer.add_child(message_label)
	prompt_label = Label.new()
	prompt_label.name = "PromptLabel"
	prompt_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	prompt_label.offset_left = 40
	prompt_label.offset_top = -112
	prompt_label.offset_right = -40
	prompt_label.offset_bottom = -64
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 22)
	prompt_label.add_theme_color_override("font_color", Color(0.98, 0.79, 0.32))
	layer.add_child(prompt_label)
	plot_info_label = Label.new()
	plot_info_label.name = "PlotInfoLabel"
	plot_info_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	plot_info_label.offset_left = 40
	plot_info_label.offset_top = 112
	plot_info_label.offset_right = -40
	plot_info_label.offset_bottom = 157
	plot_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plot_info_label.add_theme_font_size_override("font_size", 21)
	plot_info_label.add_theme_color_override("font_color", Color(0.88, 0.84, 0.70))
	layer.add_child(plot_info_label)

## 给实体道具和墙体加碰撞,避免人物穿过房屋、柜台、树干和水面。
## 门框已经从 MapDatabase.solid_rects() 里挖掉,不会把入口封死。
func _build_collision() -> void:
	_collision_root = StaticBody2D.new()
	_collision_root.name = "WorldCollision"
	_collision_root.collision_layer = 1
	_collision_root.collision_mask = 5
	add_child(_collision_root)
	for rect in MapDatabase.solid_rects(map):
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.position = rect.position + rect.size * 0.5
		_collision_root.add_child(shape)

func _has_shell_hud() -> bool:
	var cursor: Node = get_parent()
	while cursor != null:
		if cursor.name == "Game" and cursor.get_node_or_null("HUD") != null:
			return true
		cursor = cursor.get_parent()
	return false

func _spawn_npcs() -> void:
	_refresh_npcs(true)

func _refresh_npcs(force: bool = false) -> void:
	if npc_container == null:
		return
	var state := GameStateManager.state
	var entries := NpcRegistry.npcs_in_location(location_id, state.calendar,
		state.clock, state.weather)
	var signature := _signature_for(entries)
	if not force and signature == _npc_signature:
		return
	_npc_signature = signature
	for child in npc_container.get_children():
		npc_container.remove_child(child)
		child.queue_free()
	_npc_nodes.clear()
	var packed: PackedScene = load(NPC_SCENE)
	if packed == null:
		push_error("NPC 场景加载失败: %s" % NPC_SCENE)
		return
	for entry in entries:
		var npc := NpcBase.from_data(entry.get("data", {}))
		npc.position = entry.get("position", Vector2.ZERO)
		npc.activity = String(entry.get("activity", ""))
		npc.schedule_available = true
		npc.affection = state.npc_affection(npc.id)
		npc.current_day = state.calendar.day_of_year
		var node: NpcNode = packed.instantiate()
		node.name = "Npc_" + npc.id
		npc_container.add_child(node)
		node.setup(npc)
		_npc_nodes.append(node)

func _signature_for(entries: Array) -> String:
	var parts: Array = []
	for entry in entries:
		var pos: Vector2 = entry.get("position", Vector2.ZERO)
		parts.append("%s@%.1f,%.1f:%s" % [entry.get("id", ""), pos.x, pos.y,
			entry.get("activity", "")])
	return "|".join(parts)

func _build_farm_plots() -> void:
	var area: Dictionary = map["farm_area"]
	var origin_raw: Array = area.get("origin", [0, 0])
	var origin := Vector2(float(origin_raw[0]), float(origin_raw[1]))
	var cols := maxi(1, GameStateManager.state.farm.width)
	var plot_size := float(area.get("plot_size", 88.0))
	var farm := GameStateManager.state.farm
	for child in plot_container.get_children():
		child.queue_free()
	_views.clear()
	for i in farm.plots.size():
		var col := i % cols
		var row := i / cols
		var view := FarmPlotView.new()
		view.name = "Plot_%d" % i
		view.position = origin + Vector2(col * plot_size, row * plot_size)
		view.setup(farm.get_plot(i), farm.calendar)
		plot_container.add_child(view)
		_views.append(view)

func _physics_process(delta: float) -> void:
	if player == null:
		return
	_door_cooldown = maxf(0.0, _door_cooldown - delta)
	GameStateManager.state.world["player_x"] = player.position.x
	GameStateManager.state.world["player_y"] = player.position.y
	if GameStateManager.input_locked or GameStateManager.is_paused():
		return
	if _door_cooldown <= 0.0:
		var door := door_at(player.position)
		if not door.is_empty():
			_use_door(door)

func _process(_delta: float) -> void:
	_refresh_prompt()
	_refresh_plot_info()
	_refresh_plot_highlight()

func door_at(point: Vector2) -> Dictionary:
	return MapDatabase.door_at(map, point)

func _use_door(door: Dictionary) -> void:
	var target := String(door.get("target", ""))
	if target == "" or not SceneRouter.is_implemented(target):
		return
	var raw: Array = door.get("target_spawn", [])
	var spawn := Vector2(-1, -1)
	if raw.size() >= 2:
		spawn = Vector2(float(raw[0]), float(raw[1]))
	_door_cooldown = 1.0
	GameStateManager.request_travel(target, spawn)

func _refresh_prompt() -> void:
	if prompt_label == null or player == null:
		return
	var npc := _nearest_npc()
	if not npc.is_empty():
		map_renderer.set_focus_target(npc["node"].npc.today_position(), "npc")
		_set_prompt("E / A · 和%s说话" % npc.get("label", "人"))
		return
	if location_id == "L01":
		var plot_idx := _plot_near_player()
		if plot_idx >= 0:
			var context := _plot_context(plot_idx)
			map_renderer.set_focus_target((_views[plot_idx] as FarmPlotView).global_position, "plot")
			# 地块状态和倒计时由 PlotInfo 单独显示，动作提示不再重复“几号地”。
			_set_prompt("E / A · %s" % context.get("label", "耕作"))
			return
	var door := _nearest_door()
	if not door.is_empty():
		map_renderer.set_focus_target(MapDatabase.door_rect(door).get_center(), "door")
		_set_prompt("走进门 · %s" % door.get("label", "离开"))
		return
	_nearby_interactable = MapDatabase.nearest_interactable(map, player.global_position)
	if _nearby_interactable.is_empty():
		map_renderer.set_focus_target(Vector2.INF)
		_set_prompt("")
	else:
		var raw: Array = _nearby_interactable.get("pos", [0, 0])
		map_renderer.set_focus_target(Vector2(float(raw[0]), float(raw[1])), "interact")
		_set_prompt("E / A · %s" % _nearby_interactable.get("label", "互动"))

## 门提示的感知范围略大于门框本身，让玩家在门口就知道这里能出去。
func _nearest_door() -> Dictionary:
	if player == null:
		return {}
	var best: Dictionary = {}
	var best_dist := 150.0
	for door in map.get("doors", []):
		if typeof(door) != TYPE_DICTIONARY:
			continue
		var rect := MapDatabase.door_rect(door)
		var dist := player.global_position.distance_to(rect.get_center())
		if rect.grow(36.0).has_point(player.global_position):
			dist = 0.0
		if dist < best_dist:
			best_dist = dist
			best = door
	return best

func _nearest_npc() -> Dictionary:
	if player == null:
		return {}
	var candidates: Array = []
	for node in _npc_nodes:
		if node == null or node.npc == null:
			continue
		candidates.append({"node": node, "position": node.npc.today_position(),
			"label": node.npc.name})
	# 小镇交互以"靠近"为准。朝向只影响角色动画,不能成为 E/A 失效的门槛。
	var idx := InteractionSystem.find_nearest(player.global_position, candidates, 132.0)
	return {} if idx < 0 else candidates[idx]

func _unhandled_input(event: InputEvent) -> void:
	if GameStateManager.input_locked or GameStateManager.is_paused():
		return
	if event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("travel"):
		_debug_leave()
	elif location_id == "L01" and event.is_action_pressed("tool_till"):
		_use_tool(ToolBar.Tool.TILL)
	elif location_id == "L01" and event.is_action_pressed("tool_water"):
		_use_tool(ToolBar.Tool.WATER)
	elif location_id == "L01" and event.is_action_pressed("tool_seed"):
		_use_tool(ToolBar.Tool.SEED)
	elif location_id == "L01" and event.is_action_pressed("tool_harvest"):
		_use_tool(ToolBar.Tool.HARVEST)
	elif location_id == "L01" and event.is_action_pressed("tool_plough"):
		_use_autumn_plough()
	elif event.is_action_pressed("sleep"):
		_try_sleep()

func _interact() -> void:
	if GameStateManager.input_locked:
		return
	if _maybe_trigger_event():
		return
	var npc := _nearest_npc()
	if not npc.is_empty():
		GameStateManager.dialogue_requested.emit(npc["node"].npc)
		return
	if location_id == "L01":
		var plot_idx := _plot_near_player()
		if plot_idx >= 0:
			var context := _plot_context(plot_idx)
			_use_tool(int(context.get("tool", ToolBar.Tool.TILL)))
			return
	var item := MapDatabase.nearest_interactable(map, player.global_position)
	if item.is_empty():
		_show_message("这附近没有能搭手的东西")
		return
	_handle_interactable(item)

func _handle_interactable(item: Dictionary) -> void:
	var action := String(item.get("action", ""))
	var label := String(item.get("label", "互动"))
	var festival := FestivalSystem.is_today(GameStateManager.state.calendar)
	if action != "quest_board" and not festival.is_empty() \
			and String(festival.get("location_id", "")) == location_id:
		_handle_festival(festival, action)
		return
	match action:
		"post_office":
			GameStateManager.post_office_requested.emit()
		"sleep":
			_wait_one_day()
		"forecast":
			var weather := GameStateManager.state.weather
			_show_message("明日预报:%s。%s" % [WeatherSystem.weather_cn(weather.forecast),
				WeatherSystem.hint_for(weather.forecast)])
		"almanac":
			_show_message(FarmAlmanac.full_tip(GameStateManager.state.calendar,
				GameStateManager.state.farm))
		"well":
			_show_message("井水冰凉。地要浇透，人才睡得踏实。")
		"eat":
			GameStateManager.state.player.stamina.restore(18)
			_show_message("热乎饭下肚，缓过来一些。")
		"clinic":
			GameStateManager.state.player.stamina.restore(25)
			_show_message("林小满给你处理了伤口，又叮嘱别硬撑。")
		"cook":
			GameStateManager.activity_requested.emit("cooking")
		"shop", "market":
			GameStateManager.shop_requested.emit()
		"storage":
			GameStateManager.inventory_requested.emit()
		"workshop":
			var expanded := FarmExpansionSystem.expand(GameStateManager.state)
			_show_message(String(expanded.get("message", "")))
		"theater":
			GameStateManager.drama_requested.emit()
			_show_message("《月桂谣》的戏页摊在台口。选一幕，和周德顺把这场戏排下去。")
		"fishing":
			GameStateManager.activity_requested.emit("fishing")
		"forage":
			_collect_forage(item)
		"quest_board":
			GameStateManager.quest_board_requested.emit()
		"crafting", "blacksmith", "livestock", "fishmonger", "museum", "merchant", "shipping", "mine", "community":
			GameStateManager.service_requested.emit(action)
		_:
			_show_message("%s:%s" % [label, _placeholder_hint(action)])

func _watch_theater(label: String) -> void:
	var state := GameStateManager.state
	var visits := int(state.drama_progress.get("theater_visits", 0)) + 1
	state.drama_progress["theater_visits"] = visits
	if label.contains("剧场铃"):
		state.drama_progress["zhou_beat_lesson"] = true
		_show_message("周德顺把鼓槌递给你：“别使劲砸，听板眼。”你跟着敲了四拍，他难得没挑毛病。")
		return
	if Array(state.events.get("done", [])).has("zhou_e3"):
		_show_message("周德顺看见你，抬手把台口让出一块。台上唱到《月桂谣》的团圆段，台下有人跟着哼。"
			+ "他说：“这满台，不是等来的。”")
	elif Array(state.events.get("done", [])).has("zhou_e1"):
		_show_message("周德顺在后台调弦，见你来了，清了清嗓子唱半段《月桂谣》。"
			+ "唱到高处，他停了一下，说：“后头那几句，得有人接。”")
	else:
		state.flags["watched_zhou_stage"] = true
		_show_message("周德顺正弯着腰扫台。他指着台口说：“戏不是天天有，台得天天扫。”"
			+ "扫到第三级台阶，又给你哼了两句《月桂谣》。")

func _collect_forage(item: Dictionary) -> void:
	var key := ForageSystem.point_key_for(map, String(item.get("id", "")),
		GameStateManager.state.calendar)
	if key == "":
		_show_message("这一处眼下没有能采的东西。等换了时节再来。")
		return
	var result := ForageSystem.collect(GameStateManager.state, key)
	_show_message(String(result.get("message", "什么也没采到。")))

## 节日当天，节日地点本身就是活动入口；不同互动点优先匹配对应玩法。
func _handle_festival(festival: Dictionary, action: String) -> void:
	var chosen: Dictionary = {}
	for activity in festival.get("activities", []):
		if String(activity.get("action", "")) == action:
			chosen = activity
			break
	var names: Array = []
	for activity in festival.get("activities", []):
		names.append(String(activity.get("name", "")))
	var activity_name := String(chosen.get("name", names[0] if not names.is_empty() else "赶热闹"))
	if action == "fishing":
		GameStateManager.activity_requested.emit("fishing")
		_show_message("【%s】%s开始了。鱼群贴着河心走。" % [
			festival.get("name", "节日"), activity_name])
		return
	if action == "eat":
		GameStateManager.state.player.stamina.restore(24)
		_show_message("【%s】%s。热菜热饭，吃得浑身舒坦。" % [
			festival.get("name", "节日"), activity_name])
		return
	GameStateManager.state.player.stamina.restore(12)
	_show_message("【%s】%s\n%s\n今天可参与：%s。" % [
		festival.get("name", "节日"), festival.get("desc", ""),
		activity_name, "、".join(names)])

func _placeholder_hint(action: String) -> String:
	match action:
		"cook": return "灶上还空着，等学会菜谱再来。"
		"storage": return "柜子里收着这一季的家当。"
		"quest_board": return "公告板上的纸被风掀起一角。"
		"market": return "集市正热闹，摊主们还没收摊。"
		"shop": return "货架上的种子和工具都摆出来了。"
		"workshop": return "赵长河量了量院子的尺寸，说还能再扩。"
		"fishing": return "水面泛着光，鱼星在不远处打转。"
		"forage": return "林子里有新鲜的脚印和菌丝。"
		"theater": return "剧场空着，风从后台穿过。"
		"crafting": return "工作台上还缺几样材料。"
		"shipping": return "运输箱的盖板被风吹得轻响。"
		"mine": return "矿洞口往里冒着冷气。"
		"museum": return "镇史馆的灯还亮着。"
		"community": return "工程板上的清单又被人添了一笔。"
	return "这里还没有开放。"

func _debug_leave() -> void:
	match location_id:
		"L01": GameStateManager.travel_requested.emit("L03")
		"L02": GameStateManager.travel_requested.emit("L01")
		"L03": GameStateManager.travel_requested.emit("L01")
		"L05": GameStateManager.travel_requested.emit("L03")
		_: GameStateManager.travel_requested.emit("L03")

## 旧测试/调试入口:保留方法名，正式移动仍由空间门完成。
func _go_to_town() -> void:
	GameStateManager.travel_requested.emit("L03")

func _go_to_farm() -> void:
	GameStateManager.travel_requested.emit("L01")

func _go_to_post_office() -> void:
	GameStateManager.travel_requested.emit("L05")

func _open_postbox() -> void:
	GameStateManager.post_office_requested.emit()

func _wait_one_day() -> void:
	GameStateManager.advance_day()
	var cal := GameStateManager.state.calendar
	_show_message("一觉到天亮 · %s · 体力已恢复 · 今日%s" % [
		cal.date_short(), WeatherSystem.weather_cn(GameStateManager.state.weather.today)])

## 睡觉必须回农舍并靠近木床;T 只是 E 交互的快捷键,不是随处跳天。
func _try_sleep() -> bool:
	if location_id != "L02":
		_show_message("得回农舍木床上睡。")
		return false
	var bed := MapDatabase.nearest_interactable(map, player.global_position)
	if bed.is_empty() or String(bed.get("action", "")) != "sleep":
		_show_message("走近木床再睡。")
		return false
	_wait_one_day()
	return true

func _plot_near_player() -> int:
	if player == null or _views.is_empty():
		return -1
	var best := -1
	var best_dist := 128.0
	for i in _views.size():
		var view := _views[i] as FarmPlotView
		if view == null:
			continue
		var dist := view.global_position.distance_to(player.global_position)
		if dist < best_dist:
			best_dist = dist
			best = i
	return best

## 靠近地块按 E 时,按地块当前阶段给出唯一合理动作。
## 这样玩家不需要先背 J/K/L/I 四个键,也能从荒地一路种到收获。
func _plot_context(index: int) -> Dictionary:
	var plot := GameStateManager.state.farm.get_plot(index)
	if plot == null:
		return {"tool": ToolBar.Tool.TILL, "label": "翻土"}
	match plot.state:
		FarmPlot.State.UNTILLED, FarmPlot.State.FALLOW:
			return {"tool": ToolBar.Tool.TILL, "label": "翻土"}
		FarmPlot.State.TILLED:
			return {"tool": ToolBar.Tool.SEED, "label": "播种"}
		FarmPlot.State.PLANTED, FarmPlot.State.GROWING:
			return {"tool": ToolBar.Tool.WATER, "label": "浇水"}
		FarmPlot.State.READY:
			return {"tool": ToolBar.Tool.HARVEST, "label": "收获"}
		FarmPlot.State.DEAD:
			return {"tool": ToolBar.Tool.TILL, "label": "清理枯株"}
	return {"tool": ToolBar.Tool.TILL, "label": "翻土"}

func _refresh_plot_highlight() -> void:
	if _views.is_empty():
		return
	var idx := _plot_near_player() if location_id == "L01" else -1
	if idx == _highlighted_plot:
		return
	_highlighted_plot = idx
	for i in _views.size():
		var view := _views[i] as FarmPlotView
		if view != null:
			view.set_highlight(i == idx)

func _use_tool(tool: int) -> void:
	var idx := _plot_near_player()
	if idx < 0:
		_show_message("走近一块地再动手")
		return
	var farm := GameStateManager.state.farm
	var weather_mult := WeatherSystem.outdoor_stamina_multiplier(
		GameStateManager.state.weather.today)
	var energy_before := GameStateManager.state.player.energy
	var result := ToolBar.apply_tool(tool, farm, idx, GameStateManager.state.player,
		_selected_crop, weather_mult)
	var spent := maxi(0, energy_before - GameStateManager.state.player.energy)
	if tool == ToolBar.Tool.HARVEST and bool(result.get("ok", false)):
		var harvested := int(Dictionary(result.get("result", {})).get("amount", 0))
		if harvested > 0:
			QuestSystem.progress(GameStateManager.state, "harvest", harvested)
			GameStateManager.state.flags["harvested_total"] = \
				int(GameStateManager.state.flags.get("harvested_total", 0)) + harvested
	if bool(result.get("ok", false)):
		var minutes: int = int({
			ToolBar.Tool.TILL: 15,
			ToolBar.Tool.WATER: 6,
			ToolBar.Tool.SEED: 8,
			ToolBar.Tool.HARVEST: 12,
		}.get(tool, 8))
		GameStateManager.spend_time(minutes)
	var message := String(result.get("message", ""))
	if bool(result.get("ok", false)) and spent > 0:
		message += " · 体力 -%d（剩 %d）" % [spent, GameStateManager.state.player.energy]
	if tool == ToolBar.Tool.HARVEST and bool(result.get("ok", false)):
		message += "\n" + DramaSystem.farm_progress_text(GameStateManager.state)
	_show_message(message)
	_refresh_views()

func _use_autumn_plough() -> void:
	var idx := _plot_near_player()
	if idx < 0:
		_show_message("走近一块地再动手")
		return
	var weather_mult := WeatherSystem.outdoor_stamina_multiplier(
		GameStateManager.state.weather.today)
	var result := ToolBar.apply_autumn_plough(GameStateManager.state.farm, idx,
		GameStateManager.state.player, weather_mult)
	if bool(result.get("ok", false)):
		GameStateManager.spend_time(20)
	_show_message(String(result.get("message", "")))
	_refresh_views()

func _refresh_views() -> void:
	for view in _views:
		if view is FarmPlotView:
			view.queue_redraw()

func _refresh_plot_info() -> void:
	if plot_info_label == null or _views.is_empty():
		return
	var idx := _plot_near_player()
	if idx < 0:
		_set_plot_info("")
		return
	var farm := GameStateManager.state.farm
	var context := _plot_context(idx)
	_set_plot_info("【%d 号地】%s" % [idx + 1,
		FarmAlmanac.plot_tag(farm.get_plot(idx), farm.calendar)])

func _on_day_started(_day: int) -> void:
	_refresh_views()
	_refresh_npcs(true)
	_maybe_trigger_event.call_deferred()

func _on_clock_changed(_minute: int) -> void:
	_refresh_npcs(false)
	_maybe_trigger_event.call_deferred()

func _on_season_changed(next_season: String) -> void:
	if map_renderer != null:
		map_renderer.set_season(next_season)
	if map.has("farm_area"):
		_refresh_views()

func _maybe_trigger_event() -> bool:
	if GameStateManager.input_locked:
		return false
	var state := GameStateManager.state
	var event := EventSystem.available_event(state, location_id,
		state.calendar, state.clock, state.weather)
	if event.is_empty():
		return false
	GameStateManager.event_requested.emit(event)
	return true

func _show_message(text: String) -> void:
	if message_label != null:
		message_label.text = text
	if text != _last_message:
		_last_message = text
		_emit_context()

func _set_prompt(text: String) -> void:
	if prompt_label != null:
		prompt_label.text = text
	if text != _last_prompt:
		_last_prompt = text
		_emit_context()

func _set_plot_info(text: String) -> void:
	if plot_info_label != null:
		plot_info_label.text = text
	if text != _last_plot_info:
		_last_plot_info = text
		_emit_context()

func _emit_context() -> void:
	GameStateManager.location_context_changed.emit(_last_message, _last_prompt, _last_plot_info)
