extends Control
class_name WeatherOverlay

## 屏幕空间四季/天气粒子。只做氛围，不参与碰撞和输入。
## 所有粒子由本地 RNG 生成；参数变化时重建，游戏状态本身不受影响。

const MAX_PARTICLES := 220
const RAIN_WEATHER := ["drizzle", "rain", "thunderstorm", "rainstorm", "cold_rain"]
const SNOW_WEATHER := ["snow", "first_snow", "blizzard"]

var season: String = "spring"
var weather: String = "sunny"
var night: bool = false
var indoor: bool = false

var _particles: Array = []
var _rng := RandomNumberGenerator.new()
var _elapsed := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_rng.seed = 0xB1A2C3
	_seed_particles()

func configure(p_season: String, p_weather: String, p_night: bool = false,
		p_indoor: bool = false) -> void:
	if season == p_season and weather == p_weather and night == p_night \
			and indoor == p_indoor:
		return
	season = p_season
	weather = p_weather
	night = p_night
	indoor = p_indoor
	_seed_particles()
	queue_redraw()

static func particle_kind_for(p_season: String, p_weather: String,
		p_indoor: bool = false) -> String:
	if p_indoor:
		return "dust"
	if p_weather in RAIN_WEATHER:
		return "rain"
	if p_weather in SNOW_WEATHER or p_season == "winter":
		return "snow"
	match p_season:
		"spring": return "petal"
		"summer": return "pollen"
		"autumn": return "leaf"
	return "pollen"

static func particle_count_for(p_season: String, p_weather: String,
		p_indoor: bool = false) -> int:
	if p_indoor:
		return 26
	if p_weather == "blizzard":
		return 190
	if p_weather in RAIN_WEATHER:
		return 150
	if p_weather in SNOW_WEATHER or p_season == "winter":
		return 72
	match p_season:
		"spring": return 40
		"summer": return 34
		"autumn": return 48
	return 34

func particle_count() -> int:
	return _particles.size()

func particle_kind() -> String:
	return particle_kind_for(season, weather)

func _seed_particles() -> void:
	_particles.clear()
	var count := mini(MAX_PARTICLES, particle_count_for(season, weather, indoor))
	var viewport_size := get_viewport_rect().size
	if viewport_size.x < 16.0:
		viewport_size = Vector2(1920, 1080)
	for i in count:
		var particle := {
			"pos": Vector2(_rng.randf_range(0.0, viewport_size.x),
				_rng.randf_range(0.0, viewport_size.y)),
			"speed": _rng.randf_range(24.0, 92.0),
			"size": _rng.randf_range(1.2, 4.2),
			"phase": _rng.randf_range(0.0, TAU),
			"drift": _rng.randf_range(-18.0, 34.0),
			"alpha": _rng.randf_range(0.25, 0.68),
		}
		_particles.append(particle)
	queue_redraw()

func _process(delta: float) -> void:
	if _particles.is_empty():
		return
	_elapsed += delta
	var viewport_size := get_viewport_rect().size
	if viewport_size.x < 16.0:
		viewport_size = Vector2(1920, 1080)
	for i in _particles.size():
		var p: Dictionary = _particles[i]
		var pos: Vector2 = p.get("pos", Vector2.ZERO)
		var speed := float(p.get("speed", 40.0))
		var phase := float(p.get("phase", 0.0))
		match particle_kind():
			"rain":
				pos += Vector2(-speed * 0.42, speed * 1.9) * delta
			"snow":
				pos += Vector2(sin(_elapsed * 1.7 + phase) * 16.0 + speed * 0.12,
					speed) * delta
			"dust":
				pos += Vector2(sin(_elapsed * 0.55 + phase) * 5.0,
					cos(_elapsed * 0.38 + phase) * 4.0 - speed * 0.035) * delta
			"leaf":
				pos += Vector2(cos(_elapsed * 1.2 + phase) * 42.0 + speed * 0.30,
					speed * 0.52) * delta
			_:
				pos += Vector2(sin(_elapsed * 0.9 + phase) * 22.0 + speed * 0.10,
					-speed * 0.16) * delta
		if pos.y > viewport_size.y + 24.0:
			pos.y = -24.0
			pos.x = _rng.randf_range(0.0, viewport_size.x)
		elif pos.y < -40.0:
			pos.y = viewport_size.y + 20.0
		if pos.x > viewport_size.x + 40.0:
			pos.x = -30.0
		elif pos.x < -50.0:
			pos.x = viewport_size.x + 20.0
		p["pos"] = pos
		_particles[i] = p
	queue_redraw()

func _draw() -> void:
	var kind := particle_kind()
	for raw in _particles:
		var p: Dictionary = raw
		var pos: Vector2 = p.get("pos", Vector2.ZERO)
		var size := float(p.get("size", 2.0))
		var alpha := float(p.get("alpha", 0.4))
		match kind:
			"rain":
				var color := Color(0.66, 0.77, 0.85, alpha * 0.82)
				draw_line(pos, pos + Vector2(-5.0, 22.0), color, 1.1)
			"snow":
				draw_circle(pos, size, Color(0.96, 0.98, 1.0, alpha))
			"petal":
				draw_set_transform(pos, float(p.get("phase", 0.0)) + _elapsed * 0.4,
					Vector2(1.0, 0.38))
				draw_circle(Vector2.ZERO, size * 1.35, Color(0.96, 0.82, 0.86, alpha))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"leaf":
				draw_set_transform(pos, float(p.get("phase", 0.0)) + _elapsed * 0.7,
					Vector2(1.0, 0.42))
				draw_circle(Vector2.ZERO, size * 1.55, Color(0.82, 0.43, 0.17, alpha))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"dust":
				draw_circle(pos, size * 0.42, Color(0.96, 0.82, 0.52, alpha * 0.52))
			_:
				draw_circle(pos, size * 0.62, Color(0.96, 0.87, 0.45, alpha * 0.74))
