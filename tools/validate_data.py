#!/usr/bin/env python3
"""《宾州小镇》静态数据校验 —— CI 必跑。

用法:
    python3 tools/validate_data.py data/

校验规则:
  1. crops.json 必填字段齐全
  2. 播种季只能是 spring / summer(黑龙江一年一熟,冬季休耕禁播)
  3. 收获季只能是 autumn / summer
  4. plant_days 不得含 winter
  5. growth_days 为递增区间且最小值 >= 1
  6. 售价 >= 进价
  7. winter_produce 至少 4 项(冬季加工玩法)
  8. 作物 id 不重复

数值表 v1(Week 1 交付物)追加校验:
  9. items.json 道具字段齐全、种子必须指向真实作物、售价 >= 进价
 10. crop_buy_prices 的 base_sell_price 必须与 crops.json 的 sell_price 一致
 11. npcs.json NPC 字段齐全、收购比例在 (0, 1] 区间(对话内容统一在 dialogues.json)

对话系统 v1(Week 5)追加校验:
 12. dialogues.json 每条对话有 id / npc_id / lines,npc_id 指向真实 NPC
 13. 每个条目有 id,且有 text 或 texts 之一
 14. texts 变体与 options 的 condition 键必须在白名单内,season/month 取值合法
 15. options 的 next 必须指向本对话里真实存在的条目 id(写错了对话会静默断掉)
 16. options 的 action 必须在动作白名单内

通讯系统 v1(Week 6)追加校验:
17. postcards.json 联系人与明信片字段齐全,id 不重复
18. 联系人 reply_cards 必须指向真实明信片,且明信片归属该联系人
19. 每张明信片都必须能通过某位联系人的回信序列拿到

世界与生活循环 v1(Week 7)追加校验:
20. maps.json 地形、道具、门、互动点与出生点全部在界内,门双向可达
21. forage / fish / recipes / quests / festivals 的跨表引用全部存在
22. NPC 立绘、精灵与冬装文件真实存在,NPC 喜欢物能在 items.json 里找到
"""
import json
import re
import sys
from pathlib import Path

# 控制台编码未必是 UTF-8(Windows 默认 cp1252),打印中文会抛 UnicodeEncodeError
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8", errors="replace")

REQUIRED_KEYS = {
    "crops.json": [
        "id", "name", "sowing_season", "harvest_season", "plant_days",
        "growth_days", "buy_price", "sell_price", "seed_price",
        "yield_min", "yield_max", "water_per_day",
    ],
    "items.json": [
        "id", "name", "category", "buy_price", "sell_price",
    ],
    "npcs.json": [],
}

## items.json 道具分类白名单
VALID_ITEM_CATEGORIES = {"seed", "tool", "food", "material", "gift"}

## 种子道具必须带 crop_id
SEED_CATEGORY = "seed"

VALID_SEASONS = {"spring", "summer", "autumn", "winter"}
VALID_SOW_SEASONS = {"spring", "summer"}
VALID_HARVEST_SEASONS = {"autumn", "summer"}

## 对话条件键白名单(与 DialogueConditions.evaluate 支持的键一致)
VALID_CONDITION_KEYS = {
    "season", "month", "affection_min", "flag", "not_flag",
    "has_item", "gold_min", "time_from", "time_to", "weather", "weekday",
    "event_done", "not_event_done",
}

## 对话动作白名单(与 DialogueRunner 支持的动作一致)
VALID_ACTIONS = {
    "shop_sell", "shop_buy", "set_flag", "add_affection", "give_item", "open_gift",
}

VALID_WEATHER = {
    "rain", "snow", "storm", "sunny", "cloudy", "drizzle", "cold_snap", "wind",
    "humid", "thunderstorm", "rainstorm", "frost_morning", "cold_rain",
    "first_snow", "clear_cold", "blizzard", "smog",
}

VALID_TERRAIN_TYPES = {
    "grass", "grass_dark", "moss", "dirt", "soil", "road", "plaza", "sand",
    "water", "wall", "floor_wood", "floor_tile", "rug", "stage_floor",
}

VALID_PROP_TYPES = {
    "backstage", "barn", "barrel", "bed", "bench", "birch", "board", "boat",
    "building", "calendar", "cart", "chest", "clothesline", "counter", "crate",
    "desk", "dock", "exam_bed", "fallen_log", "fence", "fish_rack", "gravestone",
    "half_built", "haystack", "house", "instrument", "lamp", "lantern", "lumber",
    "mailboxes", "medicine_cabinet", "mushroom_log", "plow", "reeds", "saw",
    "shelf", "shrine", "sign", "stage", "stall", "stove", "table", "tool_rack",
    "tree", "water_trough", "well", "woodpile", "workbench",
}

## 与 scripts/world/location_scene.gd::_handle_interactable 的动作分支一一对应。
## shop/storage/workshop/theater 已实装，不允许再退回占位提示。
IMPLEMENTED_MAP_ACTIONS = {
    "almanac", "clinic", "cook", "eat", "fishing", "forage", "forecast",
    "market", "post_office", "quest_board", "shop", "sleep", "storage",
    "theater", "well", "workshop",
}
VALID_MAP_ACTIONS = IMPLEMENTED_MAP_ACTIONS

## 节日活动由 LocationScene::_handle_festival 统一承接。
VALID_FESTIVAL_ACTIONS = {
    "watch", "shop", "eat", "fishing", "theater", "market", "dance",
    "river_lantern", "riddle", "fireworks",
}

VALID_QUEST_REQUIREMENT_TYPES = {"deliver", "action", "event", "flag"}

ERRORS = []


def _in_bounds(bounds, point) -> bool:
    width, height = bounds
    return (
        isinstance(point, list)
        and len(point) >= 2
        and 0 <= point[0] <= width
        and 0 <= point[1] <= height
    )


def _rect_in_bounds(bounds, rect) -> bool:
    width, height = bounds
    return (
        isinstance(rect, list)
        and len(rect) == 4
        and rect[2] > 0
        and rect[3] > 0
        and rect[0] >= 0
        and rect[1] >= 0
        and rect[0] + rect[2] <= width
        and rect[1] + rect[3] <= height
    )


def _asset_exists(res_path: str) -> bool:
    if not res_path.startswith("res://"):
        return False
    return (Path.cwd() / res_path.removeprefix("res://")).exists()


def _hhmm(value: str) -> int:
    parts = value.split(":")
    if len(parts) != 2 or not all(part.isdigit() for part in parts):
        return -1
    hour, minute = int(parts[0]), int(parts[1])
    if hour > 26 or minute > 59:
        return -1
    return hour * 60 + minute


