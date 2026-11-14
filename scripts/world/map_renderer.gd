extends Node2D
class_name MapRenderer

## 数据驱动地图渲染。地图逻辑只认 maps.json，这里负责把地形与地标画出来：
## 四季地面贴图平铺、地点道具贴图替换色块，缺图时仍保留程序化回退。

const INK := Color(0.12, 0.09, 0.07)
const DEFAULT_SEASON := "spring"
const SEASONS := ["spring", "summer", "autumn", "winter"]
const TERRAIN_DIR := "res://assets/art/generated/terrain"
const PROP_DIR := "res://assets/art/generated/props"
const OUTDOOR_DETAIL_TERRAIN := [
	"grass", "grass_dark", "moss", "dirt", "soil", "road", "plaza", "sand",
]
const TILED_PROPS := ["fence"]
const COLORS := {
	"grass": Color(0.34, 0.39, 0.20),
	"grass_dark": Color(0.22, 0.29, 0.17),
	"moss": Color(0.28, 0.39, 0.20),
	"dirt": Color(0.42, 0.33, 0.23),
	"soil": Color(0.33, 0.23, 0.15),
	"road": Color(0.50, 0.40, 0.28),
	"plaza": Color(0.55, 0.47, 0.34),
	"sand": Color(0.65, 0.53, 0.32),
	"water": Color(0.24, 0.43, 0.54),
	"wall": Color(0.34, 0.27, 0.20),
	"floor_wood": Color(0.47, 0.34, 0.22),
	"floor_tile": Color(0.58, 0.55, 0.47),
	"rug": Color(0.46, 0.18, 0.18),
	"stage_floor": Color(0.55, 0.36, 0.21),
}

var map: Dictionary = {}
var season: String = DEFAULT_SEASON

var _terrain_cache: Dictionary = {}
var _prop_cache: Dictionary = {}
var _prop_region_cache: Dictionary = {}

## 等比放进目标矩形：以内容真实宽高为准，底部贴地、水平居中。
## 地图数据只需要给出占地范围，不再让长椅/树/建筑被任意拉伸。
static func aspect_fit_rect(target: Rect2, content_size: Vector2) -> Rect2:
	if content_size.x <= 0.0 or content_size.y <= 0.0:
		return target
	var scale := minf(target.size.x / content_size.x, target.size.y / content_size.y)
	var draw_size := content_size * scale
	return Rect2(Vector2(target.get_center().x - draw_size.x * 0.5,
		target.end.y - draw_size.y), draw_size)

## 室内保留轻微收边；室外交给不规则边缘过渡，避免整块矩形边界。
static func terrain_border_width(_kind: String, indoor: bool) -> float:
	return 3.0 if indoor else 0.0

static func should_tile_prop(kind: String) -> bool:
	return kind in TILED_PROPS

static func needs_winter_roof_cap(kind: String, p_season: String) -> bool:
	return p_season == "winter" and kind in [
		"house", "building", "barn", "backstage", "stall",
	]

## 美术测试与资源检查共用这一套命名，避免渲染器和生成器各写一份路径。
static func terrain_texture_path(p_season: String, terrain: String) -> String:
	var safe_season := p_season if p_season in SEASONS else DEFAULT_SEASON
	return "%s/%s_%s.png" % [TERRAIN_DIR, safe_season, terrain]

static func prop_texture_path(prop_type: String) -> String:
	return "%s/%s.png" % [PROP_DIR, prop_type]

func setup(p_map: Dictionary, p_season: String = DEFAULT_SEASON) -> void:
	map = p_map
	season = p_season if p_season in SEASONS else DEFAULT_SEASON
	queue_redraw()

## 换季时只换材质，不重建玩家、NPC 或地图碰撞。
func set_season(p_season: String) -> void:
	var next := p_season if p_season in SEASONS else DEFAULT_SEASON
	if next == season:
		return
	season = next
	_terrain_cache.clear()
	_prop_region_cache.clear()
	queue_redraw()

func _draw() -> void:
	if map.is_empty():
		return
	var size := MapDatabase.map_size(map)
	draw_rect(Rect2(Vector2.ZERO, Vector2(size)), Color(0.12, 0.14, 0.10))
	for layer in map.get("terrain", []):
		_draw_terrain(layer)
	_draw_ground_details()
	_draw_texture_lines(size)
	var props: Array = map.get("props", []).duplicate()
	props.sort_custom(_prop_draw_before)
	for prop in props:
		_draw_prop(prop)
	for door in map.get("doors", []):
		_draw_door(door)
	for item in map.get("interactables", []):
		_draw_interactable(item)
	if map.has("farm_area"):
		_draw_farm_area(map["farm_area"])

