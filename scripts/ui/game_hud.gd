extends Node2D
## 游戏外壳:常驻 HUD(日期/金币/体力/农时倒计时)+ 世界场景容器。
##
## 麦溪镇设定:春播秋收,冬季休耕时显示提示。
## HUD 常驻"当前可播种"与"初霜倒计时" —— 这是风险 R2/R3 的对策,
## 让玩家一眼看出"现在该干嘛"。
##
## 世界场景(自家院 / 镇大街)装在 World 节点里,换地点时只换世界不换 HUD,
## 这样走到哪儿都看得见日期、体力和农时提示。

const START_LOCATION := "L01"
const Guidance = preload("res://scripts/core/guidance_system.gd")

@onready var world: Node2D = $World
@onready var hud_label: Label = $HUD/HBox/HudLabel
@onready var season_label: Label = $HUD/HBox/SeasonLabel
@onready var almanac_label: Label = $HUD/HBox/AlmanacLabel
@onready var stamina_bar: ProgressBar = $HUD/StaminaBar
@onready var context_label: Label = $HUD/BottomBox/ContextLabel
@onready var message_label: Label = $HUD/BottomBox/MessageLabel
@onready var tip_label: Label = $HUD/BottomBox/TipLabel
@onready var key_hint: Label = $HUD/BottomBox/KeyHint
@onready var guide_label: Label = $HUD/GuidePanel/GuideLabel
@onready var guide_title: Label = $HUD/GuidePanel/GuideTitle
@onready var guide_backdrop: ColorRect = $HUD/GuideBackdrop
@onready var scene_title: Label = $HUD/SceneTitle
@onready var bottom_backdrop: ColorRect = $HUD/BottomBackdrop
@onready var bottom_box: VBoxContainer = $HUD/BottomBox

var _calendar: GameCalendar
var _farm: FarmSystem
var _location_id: String = ""
var _environment_tint: CanvasModulate = null
var _weather_overlay: WeatherOverlay = null
## 普通消息是临时反馈，显示几秒后自动让位给近距离交互提示。
const MESSAGE_SECONDS := 5.0
var _message_time_left := 0.0
## 引导只在开局、换日或目标变化时短暂出现，避免常驻文案遮住田地。
var _guide_time_left := 8.0
var _last_guide_text := ""

## 对话框与商店面板:常驻在游戏外壳里(和 HUD 一样不随地点销毁)
var _dialogue_box: DialogueBox = null
var _shop_panel: ShopPanel = null
var _inventory_panel: InventoryPanel = null
var _postcard_panel: PostcardPanel = null
var _gift_panel: GiftPanel = null
var _fishing_panel: FishingPanel = null
var _cooking_panel: CookingPanel = null
var _quest_panel: QuestPanel = null
var _service_panel: ServicePanel = null
var _drama_panel: DramaPanel = null
var _overlay_layer: CanvasLayer = null
var _overlay_root: Control = null
var _overlay_panels: Array[Control] = []
var _music: MusicDirector = null
## 当前对话的 NPC(好感度要写回存档)
var _talking_npc: NpcBase = null
var _active_event: Dictionary = {}