def validate_crops(path: Path) -> None:
    try:
        data = json.loads(path.read_text("utf-8"))
    except Exception as exc:  # noqa: BLE001
        ERRORS.append(f"{path.name}: JSON 解析失败 -> {exc}")
        return

    crops = data.get("crops", [])
    if not crops:
        ERRORS.append(f"{path.name}: crops 列表为空")

    seen = set()
    for crop in crops:
        cid = crop.get("id", "?")
        for key in REQUIRED_KEYS["crops.json"]:
            if key not in crop:
                ERRORS.append(f"{path.name}: {cid} 缺少字段 {key}")
        if cid in seen:
            ERRORS.append(f"{path.name}: 重复的作物 id {cid}")
        seen.add(cid)

        sow = crop.get("sowing_season")
        harvest = crop.get("harvest_season")
        if sow not in VALID_SEASONS:
            ERRORS.append(f"{path.name}: {cid} sowing_season 非法 -> {sow}")
        elif sow not in VALID_SOW_SEASONS:
            ERRORS.append(
                f"{path.name}: {cid} 在 '{sow}' 季播种,违反黑龙江一年一熟设定"
                f"(仅允许 spring/summer 播种)")
        if harvest not in VALID_HARVEST_SEASONS:
            ERRORS.append(
                f"{path.name}: {cid} 收获季 '{harvest}' 非法"
                f"(黑龙江仅允许 autumn/summer 收获,冬季休耕)")

        plant_days = crop.get("plant_days", [])
        if not plant_days:
            ERRORS.append(f"{path.name}: {cid} plant_days 为空")
        for d in plant_days:
            if d not in VALID_SOW_SEASONS:
                ERRORS.append(
                    f"{path.name}: {cid} plant_days 含 '{d}'(冬季不能播种)")

        # 农时窗口校验:plant_window / harvest_window 必须是连续区间
        pw = crop.get("plant_window", [])
        hw = crop.get("harvest_window", [])
        if pw and len(pw) != 2:
            ERRORS.append(f"{path.name}: {cid} plant_window 必须是 [起, 止] 连续区间")
        elif pw and int(pw[0]) > int(pw[1]):
            ERRORS.append(f"{path.name}: {cid} plant_window 区间颠倒 {pw}")
        elif pw and (int(pw[0]) < 4 or int(pw[1]) > 7):
            ERRORS.append(
                f"{path.name}: {cid} plant_window {pw} 越界"
                f"(黑龙江春播窗口 4-5月,仅早收复种可用 7 月)")
        if hw and len(hw) != 2:
            ERRORS.append(f"{path.name}: {cid} harvest_window 必须是 [起, 止] 连续区间")
        elif hw and int(hw[0]) > int(hw[1]):
            ERRORS.append(f"{path.name}: {cid} harvest_window 区间颠倒 {hw}")
        elif hw and (int(hw[0]) < 7 or int(hw[1]) > 10):
            ERRORS.append(
                f"{path.name}: {cid} harvest_window {hw} 越界"
                f"(黑龙江收获窗口 7-10月,秋霜后即冻死)")
        # 生长天数必须能跨到收获窗口
        growth = crop.get("growth_days", [])
        if len(growth) != 2:
            ERRORS.append(f"{path.name}: {cid} growth_days 必须为 [min, max]")
        elif growth[0] > growth[1]:
            ERRORS.append(f"{path.name}: {cid} growth_days 区间颠倒 {growth}")
        elif growth[0] < 1:
            ERRORS.append(f"{path.name}: {cid} growth_days 最小值过小 {growth[0]}")

        if crop.get("sell_price", 0) < crop.get("buy_price", 0):
            ERRORS.append(f"{path.name}: {cid} 售价低于进价(经济性异常)")

        # 生长天数必须与农时窗口匹配:播种到收获的可用天数
        if pw and hw and len(pw) == 2 and len(hw) == 2 and len(growth) == 2:
            sow_m = int(pw[0])
            harv_m = int(hw[1])
            avail = (harv_m - sow_m) * 30
            if avail < 0:
                avail += 360
            if int(growth[0]) > avail:
                ERRORS.append(
                    f"{path.name}: {cid} 生长天数 {growth[0]} 超过播种到收获的可用天数 "
                    f"{avail}({sow_m}月播 → {harv_m}月收),来不及成熟")

    winter = data.get("winter_produce", [])
    if len(winter) < 4:
        ERRORS.append(f"{path.name}: winter_produce 至少 4 项(冬季加工玩法)")

    print(f"  · {path.name}: {len(crops)} 种作物, {len(winter)} 项冬季产出")


def load_json(path: Path):
    """读取 JSON,失败时登记错误并返回 None。"""
    try:
        return json.loads(path.read_text("utf-8"))
    except Exception as exc:  # noqa: BLE001
        ERRORS.append(f"{path.name}: JSON 解析失败 -> {exc}")
        return None