## 可复现的地面细节层。地图数据负责大结构，这里负责草叶、碎石、落叶、雪堆等
## 低尺度笔触，避免大片贴图重复后显得空。测试也直接检查这一份规格。
func ground_detail_specs() -> Array:
	if map.is_empty():
		return []
	var size := MapDatabase.map_size(map)
	var indoor := bool(map.get("indoor", false))
	var area := maxi(1, size.x * size.y)
	var count := clampi(int(area / (7000 if indoor else 18000)), 24, 320)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(String(map.get("id", "")).hash()) ^ int(season.hash()) ^ 0x5A17
	var out: Array = []
	for _i in count:
		var pos := Vector2(rng.randf_range(20.0, size.x - 20.0),
			rng.randf_range(20.0, size.y - 20.0))
		var terrain := terrain_at(pos)
		if indoor:
			out.append({
				"kind": ["dust", "scuff", "crumb"][_i % 3],
				"pos": pos,
				"scale": rng.randf_range(0.6, 1.25),
				"variant": rng.randi_range(0, 9999),
			})
			continue
		if not OUTDOOR_DETAIL_TERRAIN.has(terrain):
			continue
		var kind := _detail_kind_for(terrain, rng)
		out.append({
			"kind": kind,
			"pos": pos,
			"scale": rng.randf_range(0.65, 1.45),
			"variant": rng.randi_range(0, 9999),
			"terrain": terrain,
		})
	return out

func terrain_at(point: Vector2) -> String:
	var found := "grass"
	for layer in map.get("terrain", []):
		if MapDatabase.rect_from_array(layer.get("rect", [])).has_point(point):
			found = String(layer.get("type", "grass"))
	return found

func _detail_kind_for(terrain: String, rng: RandomNumberGenerator) -> String:
	if terrain in ["road", "plaza"]:
		if season == "winter":
			return "ice_crack" if rng.randf() < 0.42 else "snow_lump"
		if season == "spring" and rng.randf() < 0.45:
			return "puddle"
		return "stone" if rng.randf() < 0.58 else "scuff"
	if terrain in ["dirt", "soil"]:
		if season == "winter":
			return "snow_lump" if rng.randf() < 0.62 else "twig"
		if season == "spring" and rng.randf() < 0.24:
			return "puddle"
		return "stone" if rng.randf() < 0.58 else "tuft"
	if season == "winter":
		return "snow_lump" if rng.randf() < 0.68 else "twig"
	if season == "autumn":
		return "leaf" if rng.randf() < 0.58 else "tuft_dry"
	if season == "summer":
		return "flower" if rng.randf() < 0.28 else "tuft"
	return "flower" if rng.randf() < 0.22 else ("tuft" if rng.randf() < 0.72 else "stone")

func _draw_ground_details() -> void:
	for spec in ground_detail_specs():
		_draw_ground_detail(spec)