func _ready() -> void:
	_calendar = GameStateManager.state.calendar
	_farm = GameStateManager.state.farm
	_build_environment_tint()
	_build_weather_overlay()
	_build_overlays()
	_music = MusicDirector.new()
	_music.name = "MusicDirector"
	add_child(_music)
	get_viewport().size_changed.connect(_fit_overlay_panels)
	if bottom_backdrop != null:
		bottom_backdrop.visible = false
	if bottom_box != null:
		bottom_box.visible = false
	_refresh_hud()
	GameStateManager.day_started.connect(_on_day_started)
	GameStateManager.season_changed.connect(_on_season_changed)
	GameStateManager.travel_requested.connect(_on_travel_requested)
	GameStateManager.dialogue_requested.connect(_on_dialogue_requested)
	GameStateManager.event_requested.connect(_on_event_requested)
	GameStateManager.activity_requested.connect(_on_activity_requested)
	GameStateManager.quest_board_requested.connect(_on_quest_board_requested)
	GameStateManager.post_office_requested.connect(_on_post_office_requested)
	GameStateManager.shop_requested.connect(_on_shop_requested)
	GameStateManager.inventory_requested.connect(_on_inventory_requested)
	GameStateManager.postcards_delivered.connect(_on_postcards_delivered)
	GameStateManager.player_collapsed.connect(_on_player_collapsed)
	GameStateManager.service_requested.connect(_on_service_requested)
	GameStateManager.drama_requested.connect(_on_drama_requested)
	GameStateManager.shipping_settled.connect(_on_shipping_settled)
	GameStateManager.livestock_produced.connect(_on_livestock_produced)
	GameStateManager.location_context_changed.connect(_on_location_context_changed)
	var start := String(GameStateManager.state.world.get("location_id", START_LOCATION))
	if not SceneRouter.is_implemented(start):
		start = START_LOCATION
	_travel_to(start)

func _build_environment_tint() -> void:
	_environment_tint = CanvasModulate.new()
	_environment_tint.name = "EnvironmentTint"
	add_child(_environment_tint)
	move_child(_environment_tint, 0)

func _build_weather_overlay() -> void:
	var layer := get_node_or_null("HUD") as CanvasLayer
	if layer == null:
		return
	_weather_overlay = WeatherOverlay.new()
	_weather_overlay.name = "WeatherOverlay"
	layer.add_child(_weather_overlay)
	layer.move_child(_weather_overlay, 0)

## 建对话/商店两个覆盖层(代码构建,不用改 .tscn)
func _build_overlays() -> void:
	# 世界里的 Camera2D 会影响默认画布上的所有 CanvasItem。UI 必须放进
	# 独立 CanvasLayer,否则弹层会随镜头漂移;再套一层 Control 负责视口布局。
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "UI"
	_overlay_layer.layer = 50
	add_child(_overlay_layer)
	_overlay_root = Control.new()
	_overlay_root.name = "OverlayRoot"
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.add_child(_overlay_root)
	_fit_overlay_root()

	_dialogue_box = DialogueBox.new()
	_dialogue_box.name = "DialogueBox"
	_dialogue_box.closed.connect(_on_dialogue_closed)
	_dialogue_box.action_triggered.connect(_on_dialogue_action)
	_mount_overlay(_dialogue_box)

	_shop_panel = ShopPanel.new()
	_shop_panel.name = "ShopPanel"
	_shop_panel.closed.connect(_on_shop_closed)
	_mount_overlay(_shop_panel)

	_inventory_panel = InventoryPanel.new()
	_inventory_panel.name = "InventoryPanel"
	_mount_overlay(_inventory_panel)

	_postcard_panel = PostcardPanel.new()
	_postcard_panel.name = "PostcardPanel"
	_mount_overlay(_postcard_panel)

	_gift_panel = GiftPanel.new()
	_gift_panel.name = "GiftPanel"
	_gift_panel.closed.connect(_on_gift_closed)
	_mount_overlay(_gift_panel)

	_fishing_panel = FishingPanel.new()
	_fishing_panel.name = "FishingPanel"
	_mount_overlay(_fishing_panel)

	_cooking_panel = CookingPanel.new()
	_cooking_panel.name = "CookingPanel"
	_mount_overlay(_cooking_panel)

	_quest_panel = QuestPanel.new()
	_quest_panel.name = "QuestPanel"
	_mount_overlay(_quest_panel)

	_service_panel = ServicePanel.new()
	_service_panel.name = "ServicePanel"
	_service_panel.gift_requested.connect(_on_service_gift_requested)
	_mount_overlay(_service_panel)

	_drama_panel = DramaPanel.new()
	_drama_panel.name = "DramaPanel"
	_mount_overlay(_drama_panel)