def validate_maps(path: Path):
    """地图数据、空间门与互动点的静态一致性。"""
    data = load_json(path)
    if data is None:
        return {}
    maps = data.get("maps", [])
    if not maps:
        ERRORS.append(f"{path.name}: maps 列表为空")
        return {}

    maps_by_id = {}
    for map_data in maps:
        map_id = map_data.get("id", "?")
        if map_id in maps_by_id:
            ERRORS.append(f"{path.name}: 重复的地图 id {map_id}")
        maps_by_id[map_id] = map_data

    for map_id, map_data in maps_by_id.items():
        for key in ("id", "name", "size", "spawn", "terrain", "props", "doors",
                    "interactables"):
            if key not in map_data:
                ERRORS.append(f"{path.name}: {map_id} 缺少字段 {key}")

        size = map_data.get("size", [])
        if not (
            isinstance(size, list)
            and len(size) == 2
            and all(isinstance(value, int) and value > 0 for value in size)
        ):
            ERRORS.append(f"{path.name}: {map_id} size 必须是两个正整数")
            continue
        bounds = (size[0], size[1])
        if not _in_bounds(bounds, map_data.get("spawn")):
            ERRORS.append(f"{path.name}: {map_id} 出生点越界")

        terrain = map_data.get("terrain", [])
        if not terrain:
            ERRORS.append(f"{path.name}: {map_id} 没有地形层")
        for index, layer in enumerate(terrain):
            terrain_type = layer.get("type")
            if terrain_type not in VALID_TERRAIN_TYPES:
                ERRORS.append(
                    f"{path.name}: {map_id}/terrain[{index}] 类型 '{terrain_type}' 非法")
            if not _rect_in_bounds(bounds, layer.get("rect")):
                ERRORS.append(
                    f"{path.name}: {map_id}/terrain[{index}] 矩形越界或宽高为 0")

        for index, prop in enumerate(map_data.get("props", [])):
            prop_type = prop.get("type")
            if prop_type not in VALID_PROP_TYPES:
                ERRORS.append(
                    f"{path.name}: {map_id}/prop[{index}] 类型 '{prop_type}' 非法")
            if not _rect_in_bounds(bounds, prop.get("rect")):
                ERRORS.append(
                    f"{path.name}: {map_id}/prop[{index}] 矩形越界或宽高为 0")

        door_ids = set()
        doors = map_data.get("doors", [])
        if not doors:
            ERRORS.append(f"{path.name}: {map_id} 没有出口")
        for door in doors:
            door_id = door.get("id", "?")
            if door_id in door_ids:
                ERRORS.append(f"{path.name}: {map_id} 重复的门 id {door_id}")
            door_ids.add(door_id)
            if not _rect_in_bounds(bounds, door.get("rect")):
                ERRORS.append(f"{path.name}: {map_id}/{door_id} 门框越界")
            target = door.get("target")
            if target not in maps_by_id:
                ERRORS.append(f"{path.name}: {map_id}/{door_id} 指向不存在的地图 '{target}'")
                continue
            target_size = maps_by_id[target].get("size", [0, 0])
            if not _in_bounds((target_size[0], target_size[1]), door.get("target_spawn")):
                ERRORS.append(
                    f"{path.name}: {map_id}/{door_id} 的目标出生点越出 {target} 边界")
            reverse = any(
                other.get("target") == map_id
                for other in maps_by_id[target].get("doors", [])
            )
            if not reverse:
                ERRORS.append(f"{path.name}: {map_id}/{door_id} 的目标地图没有返程门")

        interactable_ids = set()
        interactables = map_data.get("interactables", [])
        if not interactables:
            ERRORS.append(f"{path.name}: {map_id} 没有互动点")
        for item in interactables:
            item_id = item.get("id", "?")
            if item_id in interactable_ids:
                ERRORS.append(f"{path.name}: {map_id} 重复的互动点 id {item_id}")
            interactable_ids.add(item_id)
            if not _in_bounds(bounds, item.get("pos")):
                ERRORS.append(f"{path.name}: {map_id}/{item_id} 互动点越界")
            if float(item.get("radius", 0)) <= 0:
                ERRORS.append(f"{path.name}: {map_id}/{item_id} radius 必须大于 0")
            action = item.get("action")
            if action not in VALID_MAP_ACTIONS:
                ERRORS.append(f"{path.name}: {map_id}/{item_id} 动作 '{action}' 非法")

    print(f"  · {path.name}: {len(maps_by_id)} 张地图")
    validate_farm_expansion(maps_by_id)
    return maps_by_id


def validate_farm_expansion(maps_by_id) -> None:
    """木工房扩建上限必须与 L01 的可耕地面积一致。"""
    l01 = maps_by_id.get("L01", {})
    area = l01.get("farm_area", {})
    capacity = int(area.get("width", 0)) * int(area.get("height", 0))
    script_path = Path("scripts/farming/farm_expansion_system.gd")
    if not script_path.exists():
        ERRORS.append(f"缺少扩建实现: {script_path}")
        return
    source = script_path.read_text("utf-8")
    max_match = re.search(r"const MAX_PLOTS\s*:=\s*(\d+)", source)
    if not max_match:
        ERRORS.append("farm_expansion_system.gd: 找不到 MAX_PLOTS")
        return
    max_plots = int(max_match.group(1))
    if max_plots != capacity:
        ERRORS.append(
            f"farm_expansion_system.gd: MAX_PLOTS={max_plots} 与 L01 farm_area "
            f"{area.get('width', 0)}×{area.get('height', 0)}={capacity} 不一致")
    steps_source = source.split("static func next_step", 1)[0]
    totals = [int(value) for value in re.findall(r'"total"\s*:\s*(\d+)', steps_source)]
    if not totals:
        ERRORS.append("farm_expansion_system.gd: 找不到扩建阶梯 total")
    elif totals != sorted(totals) or len(set(totals)) != len(totals):
        ERRORS.append(f"farm_expansion_system.gd: 扩建阶梯必须递增且不重复 -> {totals}")
    elif totals[-1] > capacity:
        ERRORS.append(
            f"farm_expansion_system.gd: 扩建终点 {totals[-1]} 超过 L01 容量 {capacity}")


def validate_items(path: Path, crops_data) -> None:
    """数值表 v1:道具 + 作物收购价。"""
    data = load_json(path)
    if data is None:
        return

    crop_ids = set()
    if crops_data:
        crop_ids = {c.get("id") for c in crops_data.get("crops", [])}

    items = data.get("items", [])
    if not items:
        ERRORS.append(f"{path.name}: items 列表为空")

    seen = set()
    for item in items:
        iid = item.get("id", "?")
        for key in REQUIRED_KEYS["items.json"]:
            if key not in item:
                ERRORS.append(f"{path.name}: {iid} 缺少字段 {key}")
        if iid in seen:
            ERRORS.append(f"{path.name}: 重复的道具 id {iid}")
        seen.add(iid)

        cat = item.get("category")
        if cat not in VALID_ITEM_CATEGORIES:
            ERRORS.append(
                f"{path.name}: {iid} category 非法 -> {cat}"
                f"(允许 {sorted(VALID_ITEM_CATEGORIES)})")

        if cat == SEED_CATEGORY:
            crop_id = item.get("crop_id")
            if not crop_id:
                ERRORS.append(f"{path.name}: {iid} 是种子,必须指定 crop_id")
            elif crop_ids and crop_id not in crop_ids:
                ERRORS.append(
                    f"{path.name}: {iid} 指向不存在的作物 '{crop_id}'")

        # 道具是"买入 / 卖出"两个方向,半价出售属于正常(收购商压价),
        # 因此不套用农作物的"售价 >= 进价"规则;这里只校验价格为正。
        if int(item.get("buy_price", 0)) <= 0:
            ERRORS.append(f"{path.name}: {iid} buy_price 必须大于 0")
        if int(item.get("sell_price", 0)) < 0:
            ERRORS.append(f"{path.name}: {iid} sell_price 不能为负")

    # 作物收购价必须与 crops.json 的 sell_price 保持一致
    for entry in data.get("crop_buy_prices", []):
        cid = entry.get("crop_id", "?")
        base = entry.get("base_sell_price")
        ratio = entry.get("buy_ratio")
        if ratio is None or not (0.0 < float(ratio) <= 1.0):
            ERRORS.append(
                f"{path.name}: {cid} buy_ratio 必须在 (0, 1] 区间 -> {ratio}")
        if crop_ids and cid not in crop_ids:
            ERRORS.append(f"{path.name}: 收购价条目指向不存在的作物 '{cid}'")
        if crops_data:
            match = next(
                (c for c in crops_data.get("crops", []) if c.get("id") == cid), None)
            if match is not None and base is not None:
                if int(base) != int(match.get("sell_price", 0)):
                    ERRORS.append(
                        f"{path.name}: {cid} base_sell_price {base} 与 crops.json "
                        f"的 sell_price {match.get('sell_price')} 不一致")

    consumables = data.get("consumables", [])
    for c in consumables:
        if int(c.get("restore_energy", 0)) <= 0:
            ERRORS.append(
                f"{path.name}: {c.get('id', '?')} restore_energy 必须大于 0")

    print(f"  · {path.name}: {len(items)} 件道具, "
          f"{len(data.get('crop_buy_prices', []))} 条收购价")