func _draw_ground_detail(spec: Dictionary) -> void:
	var pos: Vector2 = spec.get("pos", Vector2.ZERO)
	var scale := float(spec.get("scale", 1.0))
	var variant := int(spec.get("variant", 0))
	var kind := String(spec.get("kind", "tuft"))
	match kind:
		"tuft", "tuft_dry":
			var dry := kind == "tuft_dry"
			var hi := Color(0.72, 0.72, 0.43, 0.66) if dry else Color(0.69, 0.78, 0.46, 0.64)
			var lo := Color(0.34, 0.29, 0.18, 0.68) if dry else Color(0.23, 0.34, 0.19, 0.70)
			for i in 3:
				var lean := (float((variant + i * 37) % 11) - 5.0) * 0.7
				var height := (7.0 + float((variant + i * 13) % 9)) * scale
				var base := pos + Vector2((i - 1) * 2.2 * scale, 0.0)
				draw_line(base, base + Vector2(lean, -height), lo, 2.0 * scale)
				draw_line(base + Vector2(1, 0), base + Vector2(lean + 0.7, -height * 0.74),
					hi, 1.0 * scale)
		"flower":
			var stem := Color(0.27, 0.37, 0.19, 0.76)
			var petal := Color(0.92, 0.83, 0.47, 0.88) if variant % 3 else \
				Color(0.82, 0.62, 0.66, 0.88)
			var top := pos + Vector2(0, -9.0 * scale)
			draw_line(pos, top, stem, 1.4 * scale)
			for i in 5:
				var angle := TAU * float(i) / 5.0 + float(variant % 17) * 0.1
				draw_circle(top + Vector2(cos(angle), sin(angle)) * 2.1 * scale,
					1.4 * scale, petal)
			draw_circle(top, 1.2 * scale, Color(0.64, 0.38, 0.17, 0.9))
		"leaf":
			var leaf_color := Color(0.74, 0.38, 0.15, 0.76) if variant % 2 else \
				Color(0.56, 0.29, 0.14, 0.74)
			draw_set_transform(pos + Vector2(0, -2), float(variant % 31) * 0.2,
				Vector2(1.0, 0.38))
			draw_circle(Vector2.ZERO, 4.3 * scale, leaf_color)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"stone":
			var stone := Color(0.43, 0.43, 0.37, 0.55)
			draw_set_transform(pos, 0.0, Vector2(1.0, 0.48))
			draw_circle(Vector2.ZERO, 3.7 * scale, stone)
			draw_arc(Vector2.ZERO, 3.7 * scale, 0, TAU, 12,
				Color(0.12, 0.10, 0.08, 0.42), 1.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"puddle":
			draw_set_transform(pos, 0.0, Vector2(1.0, 0.32))
			draw_circle(Vector2.ZERO, 11.0 * scale, Color(0.25, 0.37, 0.42, 0.34))
			draw_circle(Vector2(-2, -1), 5.5 * scale, Color(0.62, 0.73, 0.75, 0.22))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"snow_lump":
			draw_set_transform(pos, 0.0, Vector2(1.0, 0.34))
			draw_circle(Vector2.ZERO, 9.0 * scale, Color(0.91, 0.95, 0.95, 0.54))
			draw_circle(Vector2(-3, -2), 5.0 * scale, Color(0.98, 0.99, 0.98, 0.45))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"twig":
			draw_line(pos, pos + Vector2(8, -3) * scale,
				Color(0.22, 0.18, 0.14, 0.67), 1.5)
			draw_line(pos + Vector2(3, -1) * scale, pos + Vector2(5, -7) * scale,
				Color(0.22, 0.18, 0.14, 0.62), 1.2)
		"ice_crack":
			var start := pos + Vector2(-7, -2) * scale
			draw_line(start, start + Vector2(5, 2) * scale,
				Color(0.67, 0.80, 0.84, 0.62), 1.3)
			draw_line(start + Vector2(5, 2) * scale, start + Vector2(8, 6) * scale,
				Color(0.67, 0.80, 0.84, 0.52), 1.0)
		"scuff":
			draw_line(pos, pos + Vector2(7, 2) * scale,
				Color(0.16, 0.13, 0.10, 0.18), 1.4)
		"dust":
			draw_circle(pos, 1.2 * scale, Color(0.20, 0.16, 0.12, 0.13))
		"crumb":
			draw_circle(pos, 1.8 * scale, Color(0.44, 0.32, 0.20, 0.18))

func _draw_terrain(layer: Dictionary) -> void:
	var rect := MapDatabase.rect_from_array(layer.get("rect", []))
	if rect.size == Vector2.ZERO:
		return
	var kind := String(layer.get("type", "grass"))
	var texture := _terrain_texture(kind)
	if texture != null:
		draw_texture_rect(texture, rect, true)
	else:
		var color: Color = COLORS.get(kind, COLORS["grass"])
		draw_rect(rect, color)
	var border := terrain_border_width(kind, bool(map.get("indoor", false)))
	if border > 0.0:
		draw_rect(rect, _season_edge_color(kind), false, border)
	else:
		_draw_terrain_fringe(rect, kind)
	if kind == "water":
		var y := rect.position.y + 24.0
		while y < rect.end.y:
			draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y),
				Color(0.76, 0.90, 0.92, 0.28), 2.0)
			y += 34.0
	elif kind in ["grass", "grass_dark", "moss"]:
		_draw_grass_marks(rect)

