extends RefCounted
class_name SceneRouter

## 场景路由:统一管理"去哪"的切换(纯逻辑,可 headless 单测)。
##
## 设计文档 v5 的 11 个地点。每张地图都有独立包装场景，
## 内部共用 scripts/world/location_scene.gd。

const SCENE_FARM := "res://scenes/locations/L01.tscn"
const SCENE_FARMHOUSE := "res://scenes/locations/L02.tscn"
const SCENE_TOWN := "res://scenes/locations/L03.tscn"
const SCENE_GROCERY := "res://scenes/locations/L04.tscn"
const SCENE_POST := "res://scenes/locations/L05.tscn"
const SCENE_RESTAURANT := "res://scenes/locations/L06.tscn"
const SCENE_CLINIC := "res://scenes/locations/L07.tscn"
const SCENE_WORKSHOP := "res://scenes/locations/L08.tscn"
const SCENE_RIVER := "res://scenes/locations/L09.tscn"
const SCENE_FOREST := "res://scenes/locations/L10.tscn"
const SCENE_THEATER := "res://scenes/locations/L11.tscn"
const SCENE_MINE := "res://scenes/locations/L12.tscn"
const SCENE_RANCH := "res://scenes/locations/L13.tscn"
const SCENE_MUSEUM := "res://scenes/locations/L14.tscn"

## 地点编号 -> 场景路径
const LOCATIONS := {
	"L01": SCENE_FARM,
	"L02": SCENE_FARMHOUSE,
	"L03": SCENE_TOWN,
	"L04": SCENE_GROCERY,
	"L05": SCENE_POST,
	"L06": SCENE_RESTAURANT,
	"L07": SCENE_CLINIC,
	"L08": SCENE_WORKSHOP,
	"L09": SCENE_RIVER,
	"L10": SCENE_FOREST,
	"L11": SCENE_THEATER,
	"L12": SCENE_MINE,
	"L13": SCENE_RANCH,
	"L14": SCENE_MUSEUM,
}

## 地点中文名
const LOCATION_CN := {
	"L01": "柳溪农场",
	"L02": "农舍",
	"L03": "麦溪镇中心",
	"L04": "杂货店",
	"L05": "老邮局",
	"L06": "玉梅旅店",
	"L07": "麦溪诊所",
	"L08": "赵氏木工坊",
	"L09": "河湾",
	"L10": "柳溪林",
	"L11": "月桂剧场",
	"L12": "北岭矿洞",
	"L13": "牧云牧场",
	"L14": "麦溪镇史馆",
}

## 取地点的场景路径。未登记返回空串。
static func scene_path(location_id: String) -> String:
	return LOCATIONS.get(location_id, "")

## 取地点中文名
static func location_cn(location_id: String) -> String:
	return LOCATION_CN.get(location_id, location_id)

## v5 全量地点
static func implemented_locations() -> Array:
	return LOCATIONS.keys()

## 目标场景是否已实装
static func is_implemented(location_id: String) -> bool:
	return implemented_locations().has(location_id)
