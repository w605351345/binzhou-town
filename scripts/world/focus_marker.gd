extends Node2D
class_name FocusMarker

const DEFAULT_COLOR := Color(1.0, 0.91, 0.54, 0.94)
const DOOR_COLOR := Color(0.64, 0.91, 0.78, 0.94)

var _target := Vector2.INF
var _kind := ""
var _elapsed := 0.0

func _ready() -> void:
	z_index = 30
	set_process(false)

func set_target(target: Vector2, kind: String = "") -> void:
	if _target.distance_squared_to(target) < 0.01 and _kind == kind:
		return
	_target = target
	_kind = kind
	_elapsed = 0.0
	set_process(target.x != INF)
	queue_redraw()

func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()

func _draw() -> void:
	if _target.x == INF:
		return
	var bob := sin(_elapsed * 4.2) * 3.0
	var point := _target + Vector2(0.0, -34.0 + bob)
	var color := DOOR_COLOR if _kind == "door" else DEFAULT_COLOR
	draw_circle(point, 6.0, Color(0.12, 0.09, 0.06, 0.55))
	draw_circle(point, 4.0, color)
	var diamond := PackedVector2Array([
		point + Vector2(0, 9), point + Vector2(7, 0),
		point + Vector2(0, -9), point + Vector2(-7, 0),
	])
	draw_colored_polygon(diamond, color)