## 用沿边散布的扁圆把整块地形“啃”出有机边缘。确定性种子保证读档/截图稳定。
func _draw_terrain_fringe(rect: Rect2, kind: String) -> void:
	if rect.size.x < 80.0 or rect.size.y < 80.0:
		return
	var base: Color = COLORS.get(kind, COLORS["grass"])
	match season:
		"summer": base = base.lerp(Color(0.82, 0.90, 0.52), 0.12)
		"autumn": base = base.lerp(Color(0.92, 0.68, 0.35), 0.16)
		"winter": base = base.lerp(Color(0.80, 0.88, 0.91), 0.24)
		_: base = base.lerp(Color(0.76, 0.86, 0.55), 0.10)
	base.a = 0.34 if kind != "water" else 0.26
	var rng := RandomNumberGenerator.new()
	rng.seed = int(String(map.get("id", "")).hash()) ^ int(kind.hash()) \
		^ int(rect.position.x) * 31 ^ int(rect.size.y) * 17 ^ 0xB17
	var step := 22.0
	for x in range(int(rect.position.x), int(rect.end.x) + 1, int(step)):
		_fringe_blob(Vector2(float(x) + rng.randf_range(-5.0, 5.0), rect.position.y),
			rng.randf_range(8.0, 19.0), base, rng, true)
		_fringe_blob(Vector2(float(x) + rng.randf_range(-5.0, 5.0), rect.end.y),
			rng.randf_range(8.0, 19.0), base, rng, true)
	for y in range(int(rect.position.y), int(rect.end.y) + 1, int(step)):
		_fringe_blob(Vector2(rect.position.x, float(y) + rng.randf_range(-5.0, 5.0)),
			rng.randf_range(8.0, 19.0), base, rng, false)
		_fringe_blob(Vector2(rect.end.x, float(y) + rng.randf_range(-5.0, 5.0)),
			rng.randf_range(8.0, 19.0), base, rng, false)

func _fringe_blob(pos: Vector2, radius: float, color: Color,
		rng: RandomNumberGenerator, horizontal: bool) -> void:
	var stretch := Vector2(1.0, 0.48) if horizontal else Vector2(0.48, 1.0)
	var offset := Vector2(0.0, rng.randf_range(-6.0, 6.0)) if horizontal \
		else Vector2(rng.randf_range(-6.0, 6.0), 0.0)
	draw_set_transform(pos + offset, 0.0, stretch)
	draw_circle(Vector2.ZERO, radius, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _prop_draw_before(a: Dictionary, b: Dictionary) -> bool:
	return MapDatabase.rect_from_array(a.get("rect", [])).end.y \
		< MapDatabase.rect_from_array(b.get("rect", [])).end.y

func _draw_texture_lines(size: Vector2i) -> void:
	var step := 96
	var dot := Color(0.08, 0.07, 0.05, 0.12)
	var x := 48
	while x < size.x:
		var y := 48
		while y < size.y:
			draw_line(Vector2(x - 8, y), Vector2(x + 8, y + 3), dot, 2.0)
			y += step
		x += step

func _draw_prop(prop: Dictionary) -> void:
	var rect := MapDatabase.rect_from_array(prop.get("rect", []))
	if rect.size == Vector2.ZERO:
		return
	var kind := String(prop.get("type", "prop"))
	_draw_ground_shadow(rect)
	var texture := _prop_texture(kind)
	if texture != null:
		var tint := _prop_season_tint(kind)
		var region := _prop_region(kind, texture)
		if should_tile_prop(kind) and rect.size.x >= rect.size.y * 1.6:
			_draw_tiled_prop(texture, rect, region, tint)
		else:
			var fitted := aspect_fit_rect(rect, region.size)
			draw_texture_rect_region(texture, fitted, region, tint)
			if needs_winter_roof_cap(kind, season):
				_draw_winter_roof_cap(fitted)
		if String(prop.get("label", "")) != "":
			_draw_label(String(prop["label"]), rect.position + Vector2(0, -18), 22)
		return
	# 缺图回退：旧版程序化剪影仍可保证地图完整可玩。
	var body := Color(0.48, 0.36, 0.22)
	match kind:
		"house", "building", "barn":
			body = Color(0.47, 0.31, 0.20)
		"tree", "birch":
			body = Color(0.27, 0.36, 0.18)
		"water", "dock":
			body = Color(0.47, 0.34, 0.20)
		"stage", "backstage":
			body = Color(0.51, 0.25, 0.18)
		"well", "stove":
			body = Color(0.44, 0.45, 0.40)
		"counter", "desk", "table", "workbench", "exam_bed", "bench":
			body = Color(0.52, 0.37, 0.22)
		"shelf", "mailboxes", "medicine_cabinet", "woodpile", "lumber":
			body = Color(0.38, 0.29, 0.19)
		"stall", "board", "sign":
			body = Color(0.58, 0.42, 0.20)
		"mushroom_log", "fallen_log":
			body = Color(0.35, 0.30, 0.20)
		"lantern", "instrument":
			body = Color(0.68, 0.31, 0.16)
	draw_rect(rect, body)
	draw_rect(rect, INK, false, 7.0)
	if kind in ["house", "building", "barn", "backstage"]:
		var roof := PackedVector2Array([
			rect.position + Vector2(-16, 24), rect.position + Vector2(rect.size.x * 0.5, -42),
			rect.position + Vector2(rect.size.x + 16, 24)])
		draw_colored_polygon(roof, Color(0.28, 0.18, 0.13))
		draw_polyline(roof, INK, 7.0)
		draw_rect(Rect2(rect.position + Vector2(rect.size.x * 0.42, rect.size.y * 0.48),
			Vector2(rect.size.x * 0.18, rect.size.y * 0.52)), Color(0.16, 0.11, 0.08))
	if kind in ["tree", "birch"]:
		draw_line(Vector2(rect.position.x + rect.size.x * 0.5, rect.end.y),
			Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y * 0.5),
			Color(0.25, 0.16, 0.10), 16.0)
		draw_circle(Vector2(rect.position.x + rect.size.x * 0.5,
			rect.position.y + rect.size.y * 0.38), rect.size.x * 0.52, body)
		draw_arc(Vector2(rect.position.x + rect.size.x * 0.5,
			rect.position.y + rect.size.y * 0.38), rect.size.x * 0.52, 0, TAU, 32, INK, 6.0)
	if kind == "well":
		draw_circle(rect.get_center(), minf(rect.size.x, rect.size.y) * 0.43,
			Color(0.12, 0.16, 0.18))
		draw_arc(rect.get_center(), minf(rect.size.x, rect.size.y) * 0.43,
			0, TAU, 28, INK, 8.0)
	if String(prop.get("label", "")) != "":
		_draw_label(String(prop["label"]), rect.position + Vector2(0, -18), 22)