def validate_forage(path: Path, maps_by_id, item_ids) -> None:
    """四季采集点:地图互动点、季节与物品引用。"""
    data = load_json(path)
    if data is None:
        return
    points = data.get("points", [])
    if not points:
        ERRORS.append(f"{path.name}: points 列表为空")
    interactables_by_map = {
        map_id: {item.get("id") for item in map_data.get("interactables", [])}
        for map_id, map_data in maps_by_id.items()
    }
    seen = set()
    for point in points:
        key = point.get("key", "?")
        if key in seen:
            ERRORS.append(f"{path.name}: 重复的采集点 key {key}")
        seen.add(key)
        map_id = point.get("map_id")
        if map_id not in maps_by_id:
            ERRORS.append(f"{path.name}: {key} 的 map_id '{map_id}' 不存在")
            continue
        interactable_id = point.get("interactable_id")
        if interactable_id not in interactables_by_map[map_id]:
            ERRORS.append(
                f"{path.name}: {key} 的互动点 '{interactable_id}' 不在 {map_id}")
        seasons = point.get("seasons", [])
        if not seasons:
            ERRORS.append(f"{path.name}: {key} seasons 为空")
        for season in seasons:
            if season not in VALID_SEASONS:
                ERRORS.append(f"{path.name}: {key} 非法季节 '{season}'")
        if int(point.get("respawn_days", 0)) < 1:
            ERRORS.append(f"{path.name}: {key} respawn_days 必须大于等于 1")
        options = point.get("items", [])
        if not options:
            ERRORS.append(f"{path.name}: {key} items 为空")
        for option in options:
            item_id = option.get("id")
            if item_id not in item_ids:
                ERRORS.append(f"{path.name}: {key} 的采集物 '{item_id}' 不存在")
            if int(option.get("weight", 0)) <= 0:
                ERRORS.append(f"{path.name}: {key}/{item_id} weight 必须大于 0")
            low = int(option.get("min", 1))
            high = int(option.get("max", 1))
            if low <= 0 or high < low:
                ERRORS.append(f"{path.name}: {key}/{item_id} min/max 非法")
    print(f"  · {path.name}: {len(points)} 个四季采集点")


def validate_fish(path: Path, item_ids) -> None:
    """鱼种季节池与物品引用。"""
    data = load_json(path)
    if data is None:
        return
    fish = data.get("fish", [])
    if not fish:
        ERRORS.append(f"{path.name}: fish 列表为空")
    seen = set()
    for entry in fish:
        fish_id = entry.get("id", "?")
        if fish_id in seen:
            ERRORS.append(f"{path.name}: 重复的鱼 id {fish_id}")
        seen.add(fish_id)
        if fish_id not in item_ids:
            ERRORS.append(f"{path.name}: {fish_id} 在 items.json 里不存在")
        seasons = entry.get("seasons", [])
        if not seasons:
            ERRORS.append(f"{path.name}: {fish_id} seasons 为空")
        for season in seasons:
            if season not in VALID_SEASONS:
                ERRORS.append(f"{path.name}: {fish_id} 非法季节 '{season}'")
        if int(entry.get("weight", 0)) <= 0:
            ERRORS.append(f"{path.name}: {fish_id} weight 必须大于 0")
        if not 1 <= int(entry.get("difficulty", 0)) <= 5:
            ERRORS.append(f"{path.name}: {fish_id} difficulty 必须在 1..5")
    print(f"  · {path.name}: {len(fish)} 种鱼")


def validate_recipes(path: Path, item_ids) -> None:
    """菜谱产物与配料引用。"""
    data = load_json(path)
    if data is None:
        return
    recipes = data.get("recipes", [])
    if not recipes:
        ERRORS.append(f"{path.name}: recipes 列表为空")
    seen = set()
    for recipe in recipes:
        recipe_id = recipe.get("id", "?")
        if recipe_id in seen:
            ERRORS.append(f"{path.name}: 重复的菜谱 id {recipe_id}")
        seen.add(recipe_id)
        result = recipe.get("result")
        if result not in item_ids:
            ERRORS.append(f"{path.name}: {recipe_id} 的产物 '{result}' 不存在")
        ingredients = recipe.get("ingredients", [])
        if not ingredients:
            ERRORS.append(f"{path.name}: {recipe_id} 没有配料")
        for ingredient in ingredients:
            item_id = ingredient.get("id")
            if item_id not in item_ids:
                ERRORS.append(f"{path.name}: {recipe_id} 的配料 '{item_id}' 不存在")
            if int(ingredient.get("count", 0)) <= 0:
                ERRORS.append(f"{path.name}: {recipe_id}/{item_id} 数量必须大于 0")
        if int(recipe.get("energy", 0)) < 0:
            ERRORS.append(f"{path.name}: {recipe_id} energy 不能为负")
    print(f"  · {path.name}: {len(recipes)} 道菜谱")


