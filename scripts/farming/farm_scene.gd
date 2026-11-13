extends Node2D
## 黑土地农场场景(L01):3×3 地块 + 主角 + 工具操作。
##
## 黑龙江设定:自家院的三块地,九块格子。春播秋收,冬季休耕。

const PLOT_SIZE := 140.0
const PLOT_GAP := 24.0

@onready var plot_container: Node2D = $PlotContainer
@onready var player: CharacterBody2D = $Player
@onready var message_label: Label = $HUD/MessageLabel
@onready var plot_info_label: Label = $HUD/PlotInfoLabel

var _views: Array = []
var _selected_crop: String = ""

func _ready() -> void:
	var farm: FarmSystem = GameStateManager.state.farm
	_build_plots(farm)
	_refresh_views()
	GameStateManager.day_started.connect(_on_day_started)

func _process(_delta: float) -> void:
	_refresh_plot_info()

func _build_plots(farm: FarmSystem) -> void:
	_views.clear()
	var cols := 3
	var rows := 3
	var total_w := float(cols) * PLOT_SIZE + float(cols - 1) * PLOT_GAP
	var total_h := float(rows) * PLOT_SIZE + float(rows - 1) * PLOT_GAP
	var origin := Vector2(-total_w * 0.5, -total_h * 0.5) + Vector2(0, 120)
	for i in farm.plots.size():
		var col := i % cols
		var row := i / cols
		var view := FarmPlotView.new()
		view.position = origin + Vector2(
			float(col) * (PLOT_SIZE + PLOT_GAP),
			float(row) * (PLOT_SIZE + PLOT_GAP))
		view.setup(farm.get_plot(i), farm.calendar)
		plot_container.add_child(view)
		_views.append(view)

func _refresh_views() -> void:
	for v in _views:
		if v is FarmPlotView:
			v.queue_redraw()

## 找到主角附近的地块索引(-1 表示没有)
func _plot_near_player() -> int:
	var farm: FarmSystem = GameStateManager.state.farm
	var best := -1
	var best_dist := 130.0
	for i in farm.plots.size():
		var view := _views[i] as FarmPlotView
		var d := view.global_position.distance_to(player.global_position)
		if d < best_dist:
			best_dist = d
			best = i
	return best

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("tool_till"):
		_use_tool(ToolBar.Tool.TILL)
	elif event.is_action_pressed("tool_water"):
		_use_tool(ToolBar.Tool.WATER)
	elif event.is_action_pressed("tool_seed"):
		_use_tool(ToolBar.Tool.SEED)
	elif event.is_action_pressed("tool_harvest"):
		_use_tool(ToolBar.Tool.HARVEST)
	elif event.is_action_pressed("tool_plough"):
		_use_autumn_plough()
	elif event.is_action_pressed("travel"):
		_go_to_town()
	elif event.is_action_pressed("sleep"):
		_sleep_one_day()

func _use_tool(tool: int) -> void:
	var farm: FarmSystem = GameStateManager.state.farm
	var idx := _plot_near_player()
	if idx < 0:
		_show_message("走近一块地再动手")
		return
	var player_state: PlayerProfile = GameStateManager.state.player
	var res := ToolBar.apply_tool(tool, farm, idx, player_state, _selected_crop)
	_show_message(String(res.get("message", "")))
	_refresh_views()
	_refresh_highlight(idx)

func _use_autumn_plough() -> void:
	var farm: FarmSystem = GameStateManager.state.farm
	var idx := _plot_near_player()
	if idx < 0:
		_show_message("走近一块地再动手")
		return
	var player_state: PlayerProfile = GameStateManager.state.player
	var res := ToolBar.apply_autumn_plough(farm, idx, player_state)
	_show_message(String(res.get("message", "")))
	_refresh_views()

func _refresh_highlight(idx: int) -> void:
	for i in _views.size():
		var v := _views[i] as FarmPlotView
		if v != null:
			v.set_highlight(i == idx)

func _show_message(text: String) -> void:
	if message_label != null:
		message_label.text = text

## 睡一觉,推进一天(农时推进的主动入口)
func _sleep_one_day() -> void:
	GameStateManager.advance_day()
	_show_message("一觉到天亮 · %s" % GameStateManager.state.calendar.date_string())
	_refresh_views()

## 走进镇大街(Week 2:场景之间的流动)
func _go_to_town() -> void:
	if not SceneRouter.is_implemented("L02"):
		return
	GameStateManager.travel_requested.emit("L02")

## 主角脚边这块地的农时状态(还几天熟、几天内必割、秋翻加成)
func _refresh_plot_info() -> void:
	if plot_info_label == null:
		return
	var farm: FarmSystem = GameStateManager.state.farm
	var idx := _plot_near_player()
	if idx < 0:
		_set_plot_info("")
		return
	var tag := FarmAlmanac.plot_tag(farm.get_plot(idx), farm.calendar)
	_set_plot_info("【%d 号地】%s" % [idx + 1, tag])

func _set_plot_info(text: String) -> void:
	if plot_info_label != null and plot_info_label.text != text:
		plot_info_label.text = text

func _on_day_started(_day: int) -> void:
	_refresh_views()