func _draw_tiled_prop(texture: Texture2D, rect: Rect2, region: Rect2,
		tint: Color) -> void:
	var source_aspect := region.size.x / maxf(1.0, region.size.y)
	var segment_width := rect.size.y * source_aspect
	if segment_width <= 0.0:
		return
	var step := maxf(12.0, segment_width * 0.82)
	var count := maxi(1, int(ceil(rect.size.x / step)))
	var total_width := segment_width + (count - 1) * step
	var start_x := rect.get_center().x - total_width * 0.5
	for i in count:
		var dest := Rect2(Vector2(start_x + i * step, rect.end.y - rect.size.y),
			Vector2(segment_width, rect.size.y))
		draw_texture_rect_region(texture, dest, region, tint)

func _draw_door(door: Dictionary) -> void:
	var rect := MapDatabase.door_rect(door)
	draw_rect(rect, Color(0.08, 0.07, 0.06, 0.66))
	draw_rect(rect, Color(0.78, 0.65, 0.39), false, 4.0)
	_draw_label(String(door.get("label", "门")), rect.position + Vector2(0, -8), 18)

func _draw_interactable(item: Dictionary) -> void:
	var raw: Array = item.get("pos", [0, 0])
	var pos := Vector2(float(raw[0]), float(raw[1]))
	var radius := float(item.get("radius", 90.0))
	draw_circle(pos, 12.0, Color(0.96, 0.80, 0.36, 0.82))
	draw_arc(pos, 12.0, 0, TAU, 24, INK, 3.0)
	draw_arc(pos, minf(radius * 0.52, 48.0), 0, TAU, 40,
		Color(0.96, 0.80, 0.36, 0.30), 2.0)
	_draw_label(String(item.get("label", "互动")), pos + Vector2(-50, -24), 17)