def validate_quests(path: Path, npc_ids, item_ids, event_ids) -> None:
    """公告板与人物委托:领取人、交付物、事件前置和奖励引用。"""
    data = load_json(path)
    if data is None:
        return
    quests = data.get("quests", [])
    if not quests:
        ERRORS.append(f"{path.name}: quests 列表为空")
    seen = set()
    for quest in quests:
        quest_id = quest.get("id", "?")
        if quest_id in seen:
            ERRORS.append(f"{path.name}: 重复的任务 id {quest_id}")
        seen.add(quest_id)
        if quest.get("giver") not in npc_ids:
            ERRORS.append(f"{path.name}: {quest_id} 的 giver 不存在")
        requirements = quest.get("requirements", [])
        if not requirements:
            ERRORS.append(f"{path.name}: {quest_id} 没有完成条件")
        for requirement in requirements:
            req_type = requirement.get("type")
            if req_type not in VALID_QUEST_REQUIREMENT_TYPES:
                ERRORS.append(f"{path.name}: {quest_id} 条件类型 '{req_type}' 非法")
                continue
            if req_type == "deliver":
                item_id = requirement.get("item_id")
                if item_id not in item_ids:
                    ERRORS.append(f"{path.name}: {quest_id} 交付物 '{item_id}' 不存在")
                if int(requirement.get("count", 0)) <= 0:
                    ERRORS.append(f"{path.name}: {quest_id}/{item_id} 数量必须大于 0")
            elif req_type == "action":
                if not requirement.get("target"):
                    ERRORS.append(f"{path.name}: {quest_id} action 条件缺少 target")
                if int(requirement.get("count", 0)) <= 0:
                    ERRORS.append(f"{path.name}: {quest_id} action count 必须大于 0")
            elif req_type == "event":
                event_id = requirement.get("event_id")
                if event_id not in event_ids:
                    ERRORS.append(f"{path.name}: {quest_id} 引用不存在的事件 '{event_id}'")
            elif req_type == "flag" and not requirement.get("flag"):
                ERRORS.append(f"{path.name}: {quest_id} flag 条件缺少 flag")
        reward_items = (quest.get("rewards") or {}).get("items", {})
        for item_id in reward_items:
            if item_id not in item_ids:
                ERRORS.append(f"{path.name}: {quest_id} 奖励物 '{item_id}' 不存在")
    print(f"  · {path.name}: {len(quests)} 条任务")


def validate_festivals(path: Path, maps_by_id) -> None:
    """节日日期、地点与活动。"""
    data = load_json(path)
    if data is None:
        return
    festivals = data.get("festivals", [])
    if not festivals:
        ERRORS.append(f"{path.name}: festivals 列表为空")
    seen = set()
    for festival in festivals:
        festival_id = festival.get("id", "?")
        if festival_id in seen:
            ERRORS.append(f"{path.name}: 重复的节日 id {festival_id}")
        seen.add(festival_id)
        if not 1 <= int(festival.get("month", 0)) <= 12:
            ERRORS.append(f"{path.name}: {festival_id} month 非法")
        if not 1 <= int(festival.get("day", 0)) <= 30:
            ERRORS.append(f"{path.name}: {festival_id} day 非法")
        if festival.get("location_id") not in maps_by_id:
            ERRORS.append(f"{path.name}: {festival_id} 的地点不存在")
        activities = festival.get("activities", [])
        if not activities:
            ERRORS.append(f"{path.name}: {festival_id} 没有活动")
        for activity in activities:
            if not activity.get("name") or not activity.get("action"):
                ERRORS.append(f"{path.name}: {festival_id} 的活动缺少 name/action")
            elif activity.get("action") not in VALID_FESTIVAL_ACTIONS:
                ERRORS.append(
                    f"{path.name}: {festival_id} 的活动动作 '{activity.get('action')}' 未实现")
    print(f"  · {path.name}: {len(festivals)} 个节日")


def validate_npcs(path: Path, maps_by_id=None, item_names=None) -> None:
    """NPC v2：档案、生日、喜恶、贴图与四季日程。"""
    data = load_json(path)
    if data is None:
        return

    npcs = data.get("npcs", [])
    if not npcs:
        ERRORS.append(f"{path.name}: npcs 列表为空")

    maps_by_id = maps_by_id or {}
    item_names = item_names or set()

    seen = set()
    for npc in npcs:
        nid = npc.get("id", "?")
        for key in (
            "id", "name", "title", "gender", "birthday_month", "birthday_day",
            "home_location", "home_position", "sprite_path", "portrait_path",
            "likes", "dislikes", "schedules",
        ):
            if key not in npc:
                ERRORS.append(f"{path.name}: {nid} 缺少字段 {key}")
        if nid in seen:
            ERRORS.append(f"{path.name}: 重复的 NPC id {nid}")
        seen.add(nid)

        if npc.get("buys_crops"):
            ratio = npc.get("buy_ratio")
            if ratio is None or not (0.0 < float(ratio) <= 1.0):
                ERRORS.append(
                    f"{path.name}: {nid} buy_ratio 必须在 (0, 1] 区间 -> {ratio}")

        month = npc.get("birthday_month")
        day = npc.get("birthday_day")
        if not isinstance(month, int) or not 1 <= month <= 12:
            ERRORS.append(f"{path.name}: {nid} birthday_month 非法 -> {month}")
        if not isinstance(day, int) or not 1 <= day <= 30:
            ERRORS.append(f"{path.name}: {nid} birthday_day 非法 -> {day}")

        for field in ("sprite_path", "winter_sprite_path", "portrait_path"):
            value = str(npc.get(field, ""))
            if not value.startswith("res://"):
                ERRORS.append(f"{path.name}: {nid} {field} 必须是 res:// 路径")
            elif not _asset_exists(value):
                ERRORS.append(f"{path.name}: {nid} {field} 文件不存在 -> {value}")

        home = npc.get("home_location")
        if maps_by_id and home not in maps_by_id:
            ERRORS.append(f"{path.name}: {nid} 的 home_location '{home}' 不存在")

        schedules = npc.get("schedules", [])
        if not schedules:
            ERRORS.append(f"{path.name}: {nid} schedules 为空")
        for index, entry in enumerate(schedules):
            label = f"{nid}/schedule[{index}]"
            for key in ("time_from", "time_to", "location_id", "position", "activity"):
                if key not in entry:
                    ERRORS.append(f"{path.name}: {label} 缺少字段 {key}")
            for key in ("time_from", "time_to"):
                value = str(entry.get(key, ""))
                parts = value.split(":")
                if len(parts) != 2 or not all(p.isdigit() for p in parts):
                    ERRORS.append(f"{path.name}: {label} {key} 不是 HH:MM -> {value}")
            start_minutes = _hhmm(str(entry.get("time_from", "")))
            end_minutes = _hhmm(str(entry.get("time_to", "")))
            if start_minutes >= 0 and end_minutes >= 0 and start_minutes >= end_minutes:
                ERRORS.append(f"{path.name}: {label} time_from 必须早于 time_to")
            location = entry.get("location_id")
            map_data = maps_by_id.get(location)
            if maps_by_id and map_data is None:
                ERRORS.append(f"{path.name}: {label} 地点 '{location}' 不存在")
            pos = entry.get("position", [])
            if not isinstance(pos, list) or len(pos) != 2:
                ERRORS.append(f"{path.name}: {label} position 必须是 [x, y]")
            elif map_data is not None:
                width, height = map_data.get("size", [0, 0])
                if not (0 <= pos[0] <= width and 0 <= pos[1] <= height):
                    ERRORS.append(f"{path.name}: {label} position 越出 {location} 边界")
            for season in entry.get("seasons", []):
                if season not in VALID_SEASONS:
                    ERRORS.append(f"{path.name}: {label} 非法季节 '{season}'")
            for weather in entry.get("weather", []):
                if weather not in {
                    "rain", "snow", "storm", "sunny", "sunny", "cloudy", "drizzle",
                    "cold_snap", "wind", "humid", "thunderstorm", "rainstorm",
                    "frost_morning", "cold_rain", "first_snow", "clear_cold",
                    "blizzard", "smog",
                }:
                    ERRORS.append(f"{path.name}: {label} 非法天气 '{weather}'")

        liked_matches = [name for name in npc.get("likes", []) if name in item_names]
        if item_names and len(liked_matches) < 3:
            ERRORS.append(
                f"{path.name}: {nid} 至少要有 3 种喜欢物能在 items.json 里获得，"
                f"当前只有 {liked_matches}")

    print(f"  · {path.name}: {len(npcs)} 位 NPC")


