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
}

VALID_SEASONS = {"spring", "summer", "autumn", "winter"}
VALID_SOW_SEASONS = {"spring", "summer"}
VALID_HARVEST_SEASONS = {"autumn", "summer"}

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


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("data")
    if not root.exists():
        print(f"❌ 数据目录不存在: {root}", file=sys.stderr)
        return 1

    print("校验静态数据 ...")
    for filename in REQUIRED_KEYS:
        path = root / filename
        if not path.exists():
            ERRORS.append(f"缺少文件: {path}")
            continue
        validate_crops(path)

    if ERRORS:
        for err in ERRORS:
            print(f"  ❌ {err}", file=sys.stderr)
        print(f"\n❌ 校验失败: {len(ERRORS)} 个问题", file=sys.stderr)
        return 1

    print("✅ 数据校验通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
