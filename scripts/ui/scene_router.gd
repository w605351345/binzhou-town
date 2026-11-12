extends RefCounted
class_name SceneRouter

## 场景路由:统一管理"去哪"的切换(纯逻辑,可 headless 单测)。
##
## MVP 的 4 个地点(L01-L04)在这里登记,避免各处硬编码路径。

const SCENE_FARM := "res://scenes/farm.tscn"
const SCENE_TOWN := "res://scenes/town_street.tscn"
const SCENE_POST := "res://scenes/post_office.tscn"
const SCENE_THEATER := "res://scenes/theater.tscn"

## 地点编号 -> 场景路径
const LOCATIONS := {
	"L01": SCENE_FARM,
	"L02": SCENE_TOWN,
	"L03": SCENE_POST,
	"L04": SCENE_THEATER,
}

## 地点中文名
const LOCATION_CN := {
	"L01": "自家院 · 黑土地",
	"L02": "宾州镇 · 镇大街",
	"L03": "老邮局",
	"L04": "古戏台",
}

## 取地点的场景路径。未登记返回空串。
static func scene_path(location_id: String) -> String:
	return LOCATIONS.get(location_id, "")

## 取地点中文名
static func location_cn(location_id: String) -> String:
	return LOCATION_CN.get(location_id, location_id)

## MVP 已实现的地点(其余为占位,尚未开发)
static func implemented_locations() -> Array:
	return ["L01", "L02"]

## 目标场景是否已实装
static func is_implemented(location_id: String) -> bool:
	return implemented_locations().has(location_id)
