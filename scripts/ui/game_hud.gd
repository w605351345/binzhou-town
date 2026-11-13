extends Node2D
## 游戏外壳:常驻 HUD(日期/金币/体力/农时倒计时)+ 世界场景容器。
##
## 黑龙江设定:春播秋收,冬季休耕时显示提示。
## HUD 常驻"当前可播种"与"秋霜倒计时" —— 这是风险 R2/R3 的对策,
## 让玩家一眼看出"现在该干嘛"。
##
## 世界场景(自家院 / 镇大街)装在 World 节点里,换地点时只换世界不换 HUD,
## 这样走到哪儿都看得见日期、体力和农时提示。

const START_LOCATION := "L01"

@onready var world: Node2D = $World
@onready var hud_label: Label = $HUD/HBox/HudLabel
@onready var season_label: Label = $HUD/HBox/SeasonLabel
@onready var almanac_label: Label = $HUD/HBox/AlmanacLabel
@onready var message_label: Label = $MessageLabel
@onready var tip_label: Label = $TipLabel
@onready var key_hint: Label = $KeyHint

var _calendar: GameCalendar
var _farm: FarmSystem
var _location_id: String = ""

## 对话框与商店面板:常驻在游戏外壳里(和 HUD 一样不随地点销毁)
var _dialogue_box: DialogueBox = null
var _shop_panel: ShopPanel = null
var _inventory_panel: InventoryPanel = null
## 当前对话的 NPC(好感度要写回存档)
var _talking_npc: NpcBase = null

func _ready() -> void:
	_calendar = GameStateManager.state.calendar
	_farm = GameStateManager.state.farm
	_build_overlays()
	_refresh_hud()
	GameStateManager.day_started.connect(_on_day_started)
	GameStateManager.season_changed.connect(_on_season_changed)
	GameStateManager.travel_requested.connect(_on_travel_requested)
	GameStateManager.dialogue_requested.connect(_on_dialogue_requested)
	_travel_to(START_LOCATION)

## 建对话/商店两个覆盖层(代码构建,不用改 .tscn)
func _build_overlays() -> void:
	_dialogue_box = DialogueBox.new()
	_dialogue_box.name = "DialogueBox"
	_dialogue_box.closed.connect(_on_dialogue_closed)
	_dialogue_box.action_triggered.connect(_on_dialogue_action)
	add_child(_dialogue_box)

	_shop_panel = ShopPanel.new()
	_shop_panel.name = "ShopPanel"
	_shop_panel.closed.connect(_on_shop_closed)
	add_child(_shop_panel)

	_inventory_panel = InventoryPanel.new()
	_inventory_panel.name = "InventoryPanel"
	add_child(_inventory_panel)

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

## 地点场景判定可交互后发出对话请求 —— 这里负责把对话跑起来
func _on_dialogue_requested(npc: NpcBase) -> void:
	if _dialogue_box == null or npc == null:
		return
	var dialogue := DialogueData.dialogue_for_npc(npc.id)
	if dialogue.is_empty():
		_show_message("%s这会儿没什么想说的。" % npc.name)
		return
	_talking_npc = npc
	var runner := DialogueRunner.new()
	# flags 传的是 GameState 里的同一个字典 —— 对话里写的标记直接进存档
	runner.setup(dialogue.get("lines", []), GameStateManager.state.player,
		GameStateManager.state.calendar, npc, GameStateManager.state.flags)
	runner.start()
	_dialogue_box.setup(npc, runner)
	_dialogue_box.open()
	GameStateManager.set_dialogue_open(true)

## 对话结束:好感度写回存档(下次进镇大街还在)
func _on_dialogue_closed() -> void:
	if _talking_npc != null:
		GameStateManager.state.set_npc_affection(_talking_npc.id, _talking_npc.affection)
	_talking_npc = null
	GameStateManager.set_dialogue_open(false)

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

## 商店收摊:对话还没完,接着聊
func _on_shop_closed() -> void:
	if _dialogue_box != null:
		_dialogue_box.show_again()

## 切换世界场景:只换 World 里的内容,保留 HUD 外壳
func _travel_to(location_id: String) -> void:
	_location_id = location_id
	if world == null:
		return
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
	world.add_child(packed.instantiate())

## 延迟到本帧末尾再换场景 —— 避免把正在发信号的地点场景当场销毁
func _on_travel_requested(location_id: String) -> void:
	_travel_to.call_deferred(location_id)

func _process(_delta: float) -> void:
	_refresh_hud()
	# 背包内容随时可能被买卖改动,开着的时候每帧刷一次
	if _inventory_panel != null and _inventory_panel.is_open():
		_inventory_panel.refresh()

func _refresh_hud() -> void:
	# 每帧重读:读档会整体替换 GameState,缓存引用会变旧
	_calendar = GameStateManager.state.calendar
	_farm = GameStateManager.state.farm
	var p := GameStateManager.state.player
	var stats := _farm.get_stats()
	hud_label.text = "第%d年 %d月%d日  %s | 金币 %d | 体力 %d/%d | 已种 %d 可收 %d" % [
		_calendar.year, _calendar.get_real_month(), _calendar.get_day_of_month(),
		GameCalendar.season_cn(_calendar.get_season()),
		p.gold, p.energy, p.max_energy,
		stats.get("planted", 0), stats.get("ready", 0),
	]
	season_label.text = GameCalendar.season_desc(_calendar.get_season())
	almanac_label.text = _countdown_text()
	almanac_label.add_theme_color_override("font_color", _countdown_color())
	tip_label.text = FarmAlmanac.full_tip(_calendar, _farm)
	key_hint.text = _key_hint_text()

## 农时倒计时:播种窗(春播/抢茬复种)+ 秋霜,常驻在状态栏
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
		parts.append("秋霜 %d 天" % frost_left)
	else:
		parts.append("秋霜已过")
	return " · ".join(parts)

## 倒计时的颜色:窗口快关或临近秋霜时变橙,霜期过后转淡蓝
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
	var base := "WASD/左摇杆 移动 · E/A 对话 · T/左摇杆 睡觉 · TAB/BACK 背包 · ESC/START 暂停"
	if _location_id == "L02":
		return base + " · F/右摇杆 回自家院"
	if _location_id == "L01":
		return base + " · J/X 翻土 · K/Y 浇水 · L/LB 播种 · I/RB 收获 · R/BACK 秋翻 · F/右摇杆 去镇大街"
	return base

func _show_message(text: String) -> void:
	if message_label != null:
		message_label.text = text

func _on_day_started(_day: int) -> void:
	_refresh_hud()

func _on_season_changed(season: String) -> void:
	message_label.text = "【%s】%s" % [GameCalendar.season_cn(season), GameCalendar.season_desc(season)]
	_refresh_hud()