## Control 挂在 Node2D 下不会自动继承视口尺寸;显式铺满,否则居中面板
## 会以 (0,0) 为中心,真实窗口里只剩左上角一块黑边。
func _mount_overlay(panel: Control) -> void:
	_overlay_root.add_child(panel)
	_overlay_panels.append(panel)
	_fit_overlay(panel)

func _fit_overlay_root() -> void:
	if not is_instance_valid(_overlay_root):
		return
	_overlay_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_overlay_root.position = Vector2.ZERO
	_overlay_root.size = get_viewport_rect().size

func _fit_overlay(panel: Control) -> void:
	if not is_instance_valid(panel):
		return
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2.ZERO
	panel.size = get_viewport_rect().size

func _fit_overlay_panels() -> void:
	_fit_overlay_root()
	for panel in _overlay_panels:
		_fit_overlay(panel)

## Tab 开合背包
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_inventory"):
		return
	# 对话/商店开着的时候别再叠一层背包 —— 一个界面套一个界面,玩家会懵
	if GameStateManager.input_locked:
		return
	get_viewport().set_input_as_handled()
	if _inventory_panel != null:
		_inventory_panel.toggle()

## 邮局柜台:打开寄信 / 收藏册面板
func _on_post_office_requested() -> void:
	if _postcard_panel == null:
		return
	if _postcard_panel.is_open():
		_postcard_panel.close_panel()
	else:
		_postcard_panel.open_panel()

func _on_shop_requested() -> void:
	if _shop_panel == null:
		return
	if _shop_panel.is_open():
		_shop_panel.close_shop()
	else:
		_shop_panel.open_shop(null, ShopPanel.Mode.BUY)

func _on_inventory_requested() -> void:
	if _inventory_panel == null:
		return
	_inventory_panel.toggle()

## 次日投递:在 HUD 上明确告诉玩家收到谁的来信
func _on_postcards_delivered(cards: Array) -> void:
	if cards.is_empty():
		return
	if _postcard_panel != null and _postcard_panel.is_open():
		_postcard_panel.refresh()
	var titles: Array = []
	for card in cards:
		titles.append("《%s》" % card.get("title", "远方来信"))
	_show_message("邮差送来%s。去老邮局翻翻收藏册吧。" % "、".join(titles))

## 地点场景判定可交互后发出对话请求 —— 这里负责把对话跑起来
func _on_dialogue_requested(npc: NpcBase) -> void:
	if _dialogue_box == null or npc == null:
		return
	GameStateManager.state.flags["tutorial_talked"] = true
	if npc.service_type != "" and _service_panel != null:
		_service_panel.open_service(npc.service_type, npc)
		return
	var dialogue := DialogueData.dialogue_for_npc(npc.id)
	if dialogue.is_empty():
		_show_message("%s这会儿没什么想说的。" % npc.name)
		return
	_talking_npc = npc
	var runner := DialogueRunner.new()
	# flags 传的是 GameState 里的同一个字典 —— 对话里写的标记直接进存档
	runner.setup(dialogue.get("lines", []), GameStateManager.state.player,
		GameStateManager.state.calendar, npc, GameStateManager.state.flags,
		GameStateManager.state.events, GameStateManager.state.clock,
		GameStateManager.state.weather)
	runner.start()
	_dialogue_box.setup(npc, runner)
	_dialogue_box.open()
	GameStateManager.set_dialogue_open(true)

## 对话结束:好感度写回存档(下次进镇大街还在)
func _on_dialogue_closed() -> void:
	if _talking_npc != null:
		GameStateManager.state.set_npc_affection(_talking_npc.id, _talking_npc.affection)
	if not _active_event.is_empty():
		var title := String(_active_event.get("title", "这段事"))
		EventSystem.finish_event(GameStateManager.state,
			String(_active_event.get("id", "")))
		_active_event = {}
		_show_message("【%s】这段事记下了。" % title)
	_talking_npc = null
	GameStateManager.set_dialogue_open(false)

