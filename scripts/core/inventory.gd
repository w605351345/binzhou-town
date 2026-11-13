extends RefCounted
class_name Inventory

## 背包清单(纯逻辑,可 headless 自测)
##
## 背包里混着两样东西:**庄稼**(收获下来的,能卖)和**物件**(种子、工具、吃食)。
## 玩家一眼得能分清"哪些能卖钱、哪些是种子",所以清单按栏分。

const KIND_CROP := "crop"
const KIND_ITEM := "item"

## 列出背包清单。返回 [{id, name, count, kind}]
## 数据表里查不到的 id 也照列(用 id 当名字),不然东西会凭空消失。
static func list_entries(inventory: Dictionary) -> Array:
	var crops: Array = []
	var items: Array = []
	for item_id in inventory.keys():
		var count := int(inventory[item_id])
		if count <= 0:
			continue
		var key := String(item_id)
		var crop := CropDatabase.get_crop(key)
		if crop != null:
			crops.append({
				"id": key, "name": crop.name, "count": count, "kind": KIND_CROP,
			})
			continue
		var item := ItemDatabase.get_item(key)
		items.append({
			"id": key,
			"name": String(item.get("name", "")) if not item.is_empty() else key,
			"count": count,
			"kind": KIND_ITEM,
		})
	crops.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	items.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	return crops + items

## 只要某一栏(作物栏 / 物件栏)
static func entries_of_kind(inventory: Dictionary, kind: String) -> Array:
	var out: Array = []
	for entry in list_entries(inventory):
		if String(entry.get("kind", "")) == kind:
			out.append(entry)
	return out

## 背包里能卖钱的作物总个数
static func crop_total(inventory: Dictionary) -> int:
	var total := 0
	for entry in entries_of_kind(inventory, KIND_CROP):
		total += int(entry.get("count", 0))
	return total