func _draw_farm_area(area: Dictionary) -> void:
	var origin_raw: Array = area.get("origin", [0, 0])
	var origin := Vector2(float(origin_raw[0]), float(origin_raw[1]))
	var cols := int(area.get("width", 6))
	var rows := int(area.get("height", 4))
	var plot_size := float(area.get("plot_size", 88.0))
	var total := Rect2(origin, Vector2(cols * plot_size, rows * plot_size))
	draw_rect(total, Color(0.04, 0.03, 0.02, 0.10))
	draw_rect(total, Color(0.12, 0.09, 0.07, 0.34), false, 3.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(String(map.get("id", "")).hash()) ^ 0xFA11
	for i in 24:
		var edge := i % 4
		var pos := total.position
		match edge:
			0: pos += Vector2(rng.randf_range(0.0, total.size.x), 0.0)
			1: pos += Vector2(total.size.x, rng.randf_range(0.0, total.size.y))
			2: pos += Vector2(rng.randf_range(0.0, total.size.x), total.size.y)
			_: pos += Vector2(0.0, rng.randf_range(0.0, total.size.y))
		draw_circle(pos, rng.randf_range(4.0, 10.0), Color(0.18, 0.12, 0.07, 0.28))

func _terrain_texture(kind: String) -> Texture2D:
	if _terrain_cache.has(kind):
		return _terrain_cache[kind]
	var path := terrain_texture_path(season, kind)
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_terrain_cache[kind] = texture
	return texture

func _prop_texture(kind: String) -> Texture2D:
	if _prop_cache.has(kind):
		return _prop_cache[kind]
	var path := prop_texture_path(kind)
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_prop_cache[kind] = texture
	return texture

func _prop_region(kind: String, texture: Texture2D) -> Rect2:
	if _prop_region_cache.has(kind):
		return _prop_region_cache[kind]
	var region := Rect2(Vector2.ZERO, texture.get_size())
	var image := texture.get_image()
	if image != null:
		var used := image.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			region = Rect2(used)
	_prop_region_cache[kind] = region
	return region

func _season_edge_color(kind: String) -> Color:
	if kind == "water":
		return Color(0.12, 0.22, 0.25, 0.64)
	if season == "winter":
		return Color(0.17, 0.22, 0.26, 0.55)
	return Color(0.12, 0.09, 0.07, 0.44)

func _prop_season_tint(kind: String) -> Color:
	if kind not in ["tree", "birch", "reeds", "grass"]:
		return Color.WHITE
	match season:
		"summer": return Color(0.90, 1.0, 0.88, 1.0)
		"autumn": return Color(1.0, 0.88, 0.68, 1.0)
		"winter": return Color(0.78, 0.87, 0.92, 1.0)
	return Color(0.92, 1.0, 0.88, 1.0)

func _draw_grass_marks(rect: Rect2) -> void:
	var cols := maxi(1, int(rect.size.x / 150.0))
	var rows := maxi(1, int(rect.size.y / 150.0))
	for row in rows:
		for col in cols:
			var x := rect.position.x + (col + 0.5) * rect.size.x / cols
			var y := rect.position.y + (row + 0.62) * rect.size.y / rows
			draw_line(Vector2(x - 5, y + 5), Vector2(x + 1, y - 7),
				Color(0.88, 0.84, 0.63, 0.28), 2.0)
			draw_line(Vector2(x + 6, y + 5), Vector2(x + 2, y - 4),
				Color(0.20, 0.25, 0.13, 0.22), 2.0)

func _draw_ground_shadow(rect: Rect2) -> void:
	var center := Vector2(rect.get_center().x, rect.end.y - minf(18.0, rect.size.y * 0.12))
	draw_set_transform(center, 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, maxf(24.0, rect.size.x * 0.42), Color(0.04, 0.03, 0.02, 0.22))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 冬季屋脊积雪：沿母版坡屋顶的透视范围铺一层冷白，再挂几根短冰凌。
func _draw_winter_roof_cap(fitted: Rect2) -> void:
	var left := fitted.position + Vector2(fitted.size.x * 0.08, fitted.size.y * 0.38)
	var ridge := fitted.position + Vector2(fitted.size.x * 0.5, fitted.size.y * 0.08)
	var right := fitted.position + Vector2(fitted.size.x * 0.92, fitted.size.y * 0.38)
	var lower_left := fitted.position + Vector2(fitted.size.x * 0.17, fitted.size.y * 0.42)
	var lower_right := fitted.position + Vector2(fitted.size.x * 0.83, fitted.size.y * 0.42)
	draw_colored_polygon([left, ridge, right, lower_right, lower_left],
		Color(0.90, 0.95, 0.96, 0.78))
	draw_polyline([left, ridge, right], Color(0.98, 0.99, 0.98, 0.92), 3.0)
	draw_line(lower_left, lower_right, Color(0.55, 0.67, 0.72, 0.58), 2.0)
	var drop_count := maxi(3, int(fitted.size.x / 90.0))
	for i in drop_count:
		var x := lerpf(lower_left.x, lower_right.x, (i + 0.5) / drop_count)
		var length := 5.0 + float((i * 7) % 11)
		draw_line(Vector2(x, lower_left.y), Vector2(x + 1.0, lower_left.y + length),
			Color(0.84, 0.93, 0.96, 0.72), 2.0)

func _draw_label(text: String, pos: Vector2, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		Color(0.97, 0.91, 0.75))