## 地点场景判定有人物事件后，复用对话框播放事件台词。
func _on_event_requested(event: Dictionary) -> void:
	if event.is_empty() or _dialogue_box == null or _dialogue_box.is_open():
		return
	var npc_id := String(event.get("npc_id", ""))
	var data := NpcRegistry.get_npc(npc_id)
	if data.is_empty():
		return
	var started := EventSystem.start_event(GameStateManager.state,
		String(event.get("id", "")))
	if started.is_empty():
		return
	_active_event = started
	_talking_npc = NpcBase.from_data(data)
	_talking_npc.affection = GameStateManager.state.npc_affection(npc_id)
	var runner := DialogueRunner.new()
	runner.setup(Array(started.get("lines", [])), GameStateManager.state.player,
		GameStateManager.state.calendar, _talking_npc,
		GameStateManager.state.flags, GameStateManager.state.events,
		GameStateManager.state.clock, GameStateManager.state.weather)
	runner.start()
	_dialogue_box.setup(_talking_npc, runner)
	_dialogue_box.open()
	GameStateManager.set_dialogue_open(true)

## 对话里的动作:开商店
func _on_dialogue_action(action: String, _data: Dictionary) -> void:
	if _shop_panel == null:
		return
	if action == DialogueRunner.ACTION_SHOP_SELL:
		_dialogue_box.hide_temporarily()
		_shop_panel.open_shop(_talking_npc, ShopPanel.Mode.SELL)
	elif action == DialogueRunner.ACTION_SHOP_BUY:
		_dialogue_box.hide_temporarily()
		_shop_panel.open_shop(_talking_npc, ShopPanel.Mode.BUY)
	elif action == DialogueRunner.ACTION_OPEN_GIFT and _gift_panel != null:
		_dialogue_box.hide_temporarily()
		_gift_panel.open_for(NpcRegistry.get_npc(_talking_npc.id))

func _on_gift_closed() -> void:
	if _dialogue_box != null:
		_dialogue_box.show_again()

func _on_service_gift_requested(npc_data: Dictionary) -> void:
	if _gift_panel == null:
		return
	if _service_panel != null and _service_panel.is_open():
		_service_panel.close_panel()
	_gift_panel.open_for(npc_data, true)

func _on_activity_requested(kind: String) -> void:
	if kind == "fishing" and _fishing_panel != null:
		var season := GameStateManager.state.calendar.get_season()
		var seed := GameStateManager.state.calendar.abs_day() * 997 \
			+ int(GameStateManager.state.clock.minute_of_day)
		_fishing_panel.open_round(seed, season)
	elif kind == "cooking" and _cooking_panel != null:
		_cooking_panel.open_panel()

func _on_service_requested(service_type: String) -> void:
	if _service_panel == null or GameStateManager.dialogue_open:
		return
	_service_panel.open_service(service_type)

func _on_drama_requested() -> void:
	if _drama_panel == null or GameStateManager.input_locked:
		return
	_drama_panel.open_panel()

func _on_quest_board_requested() -> void:
	if _quest_panel == null:
		return
	if _quest_panel.is_open():
		_quest_panel.close_panel()
	else:
		_quest_panel.open_panel()

## 商店收摊:对话还没完,接着聊
func _on_shop_closed() -> void:
	if _dialogue_box != null:
		_dialogue_box.show_again()

## 切换世界场景:只换 World 里的内容,保留 HUD 外壳
func _travel_to(location_id: String) -> void:
	_location_id = location_id
	if world == null:
		return
	if context_label != null:
		context_label.text = ""
	if message_label != null:
		message_label.text = ""
	for child in world.get_children():
		world.remove_child(child)
		child.queue_free()
	var path := SceneRouter.scene_path(location_id)
	if path == "":
		return
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("场景加载失败: %s" % path)
		return
	var scene: Node = packed.instantiate()
	if scene.has_method("setup"):
		scene.setup(location_id, GameStateManager.pending_spawn)
	GameStateManager.pending_spawn = Vector2(-1, -1)
	world.add_child(scene)
	if _music != null:
		var location_map := MapDatabase.get_map(location_id)
		_music.play_ambience(String(location_map.get("ambience", "town")))
	_show_scene_title(location_id)

