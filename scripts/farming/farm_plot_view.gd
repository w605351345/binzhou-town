extends Node2D
class_name FarmPlotView
## 地块的可视化节点:根据 FarmPlot 的状态画不同颜色与标记。
##
## 颜色是"读表即懂"的:黑土深褐 → 已翻松的浅土 → 出苗绿 → 成熟黄 → 冻死灰。
## 这样即使没有美术资源,玩家也能一眼看出每块地的状态。
##
## 地块下方再挂一行农时角标:还几天熟 / 可收获 / 霜冻警告 / 秋翻 +15%。

const SIZE := Vector2(96, 96)
## 角标文字的尺寸(地块在农场里间隔 164px,超过就会串到邻块)
const BADGE_WIDTH := 150.0
const BADGE_FONT_SIZE := 13

var plot: FarmPlot = null
var calendar: GameCalendar = null
var _highlight := false

func setup(p_plot: FarmPlot, p_calendar: GameCalendar = null) -> void:
	plot = p_plot
	calendar = p_calendar
	queue_redraw()

func set_highlight(on: bool) -> void:
	if _highlight == on:
		return
	_highlight = on
	queue_redraw()

func _draw() -> void:
	if plot == null:
		return
	var rect := Rect2(-SIZE * 0.5, SIZE)
	var base := _state_color()
	draw_rect(rect, base, true)
	draw_rect(rect, Color(0.16, 0.12, 0.09, 0.9), false, 3.0)

	# 耕地纹理:横向犁沟
	if plot.state == FarmPlot.State.TILLED or plot.state == FarmPlot.State.PLANTED \
			or plot.state == FarmPlot.State.GROWING:
		for i in 3:
			var y := -SIZE.y * 0.5 + 22 + i * 26
			draw_line(Vector2(-SIZE.x * 0.5 + 8, y), Vector2(SIZE.x * 0.5 - 8, y),
				Color(0.22, 0.16, 0.12, 0.55), 2.0)

	# 秋翻地标记:犁沟加深 + 深色角标
	if plot.autumn_plowed:
		draw_rect(Rect2(-SIZE * 0.5, SIZE), Color(0.10, 0.07, 0.05, 0.28), true)
		draw_circle(Vector2(SIZE.x * 0.5 - 14, -SIZE.y * 0.5 + 14), 7,
			Color(0.55, 0.42, 0.25, 0.95))

	# 作物标记
	match plot.state:
		FarmPlot.State.PLANTED:
			_draw_sprout(Color(0.45, 0.62, 0.30))
		FarmPlot.State.GROWING:
			_draw_sprout(Color(0.36, 0.56, 0.24))
		FarmPlot.State.READY:
			_draw_ready()
		FarmPlot.State.DEAD:
			_draw_dead()

	if _highlight:
		draw_rect(rect.grow(3.0), Color(1.0, 0.95, 0.75, 0.9), false, 3.0)

	_draw_badge()

## 地块角标:还几天熟 / 可收获 / 霜冻警告 / 秋翻加成
func _draw_badge() -> void:
	var badge := FarmAlmanac.plot_badge(plot, calendar)
	if badge == "":
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var top := SIZE.y * 0.5 + 2.0
	draw_rect(Rect2(Vector2(-BADGE_WIDTH * 0.5, top), Vector2(BADGE_WIDTH, 18.0)),
		Color(0.11, 0.08, 0.06, 0.62), true)
	draw_string(font, Vector2(-BADGE_WIDTH * 0.5, top + 14.0), badge,
		HORIZONTAL_ALIGNMENT_CENTER, BADGE_WIDTH, BADGE_FONT_SIZE, _badge_color())

## 角标配色:熟了用亮黄,枯死用暗红,其余米白
func _badge_color() -> Color:
	match plot.state:
		FarmPlot.State.READY:
			return Color(1.0, 0.88, 0.42)
		FarmPlot.State.DEAD:
			return Color(0.85, 0.45, 0.42)
	return Color(0.93, 0.90, 0.78)

## 状态底色
func _state_color() -> Color:
	match plot.state:
		FarmPlot.State.UNTILLED:
			return Color(0.42, 0.45, 0.30)   # 荒草
		FarmPlot.State.TILLED:
			return Color(0.33, 0.24, 0.17)   # 翻松的黑土
		FarmPlot.State.PLANTED:
			return Color(0.31, 0.22, 0.16)
		FarmPlot.State.GROWING:
			return Color(0.29, 0.21, 0.15)
		FarmPlot.State.READY:
			return Color(0.35, 0.26, 0.17)
		FarmPlot.State.DEAD:
			return Color(0.30, 0.27, 0.24)   # 枯灰
		FarmPlot.State.FALLOW:
			return Color(0.38, 0.30, 0.22)   # 休耕
	return Color(0.3, 0.25, 0.2)

func _draw_sprout(color: Color) -> void:
	var stage := plot.get_growth_stage()
	var h := 14.0 + float(stage) * 9.0
	draw_line(Vector2(0, 20), Vector2(0, 20 - h), color, 4.0)
	draw_circle(Vector2(-7, 20 - h), 5.0, color)
	draw_circle(Vector2(7, 20 - h), 5.0, color)

func _draw_ready() -> void:
	var crop := CropDatabase.get_crop(plot.crop_id)
	var color := Color(0.92, 0.76, 0.28)
	if crop != null and crop.category == "vegetable":
		color = Color(0.72, 0.85, 0.40)
	draw_circle(Vector2(0, 6), 20.0, color)
	draw_circle(Vector2(-9, 14), 13.0, color)
	draw_circle(Vector2(9, 14), 13.0, color)
	# 成熟提示环
	draw_arc(Vector2(0, 4), 30.0, 0.0, TAU, 32, Color(1.0, 0.92, 0.55, 0.85), 3.0)

func _draw_dead() -> void:
	# 枯株:歪倒的褐色枝
	draw_line(Vector2(-10, 26), Vector2(4, 2), Color(0.45, 0.36, 0.22), 4.0)
	draw_line(Vector2(10, 26), Vector2(-2, 4), Color(0.45, 0.36, 0.22), 4.0)
	draw_line(Vector2(-10, 26), Vector2(10, 26), Color(0.40, 0.32, 0.20), 3.0)
