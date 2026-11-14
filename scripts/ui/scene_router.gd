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
}

## 地点中文名
const LOCATION_CN := {
	"L01": "自家农场 · 黑土地",
	"L02": "农舍室内",
	"L03": "宾州镇中心",
	"L04": "杂货店",
	"L05": "老邮局",
	"L06": "玉梅饭馆",
	"L07": "镇卫生所",
	"L08": "赵家木工房",
	"L09": "河岸",
	"L10": "桦树林",
	"L11": "古戏台",
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