func _show_scene_title(location_id: String) -> void:
	if scene_title == null:
		return
	scene_title.text = SceneRouter.location_cn(location_id)
	scene_title.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(scene_title, "modulate:a", 1.0, 0.28)
	tween.tween_interval(1.15)
	tween.tween_property(scene_title, "modulate:a", 0.0, 0.55)

## 延迟到本帧末尾再换场景 —— 避免把正在发信号的地点场景当场销毁
func _on_travel_requested(location_id: String) -> void:
	_travel_to.call_deferred(location_id)

func _process(_delta: float) -> void:
	_refresh_hud()
	_refresh_environment()
	if _guide_time_left > 0.0:
		_guide_time_left = maxf(0.0, _guide_time_left - _delta)
		if _guide_time_left <= 0.0:
			_set_guide_visible(false)
	if _message_time_left > 0.0:
		_message_time_left = maxf(0.0, _message_time_left - _delta)
		if _message_time_left <= 0.0:
			_clear_expired_message()
	# 背包内容随时可能被买卖改动,开着的时候每帧刷一次
	if _inventory_panel != null and _inventory_panel.is_open():
		_inventory_panel.refresh()

func _refresh_hud() -> void:
	# 每帧重读:读档会整体替换 GameState,缓存引用会变旧
	_calendar = GameStateManager.state.calendar
	_farm = GameStateManager.state.farm
	var p := GameStateManager.state.player
	var stats := _farm.get_stats()
	var clock := GameStateManager.state.clock
	var weather := GameStateManager.state.weather
	hud_label.text = "%s\n%s" % [_calendar.date_short(),
		"%s · %s · %s" % [SceneRouter.location_cn(_location_id),
			clock.time_string(), WeatherSystem.weather_cn(weather.today)]]
	season_label.text = "金币 %d · 体力 %d/%d\n%s" % [
		p.gold, p.energy, p.max_energy, _countdown_text()]
	season_label.add_theme_color_override("font_color", _countdown_color())
	if almanac_label != null:
		# 顶栏只显示压缩后的状态；该标签仍保留可读文本供存档验收与辅助功能读取。
		almanac_label.text = _countdown_text()
		almanac_label.visible = false
	if stamina_bar != null:
		stamina_bar.max_value = p.max_energy
		stamina_bar.value = p.energy
		stamina_bar.modulate = Color(0.55, 0.9, 0.55) if p.energy > 30 else Color(0.96, 0.56, 0.32)
	tip_label.text = "%s · 明日：%s" % [_brief_almanac_text(),
		WeatherSystem.weather_cn(weather.forecast)]
	key_hint.text = _key_hint_text()
	# 农时摘要放在顶部；底部只保留真正的近距离交互卡。
	# 常驻按键说明会制造视觉噪声，操作提示已经并入靠近目标时的 E/A 文案。
	tip_label.visible = false
	key_hint.visible = false
	if guide_label != null:
		var guide: String = Guidance.guide_text(GameStateManager.state)
		if guide_label.text != guide:
			guide_label.text = guide
		if guide != _last_guide_text:
			_last_guide_text = guide
			_guide_time_left = 8.0
			_set_guide_visible(true)
	if guide_title != null:
		guide_title.text = "今日指引 · %s季第%d天" % [
			GameCalendar.season_cn(_calendar.get_season()), _calendar.get_season_day()]

func _set_guide_visible(value: bool) -> void:
	if guide_label != null:
		guide_label.get_parent().visible = value
	if guide_backdrop != null:
		guide_backdrop.visible = false