def validate_dialogues(path: Path, npcs_data) -> None:
    """对话系统 v1:对话数据。"""
    data = load_json(path)
    if data is None:
        return

    dialogues = data.get("dialogues", [])
    if not dialogues:
        ERRORS.append(f"{path.name}: dialogues 列表为空")

    npc_ids = set()
    if npcs_data:
        npc_ids = {n.get("id") for n in npcs_data.get("npcs", [])}

    seen = set()
    seasonal_counts = {}
    season_months = {
        "spring": {3, 4, 5}, "summer": {6, 7, 8},
        "autumn": {9, 10}, "winter": {11, 12, 1, 2},
    }
    for dialogue in dialogues:
        did = dialogue.get("id", "?")
        for key in ("id", "npc_id", "lines"):
            if key not in dialogue:
                ERRORS.append(f"{path.name}: {did} 缺少字段 {key}")
        if did in seen:
            ERRORS.append(f"{path.name}: 重复的对话 id {did}")
        seen.add(did)

        npc_id = dialogue.get("npc_id")
        if npc_ids and npc_id not in npc_ids:
            ERRORS.append(
                f"{path.name}: {did} 的 npc_id '{npc_id}' 在 npcs.json 里不存在")

        lines = dialogue.get("lines", [])
        if not lines:
            ERRORS.append(f"{path.name}: {did} lines 为空")

        counts = {season: 0 for season in VALID_SEASONS}
        for line in lines:
            for variant in line.get("texts", []):
                condition = variant.get("condition", {}) if isinstance(variant, dict) else {}
                season_cond = condition.get("season")
                month_cond = condition.get("month")
                if season_cond:
                    values = season_cond if isinstance(season_cond, list) else [season_cond]
                    for season in VALID_SEASONS:
                        if season in values:
                            counts[season] += 1
                elif month_cond:
                    values = month_cond if isinstance(month_cond, list) else [month_cond]
                    for season, months in season_months.items():
                        if any(int(month) in months for month in values):
                            counts[season] += 1
        seasonal_counts[npc_id] = counts

        # 先收齐全部条目 id —— 跳转可以向前也可以向后,
        # 查跳转目标前必须把整份对话的 id 收齐,否则会误报
        line_ids = set()
        for line in lines:
            lid = line.get("id", "?")
            if "id" not in line:
                ERRORS.append(f"{path.name}: {did} 里的条目缺少 id")
            if lid in line_ids:
                ERRORS.append(f"{path.name}: {did} 里有重复的条目 id {lid}")
            line_ids.add(lid)

        for line in lines:
            lid = line.get("id", "?")

            # 台词:text 或 texts 至少有一个
            if "text" not in line and "texts" not in line:
                ERRORS.append(f"{path.name}: {did}/{lid} 既没有 text 也没有 texts")

            variants = line.get("texts", [])
            if variants:
                for variant in variants:
                    if not variant.get("text"):
                        ERRORS.append(f"{path.name}: {did}/{lid} 的 texts 变体缺少 text")
                    _check_condition(path, did, lid, variant.get("condition", {}))
            elif not str(line.get("text", "")).strip():
                ERRORS.append(f"{path.name}: {did}/{lid} 的 text 为空")

            # 条目自身的条件
            if "condition" in line:
                _check_condition(path, did, lid, line.get("condition", {}))

            for opt in line.get("options", []):
                if not opt.get("text"):
                    ERRORS.append(f"{path.name}: {did}/{lid} 的选项缺少 text")
                if "condition" in opt:
                    _check_condition(path, did, lid, opt.get("condition", {}))
                action = opt.get("action")
                if action and action not in VALID_ACTIONS:
                    ERRORS.append(
                        f"{path.name}: {did}/{lid} 的选项动作 '{action}' 不在白名单内"
                        f"(允许 {sorted(VALID_ACTIONS)})")
                nxt = opt.get("next")
                if nxt and nxt not in line_ids:
                    ERRORS.append(
                        f"{path.name}: {did}/{lid} 的选项跳转到不存在的条目 '{nxt}'")

    for npc_id, counts in seasonal_counts.items():
        for season, count in counts.items():
            if count < 4:
                ERRORS.append(
                    f"{path.name}: {npc_id} 的 {season} 季只有 {count} 条季节化日常对白，"
                    "设计要求每季至少 4 条")

    print(f"  · {path.name}: {len(dialogues)} 份对话, "
          f"{sum(len(d.get('lines', [])) for d in dialogues)} 个条目")


