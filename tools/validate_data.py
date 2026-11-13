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
"""
import json
import sys
from pathlib import Path

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
    "has_item", "gold_min",
}

## 对话动作白名单(与 DialogueRunner 支持的动作一致)
VALID_ACTIONS = {
    "shop_sell", "shop_buy", "set_flag", "add_affection", "give_item",
}

ERRORS = []


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


def validate_npcs(path: Path) -> None:
    """数值表 v1:NPC。"""
    data = load_json(path)
    if data is None:
        return

    npcs = data.get("npcs", [])
    if not npcs:
        ERRORS.append(f"{path.name}: npcs 列表为空")

    seen = set()
    for npc in npcs:
        nid = npc.get("id", "?")
        for key in ("id", "name", "buys_crops", "buy_ratio", "scene"):
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

        positions = npc.get("daily_positions", [])
        for pos in positions:
            if not isinstance(pos, list) or len(pos) != 2:
                ERRORS.append(f"{path.name}: {nid} daily_positions 坐标必须是 [x, y]")

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

    print(f"  · {path.name}: {len(dialogues)} 份对话, "
          f"{sum(len(d.get('lines', [])) for d in dialogues)} 个条目")


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


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("data")
    if not root.exists():
        print(f"❌ 数据目录不存在: {root}", file=sys.stderr)
        return 1

    print("校验静态数据 ...")

    crops_path = root / "crops.json"
    crops_data = None
    if crops_path.exists():
        crops_data = load_json(crops_path)
        validate_crops(crops_path)
    else:
        ERRORS.append(f"缺少文件: {crops_path}")

    items_path = root / "items.json"
    if items_path.exists():
        validate_items(items_path, crops_data)
    else:
        ERRORS.append(f"缺少文件: {items_path}")

    npcs_path = root / "npcs.json"
    npcs_data = None
    if npcs_path.exists():
        npcs_data = load_json(npcs_path)
        validate_npcs(npcs_path)
    else:
        ERRORS.append(f"缺少文件: {npcs_path}")

    dialogues_path = root / "dialogues.json"
    if dialogues_path.exists():
        validate_dialogues(dialogues_path, npcs_data)
    else:
        ERRORS.append(f"缺少文件: {dialogues_path}")

    if ERRORS:
        for err in ERRORS:
            print(f"  ❌ {err}", file=sys.stderr)
        print(f"\n❌ 校验失败: {len(ERRORS)} 个问题", file=sys.stderr)
        return 1

    print("✅ 数据校验通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