func _tilled_count() -> int:
	var count := 0
	if _farm == null:
		return 0
	for plot in _farm.plots:
		if plot != null and plot.state == FarmPlot.State.TILLED:
			count += 1
	return count

## 底部只保留一眼能读懂的农时摘要。完整的播种清单放在农事木牌/指引面板,
## 避免把六种作物名和霜冻说明全部塞进一行。
func _brief_almanac_text() -> String:
	if _calendar == null or _farm == null:
		return ""
	if _calendar.is_winter():
		return "农时：冬歇 · 可深翻积肥"
	var sow_left := FarmAlmanac.sow_window_days_left(_calendar, _farm)
	var frost_left := FarmAlmanac.days_until_frost(_calendar)
	var sow := "已过播种窗" if sow_left < 0 else "播种窗 %d 天" % sow_left
	var frost := "初霜已过" if frost_left <= 0 else "初霜 %d 天" % frost_left
	var tag := "可播种" if sow_left >= 0 else "田间管理"
	return "农时：%s · %s · %s" % [tag, sow, frost]

## 地点场景只负责判定"现在能做什么",这里统一排版显示。
func _on_location_context_changed(message: String, prompt: String, plot_info: String) -> void:
	var lines: Array = []
	if prompt != "":
		lines.append(prompt)
	if plot_info != "":
		lines.append(plot_info)
	if context_label != null:
		context_label.text = "\n".join(lines)
	if message_label != null:
		message_label.text = message
		if message != "":
			_message_time_left = MESSAGE_SECONDS
	var show_card := prompt != "" or plot_info != "" or message != ""
	if bottom_backdrop != null:
		bottom_backdrop.visible = false
	if bottom_box != null:
		bottom_box.visible = show_card
	if key_hint != null:
		key_hint.visible = false
	if context_label != null:
		context_label.visible = prompt != "" or plot_info != ""
	if message_label != null:
		message_label.visible = message != ""

func _clear_expired_message() -> void:
	if message_label != null:
		message_label.text = ""
		message_label.visible = false
	var still_near := context_label != null and context_label.text != ""
	if bottom_backdrop != null:
		bottom_backdrop.visible = false
	if bottom_box != null:
		bottom_box.visible = still_near

## 季节、时段、天气叠成一张环境色罩；只染世界，不染 HUD。
func _refresh_environment() -> void:
	if _environment_tint == null:
		return
	var state := GameStateManager.state
	var color := Color(1.10, 1.08, 1.02)
	match state.calendar.get_season():
		"spring": color *= Color(0.98, 1.04, 0.98)
		"summer": color *= Color(1.04, 1.01, 0.94)
		"autumn": color *= Color(1.04, 0.97, 0.88)
		"winter": color *= Color(0.96, 1.01, 1.08)
	match state.weather.today:
		"drizzle", "rain", "thunderstorm", "rainstorm", "cold_rain":
			color *= Color(0.86, 0.90, 0.98)
		"snow", "first_snow": color *= Color(0.96, 0.99, 1.04)
		"blizzard": color *= Color(0.80, 0.86, 0.98)
		"smog": color *= Color(0.88, 0.86, 0.80)
		"frost_morning": color *= Color(0.94, 0.98, 1.02)
	var phase := state.clock.phase()
	match phase:
		"dawn": color *= Color(1.05, 0.98, 0.92)
		"dusk": color *= Color(1.02, 0.90, 0.80)
		"night": color *= Color(0.82, 0.87, 1.0)
		"late_night": color *= Color(0.70, 0.76, 0.95)
	_environment_tint.color = color
	if _weather_overlay != null:
		var current_map := MapDatabase.get_map(_location_id)
		_weather_overlay.configure(state.calendar.get_season(), state.weather.today,
			phase in ["night", "late_night"], bool(current_map.get("indoor", false)))