def validate_events(path: Path, npcs_data) -> None:
    """好感事件：18 段、引用、条件与对话分支完整。"""
    data = load_json(path)
    if data is None:
        return
    events = data.get("events", [])
    if not events:
        ERRORS.append(f"{path.name}: events 列表为空")
        return
    npc_ids = {n.get("id") for n in (npcs_data or {}).get("npcs", [])}
    maps_path = path.parent / "maps.json"
    maps_by_id = {}
    if maps_path.exists():
        maps_by_id = {m.get("id"): m for m in (load_json(maps_path) or {}).get("maps", [])}
    ids = {e.get("id") for e in events}
    if len(ids) != len(events):
        ERRORS.append(f"{path.name}: 事件 id 有重复")
    per_npc = {npc_id: 0 for npc_id in npc_ids}

    for event in events:
        eid = event.get("id", "?")
        for key in ("id", "npc_id", "title", "affection_min", "location_id",
                    "time_from", "time_to", "lines"):
            if key not in event:
                ERRORS.append(f"{path.name}: {eid} 缺少字段 {key}")
        npc_id = event.get("npc_id")
        if npc_ids and npc_id not in npc_ids:
            ERRORS.append(f"{path.name}: {eid} 的 npc_id '{npc_id}' 不存在")
        if npc_id in per_npc:
            per_npc[npc_id] += 1
        if not 0 <= int(event.get("affection_min", 0)) <= 100:
            ERRORS.append(f"{path.name}: {eid} affection_min 必须在 0..100")
        if maps_by_id and event.get("location_id") not in maps_by_id:
            ERRORS.append(f"{path.name}: {eid} 的地点不存在")
        for season in event.get("seasons", []):
            if season not in VALID_SEASONS:
                ERRORS.append(f"{path.name}: {eid} 非法季节 '{season}'")
        for weather in event.get("weather", []):
            if weather not in VALID_WEATHER:
                ERRORS.append(f"{path.name}: {eid} 非法天气 '{weather}'")
        for req in event.get("requires_events", []):
            if req not in ids:
                ERRORS.append(f"{path.name}: {eid} 依赖不存在的事件 '{req}'")
        lines = event.get("lines", [])
        if not lines:
            ERRORS.append(f"{path.name}: {eid} lines 为空")
        line_ids = {line.get("id") for line in lines}
        for line in lines:
            lid = line.get("id", "?")
            if "id" not in line:
                ERRORS.append(f"{path.name}: {eid} 的条目缺少 id")
            if "text" not in line and "texts" not in line:
                ERRORS.append(f"{path.name}: {eid}/{lid} 既没有 text 也没有 texts")
            for variant in line.get("texts", []):
                _check_condition(path, eid, lid, variant.get("condition", {}))
            if "condition" in line:
                _check_condition(path, eid, lid, line.get("condition", {}))
            for opt in line.get("options", []):
                if not opt.get("text"):
                    ERRORS.append(f"{path.name}: {eid}/{lid} 的选项缺少 text")
                if "condition" in opt:
                    _check_condition(path, eid, lid, opt.get("condition", {}))
                if opt.get("action") and opt.get("action") not in VALID_ACTIONS:
                    ERRORS.append(
                        f"{path.name}: {eid}/{lid} 的动作 '{opt.get('action')}' 非法")
                if opt.get("next") not in (None, "") and opt.get("next") not in line_ids:
                    ERRORS.append(
                        f"{path.name}: {eid}/{lid} 的 next '{opt.get('next')}' 不存在")

    for npc_id, count in per_npc.items():
        if npc_id and count != 3:
            ERRORS.append(f"{path.name}: {npc_id} 应有 3 段好感事件，实际 {count}")
    print(f"  · {path.name}: {len(events)} 段好感事件")


def validate_postcards(path: Path) -> None:
    """通讯系统 v1:联系人与回信明信片。"""
    data = load_json(path)
    if data is None:
        return

    if int(data.get("delivery_days", 0)) < 1:
        ERRORS.append(f"{path.name}: delivery_days 必须至少为 1 天")

    recipients = data.get("recipients", [])
    postcards = data.get("postcards", [])
    if not recipients:
        ERRORS.append(f"{path.name}: recipients 列表为空")
    if not postcards:
        ERRORS.append(f"{path.name}: postcards 列表为空")

    recipient_ids = set()
    for recipient in recipients:
        rid = recipient.get("id", "?")
        for key in ("id", "name", "relation", "reply_cards"):
            if key not in recipient:
                ERRORS.append(f"{path.name}: {rid} 缺少字段 {key}")
        if rid in recipient_ids:
            ERRORS.append(f"{path.name}: 重复的联系人 id {rid}")
        recipient_ids.add(rid)
        replies = recipient.get("reply_cards", [])
        if not replies:
            ERRORS.append(f"{path.name}: {rid} 没有任何回信明信片")
        if len(set(replies)) != len(replies):
            ERRORS.append(f"{path.name}: {rid} 的 reply_cards 有重复项")

    postcard_ids = set()
    for postcard in postcards:
        pid = postcard.get("id", "?")
        for key in ("id", "title", "recipient_id", "stamp_color", "body"):
            if key not in postcard:
                ERRORS.append(f"{path.name}: {pid} 缺少字段 {key}")
        if pid in postcard_ids:
            ERRORS.append(f"{path.name}: 重复的明信片 id {pid}")
        postcard_ids.add(pid)
        if not str(postcard.get("body", "")).strip():
            ERRORS.append(f"{path.name}: {pid} 的正文为空")
        color = str(postcard.get("stamp_color", ""))
        if len(color) != 7 or not color.startswith("#"):
            ERRORS.append(f"{path.name}: {pid} 的 stamp_color 必须是 #RRGGBB")
        if recipient_ids and postcard.get("recipient_id") not in recipient_ids:
            ERRORS.append(
                f"{path.name}: {pid} 的 recipient_id "
                f"'{postcard.get('recipient_id')}' 在 recipients 里不存在")

    reachable = set()
    for recipient in recipients:
        rid = recipient.get("id", "?")
        for pid in recipient.get("reply_cards", []):
            if pid not in postcard_ids:
                ERRORS.append(
                    f"{path.name}: {rid} 的 reply_cards 指向不存在的明信片 '{pid}'")
                continue
            card = next((p for p in postcards if p.get("id") == pid), None)
            if card is not None and card.get("recipient_id") != rid:
                ERRORS.append(
                    f"{path.name}: {pid} 挂在 {rid} 的回信序列里,"
                    f"但 recipient_id 是 '{card.get('recipient_id')}'")
            reachable.add(pid)
    orphaned = postcard_ids - reachable
    for pid in sorted(orphaned):
        ERRORS.append(f"{path.name}: {pid} 无法通过任何联系人的回信序列拿到")

    print(f"  · {path.name}: {len(recipients)} 位联系人, {len(postcards)} 张明信片")


def _check_condition(path: Path, did: str, lid: str, condition) -> None:
    """条件字典的键与取值必须合法。"""
    if not isinstance(condition, dict):
        ERRORS.append(f"{path.name}: {did}/{lid} 的 condition 不是字典")
        return
    for key, value in condition.items():
        if key not in VALID_CONDITION_KEYS:
            ERRORS.append(
                f"{path.name}: {did}/{lid} 的条件键 '{key}' 不在白名单内"
                f"(允许 {sorted(VALID_CONDITION_KEYS)})")
            continue
        if key == "season":
            seasons = value if isinstance(value, list) else [value]
            for season in seasons:
                if season not in VALID_SEASONS:
                    ERRORS.append(
                        f"{path.name}: {did}/{lid} 的季节条件 '{season}' 非法")
        elif key == "month":
            months = value if isinstance(value, list) else [value]
            for month in months:
                if not isinstance(month, int) or not (1 <= month <= 12):
                    ERRORS.append(
                        f"{path.name}: {did}/{lid} 的月份条件 {month} 非法(1-12)")
        elif key == "weather":
            weathers = value if isinstance(value, list) else [value]
            for weather in weathers:
                if weather not in VALID_WEATHER:
                    ERRORS.append(
                        f"{path.name}: {did}/{lid} 的天气条件 '{weather}' 非法")
        elif key == "weekday":
            days = value if isinstance(value, list) else [value]
            for day in days:
                if not isinstance(day, int) or not 0 <= day <= 6:
                    ERRORS.append(
                        f"{path.name}: {did}/{lid} 的星期条件 {day} 非法(0-6)")