## 农时倒计时:播种窗(春播/抢茬复种)+ 初霜,常驻在状态栏
func _countdown_text() -> String:
	var parts: Array = []
	var sow_left := FarmAlmanac.sow_window_days_left(_calendar, _farm)
	if _calendar.is_winter():
		parts.append("冬歇")
	elif sow_left >= 0:
		var window_cn := "复种窗" if _calendar.get_season() == "summer" else "播种窗"
		parts.append("%s %d 天" % [window_cn, sow_left])
	else:
		parts.append("播种窗已过")
	var frost_left := FarmAlmanac.days_until_frost(_calendar)
	if frost_left > 0:
		parts.append("初霜 %d 天" % frost_left)
	else:
		parts.append("初霜已过")
	return " · ".join(parts)

## 倒计时的颜色:窗口快关或临近初霜时变橙,霜期过后转淡蓝
func _countdown_color() -> Color:
	var sow_left := FarmAlmanac.sow_window_days_left(_calendar, _farm)
	var frost_left := FarmAlmanac.days_until_frost(_calendar)
	if (sow_left >= 0 and sow_left <= 15) or (frost_left >= 0 and frost_left <= 30):
		return Color(0.98, 0.62, 0.25)
	if sow_left < 0 and frost_left < 0:
		return Color(0.74, 0.79, 0.86)
	return Color(0.92, 0.89, 0.72)

## 按键提示随地点变化(键鼠 + 手柄都写出来,手柄玩家不用背)
func _key_hint_text() -> String:
	var base := "WASD/左摇杆 移动 · E/A 互动 · TAB/BACK 背包 · ESC/START 暂停"
	if _location_id == "L02":
		return "E/A 睡觉 · TAB/BACK 背包 · ESC/START 暂停"
	if _location_id == "L05":
		return "E/A 寄信与收藏册 · ESC/START 暂停"
	if _location_id == "L03":
		return "走进门 · E/A 和镇民交谈 · ESC/START 暂停"
	if _location_id == "L01":
		return "E/A 自动农作 · J 翻土 K 浇水 L 播种 I 收获"
	if _location_id in ["L09", "L10", "L11"]:
		return "E/A 钓鱼/采集/看戏 · 走进门换地点"
	if _location_id == "L12":
		return "E/A 下矿 · 走进门出洞"
	if _location_id == "L13":
		return "E/A 照料牲口 · 走进门离开"
	if _location_id == "L14":
		return "E/A 捐赠藏品 · 走进门离开"
	return base

func _show_message(text: String) -> void:
	if message_label != null:
		message_label.text = text

func _on_day_started(_day: int) -> void:
	_refresh_hud()
	_guide_time_left = 8.0
	_set_guide_visible(true)
	_show_day_banner()
	var birthday := _birthday_name()
	if birthday != "":
		_show_message("今天是%s的生日。去说句话，或送份合心意的东西吧。" % birthday)

func _show_day_banner() -> void:
	if scene_title == null:
		return
	scene_title.text = "%s · %s" % [_calendar.date_short(),
		WeatherSystem.weather_cn(GameStateManager.state.weather.today)]
	scene_title.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(scene_title, "modulate:a", 1.0, 0.25)
	tween.tween_interval(1.0)
	tween.tween_property(scene_title, "modulate:a", 0.0, 0.5)

func _birthday_name() -> String:
	for data in NpcRegistry.all_npcs():
		if RelationshipSystem.is_birthday(GameStateManager.state, data):
			return String(data.get("name", ""))
	return ""

func _on_season_changed(season: String) -> void:
	message_label.text = "【%s】%s" % [GameCalendar.season_cn(season), GameCalendar.season_desc(season)]
	_refresh_hud()

func _on_player_collapsed() -> void:
	_show_message("你在田埂边熬不住了。再睁眼已是清晨，浑身发沉，今天只剩六成力气。")

func _on_shipping_settled(report: Dictionary) -> void:
	_show_message(String(report.get("message", "运输箱结算了。")))

func _on_livestock_produced(report: Dictionary) -> void:
	_show_message(String(report.get("message", "棚里有新产出。")))