## --- 游戏内文本禁真实地名(D8 决策) ---
##
## 口径:禁真实行政区划与真实专名;允许通用地理词汇(东北 / 黑土地 / 北大荒 / 平原)。
## 理由:游戏是架空小镇,世界观参考黑龙江,但玩家在游戏里看到真实县名会出戏。
## 例外:crops.json 的 origin 是给制作人核实的设定资料,不进 UI,不参与检查。

FORBIDDEN_PLACE_NAMES = [
    "黑龙江省", "哈尔滨市", "宾县", "宾州厅", "松嫩平原", "松花江", "乌苏里江",
    "镜泊湖", "大兴安岭", "兴安岭", "齐齐哈尔", "牡丹江", "佳木斯", "双鸭山",
    "鸡西", "绥化", "伊春", "白城", "鹤岗", "双城", "阿城", "呼兰", "尚志",
    "巴彦", "木兰", "延寿", "通河", "依兰", "方正", "五常", "庆安", "北安",
    "拜泉", "克山", "克东", "讷河", "嫩江", "逊克", "孙吴", "泰来", "甘南",
    "肇东", "肇州", "梨树", "肇州", "海伦", "富锦",
]


def _find_forbidden(text: str) -> list:
    """找出文本里的真实地名。长词优先,命中后从文本里剔除,避免『黑龙江』被『龙江』二次命中。"""
    hits = []
    remaining = text
    for word in sorted(FORBIDDEN_PLACE_NAMES, key=len, reverse=True):
        if word in remaining:
            hits.append(word)
            remaining = remaining.replace(word, "")
    return hits


def validate_no_real_place_names(path: Path, data, skip_fields=None) -> None:
    """检查游戏内可见文本里没有真实行政区划/专名。

    skip_fields:这些字段不参与检查(如 crops.json 的 origin —— 那是给制作人
    核实的设定资料,不会出现在游戏界面里)。
    """
    skip_fields = skip_fields or set()
    hits = []

    def walk(node, trail):
        if isinstance(node, dict):
            for key, value in node.items():
                if key.startswith("_"):
                    continue  # _meta 之类的内部字段
                if key in skip_fields:
                    continue
                walk(value, trail + "/" + key)
        elif isinstance(node, list):
            for i, value in enumerate(node):
                walk(value, trail + "/%d" % i)
        elif isinstance(node, str):
            for word in _find_forbidden(node):
                hits.append((trail, word, node[:40]))

    walk(data, "")
    for trail, word, sample in hits:
        ERRORS.append(
            "%s: 游戏内文本出现真实地名『%s』(%s)—— 改成通用说法"
            % (path.name, word, trail))


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("data")
    if not root.exists():
        print(f"❌ 数据目录不存在: {root}", file=sys.stderr)
        return 1

    print("校验静态数据 ...")

    maps_path = root / "maps.json"
    maps_by_id = {}
    if maps_path.exists():
        maps_by_id = validate_maps(maps_path)
        validate_no_real_place_names(maps_path, load_json(maps_path))
    else:
        ERRORS.append(f"缺少文件: {maps_path}")

    crops_path = root / "crops.json"
    crops_data = None
    if crops_path.exists():
        crops_data = load_json(crops_path)
        validate_crops(crops_path)
    else:
        ERRORS.append(f"缺少文件: {crops_path}")

    items_path = root / "items.json"
    items_data = None
    if items_path.exists():
        items_data = load_json(items_path)
        validate_items(items_path, crops_data)
    else:
        ERRORS.append(f"缺少文件: {items_path}")
    item_ids = {
        item.get("id") for item in (items_data or {}).get("items", [])
    }
    item_names = {
        item.get("name") for item in (items_data or {}).get("items", [])
    }

    # 游戏内文本禁真实地名(对白 / NPC / 物品描述全查;origin 是设定资料,跳过)
    if crops_data is not None:
        validate_no_real_place_names(crops_path, crops_data, skip_fields={"origin"})

    if items_path.exists():
        validate_no_real_place_names(items_path, items_data)

    npcs_path = root / "npcs.json"
    npcs_data = None
    if npcs_path.exists():
        npcs_data = load_json(npcs_path)
        validate_npcs(npcs_path, maps_by_id, item_names)
        validate_no_real_place_names(npcs_path, npcs_data)
    else:
        ERRORS.append(f"缺少文件: {npcs_path}")

    dialogues_path = root / "dialogues.json"
    if dialogues_path.exists():
        validate_dialogues(dialogues_path, npcs_data)
        validate_no_real_place_names(dialogues_path, load_json(dialogues_path))
    else:
        ERRORS.append(f"缺少文件: {dialogues_path}")

    events_path = root / "events.json"
    events_data = None
    event_ids = set()
    if events_path.exists():
        events_data = load_json(events_path)
        event_ids = {
            event.get("id") for event in (events_data or {}).get("events", [])
        }
        validate_events(events_path, npcs_data)
        validate_no_real_place_names(events_path, events_data)
    else:
        ERRORS.append(f"缺少文件: {events_path}")

    postcards_path = root / "postcards.json"
    if postcards_path.exists():
        validate_postcards(postcards_path)
        validate_no_real_place_names(postcards_path, load_json(postcards_path))
    else:
        ERRORS.append(f"缺少文件: {postcards_path}")

    for filename, validator in (
        ("forage.json", lambda path: validate_forage(path, maps_by_id, item_ids)),
        ("fish.json", lambda path: validate_fish(path, item_ids)),
        ("recipes.json", lambda path: validate_recipes(path, item_ids)),
        ("quests.json", lambda path: validate_quests(
            path,
            {npc.get("id") for npc in (npcs_data or {}).get("npcs", [])},
            item_ids,
            event_ids,
        )),
        ("festivals.json", lambda path: validate_festivals(path, maps_by_id)),
    ):
        data_path = root / filename
        if not data_path.exists():
            ERRORS.append(f"缺少文件: {data_path}")
            continue
        validator(data_path)
        validate_no_real_place_names(data_path, load_json(data_path))

    if ERRORS:
        for err in ERRORS:
            print(f"  ❌ {err}", file=sys.stderr)
        print(f"\n❌ 校验失败: {len(ERRORS)} 个问题", file=sys.stderr)
        return 1

    print("✅ 数据校验通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
