#!/usr/bin/env python3
"""《宾州小镇》美术资源生成器 —— 饥荒观感手绘像素资源。

沿用 tools/gen_sprites.py 的思路(纯标准库手写 PNG,零第三方依赖,CI 可复现),
但产出的是《视觉与平台升级设计》§3.2 定义的成套资源:

    assets/art/generated/bg_farm_sky.png      农场天空层   960×540
    assets/art/generated/bg_farm_far.png      农场远景层
    assets/art/generated/bg_farm_ground.png   农场地面层
    assets/art/generated/bg_town_*.png        镇大街三层
    assets/sprites/player_body.png            主角 3 行 × 8 列,帧 48×72
    assets/sprites/player_female.png          女主(同布局)
    assets/sprites/npc_zhangxiaofang.png     张晓芳 3 行 × 8 列
    assets/sprites/plots/*.png                5 种土壤贴图 96×96
    assets/sprites/crops/*.png                9 种作物 × 3 阶段 48×48
    assets/sprites/items/*.png                12 件物品图标 48×48

观感规则(与 tools/pixelart.py 文档一致):
    粗描边(暖黑 #241A12)/ 有限暖色盘 / 有机轮廓 / 纸片分层 / 实心阴影 / 上缘高光。

用法:
    python3 tools/gen_art.py [资源根目录]
"""
import math
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pixelart import (INK, Canvas, Rng, bezier, blob, mix, shade,  # noqa: E402
                    tree_silhouette)

# --- 帧布局(与 scripts/player/player.gd 的 FRAME_SIZE / SHEET_ROWS 对齐) ---
# 48×72:角色实际高度约 58px,约为一块地(88px)的 2/3 —— 比例协调,不再"人比地大"。
CELL_W = 48
CELL_H = 72
FRAMES = 8
ROWS = 3            # down / up / side(左右靠 flip_h 镜像)
SHEET_W = CELL_W * FRAMES
SHEET_H = CELL_H * ROWS

# --- 有限暖色盘(与 BZC-ArtProposals 的黑土色系锚点一致) ---
PAL = {
    "ink": INK,
    "soil_dark": (0x3B, 0x2A, 0x1E),
    "soil": (0x6B, 0x4E, 0x32),
    "soil_light": (0x8A, 0x68, 0x45),
    "autumn": (0xC8, 0xA1, 0x65),
    "winter": (0x8F, 0xB8, 0xDE),
    "sack": (0xD9, 0xC9, 0xA3),
    "corn": (0x4A, 0x5D, 0x3A),
    "sky_hi": (0x6E, 0x93, 0xB0),
    "sky_lo": (0xE8, 0xB0, 0x6A),
    "sky_warm": (0xF3, 0xD0, 0x92),
    "sun": (0xFF, 0xE8, 0xB0),
    "wood": (0x7A, 0x54, 0x33),
    "wood_light": (0x9C, 0x70, 0x46),
    "wall": (0xB4, 0x9C, 0x7C),
    "wall_dark": (0x8A, 0x74, 0x59),
    "mud": (0x5B, 0x45, 0x33),
    "mud_light": (0x74, 0x5B, 0x43),
    "sand": (0xC8, 0xA1, 0x65),
    "grass": (0x6E, 0x7A, 0x42),
    "grass_dark": (0x53, 0x5E, 0x33),
}

# --- 角色配色 ---
HERO = {
    "coat": (0x48, 0x6A, 0x94),      # 藏蓝棉袄
    "coat_dark": (0x34, 0x4E, 0x70),
    "pants": (0x3A, 0x3E, 0x4E),
    "boot": (0x2A, 0x24, 0x1E),
    "skin": (0xEE, 0xCD, 0xB2),
    "hair": (0x2E, 0x2A, 0x28),
    "scarf": (0xC8, 0xA1, 0x65),
}
HERO_F = {
    "coat": (0xB0, 0x5C, 0x6C),      # 玫红棉袄
    "coat_dark": (0x8C, 0x44, 0x52),
    "pants": (0x48, 0x42, 0x5C),
    "boot": (0x2A, 0x24, 0x1E),
    "skin": (0xF0, 0xD4, 0xBC),
    "hair": (0x34, 0x28, 0x26),
    "scarf": (0xD9, 0xC9, 0xA3),
    "apron": (0xE4, 0xDA, 0xC0),
}
XIAOFANG = {
    "coat": (0xB0, 0x5C, 0x6C),      # 玫红棉袄
    "coat_dark": (0x8C, 0x44, 0x52),
    "pants": (0x48, 0x42, 0x5C),
    "boot": (0x2A, 0x24, 0x1E),
    "skin": (0xF0, 0xD4, 0xBC),
    "hair": (0x34, 0x28, 0x26),
    "scarf": (0xD9, 0xC9, 0xA3),
    "apron": (0xE4, 0xDA, 0xC0),
}

# 8 帧行走周期:身体起伏 + 双腿摆幅(按 48px 宽的格子缩放)
BOB = [0, 0, 1, 1, 0, 0, -1, -1]
SWING = [0, 1, 3, 4, 3, 1, 0, -1]


def _legs(c, ox, oy, colors, frame, facing):
    """两条腿:走路摆动。侧身时前后摆,正面时左右分。"""
    swing = SWING[frame]
    hip_y = oy - 19
    leg_h = 14
    boot_h = 5
    if facing == "side":
        for dx, factor in ((swing, 1.0), (-swing, 0.66)):
            leg_c = shade(colors["pants"], -0.3 if factor < 1 else 0.0)
            c.thick_line((ox + dx * 0.45, hip_y), (ox + dx, hip_y + leg_h), leg_c, 7)
            c.thick_line((ox + dx, hip_y + leg_h), (ox + dx + 1, hip_y + leg_h + boot_h),
                         colors["boot"], 8)
    else:
        for sign, factor in ((1, 1.0), (-1, 0.66)):
            dx = swing * sign * 0.6
            leg_c = shade(colors["pants"], -0.3 if factor < 1 else 0.0)
            c.thick_line((ox + sign * 6, hip_y), (ox + sign * 6 + dx, hip_y + leg_h),
                         leg_c, 7)
            c.thick_line((ox + sign * 6 + dx, hip_y + leg_h),
                         (ox + sign * 6 + dx, hip_y + leg_h + boot_h),
                         colors["boot"], 8)


def _arms(c, ox, oy, colors, frame, facing):
    """手臂:与腿反相摆动。"""
    swing = SWING[frame]
    shoulder_y = oy - 34
    sleeve = colors["coat"]
    if facing == "side":
        c.thick_line((ox + 1, shoulder_y), (ox + swing * 0.85 + 1, shoulder_y + 16),
                     sleeve, 7)
        c.thick_line((ox - 2, shoulder_y), (ox - swing * 0.7 - 1, shoulder_y + 15),
                     shade(colors["coat"], -0.25), 6)
    else:
        for sign in (1, -1):
            dx = -swing * sign * 0.6
            arm_c = shade(colors["coat"], -0.25 if sign < 0 else 0.0)
            c.thick_line((ox + sign * 12, shoulder_y),
                         (ox + sign * 13 + dx, shoulder_y + 16), arm_c, 7)


def _head(c, ox, oy, colors, facing):
    """头 + 发 + 围巾。oy 为头部中心。"""
    c.fill_circle(ox, oy, 10, colors["skin"])
    if facing == "up":
        # 背对镜头:整颗头都是头发
        c.fill_ellipse(ox, oy, 10.0, 10.0, colors["hair"])
    elif facing == "side":
        # 侧脸:头发盖住后脑,脸朝右
        c.fill_ellipse(ox - 1, oy - 1, 10.0, 9.5, colors["hair"])
        c.fill_ellipse(ox + 4, oy + 2, 6.5, 7.5, colors["skin"])
        c.fill_rect(ox + 6, oy + 1, ox + 8, oy + 3, INK)
    else:
        c.fill_ellipse(ox, oy - 3, 10.0, 8.0, colors["hair"])
        c.fill_ellipse(ox, oy + 3, 8.0, 7.5, colors["skin"])
        c.fill_rect(ox - 5, oy + 1, ox - 3, oy + 3, INK)
        c.fill_rect(ox + 3, oy + 1, ox + 5, oy + 3, INK)
    # 围巾(脖子)
    c.fill_ellipse(ox, oy + 10, 9.0, 4.5, colors["scarf"])


def draw_character(c, ox, oy, colors, frame, facing):
    """在画布 c 上画一帧角色。ox/oy = 角色脚底中心。

    比例基线(48×72 格):脚底 oy=66,头顶 y=8 —— 角色实高 58px,
    约为一块地(88px)的 2/3,视觉上"人站进地里"而不是"人比地大"。
    """
    bob = BOB[frame]
    _legs(c, ox, oy + bob, colors, frame, facing)
    body_top = oy - 43 + bob
    body_bot = oy - 19 + bob
    half = 9.0 if facing == "side" else 13.0
    torso = [
        (ox - half, body_top + 2), (ox - half + 1, body_top),
        (ox + half - 1, body_top), (ox + half, body_top + 2),
        (ox + half + 1, body_bot), (ox - half - 1, body_bot),
    ]
    c.fill_poly(torso, colors["coat"])
    c.fill_rect(ox - half - 1, body_bot - 4, ox + half + 1, body_bot,
                colors["coat_dark"])
    if facing != "side":
        c.fill_rect(ox - 1, body_top + 3, ox + 1, body_bot - 4, colors["coat_dark"])
    if "apron" in colors:
        c.fill_rect(ox - half + 3, body_top + 10, ox + half - 3, body_bot - 1,
                    colors["apron"])
        c.fill_rect(ox - half + 3, body_top + 10, ox + half - 3, body_top + 12,
                    shade(colors["apron"], -0.2))
    _arms(c, ox, oy + bob, colors, frame, facing)
    _head(c, ox, oy - 48 + bob, colors, facing)


def gen_character_sheet(colors, out_path):
    """生成 3 行 × 8 列精灵表(下 / 上 / 侧)。

    逐帧独立画布再描边 —— 免得相邻帧的描边连成一片。
    """
    sheet = Canvas(SHEET_W, SHEET_H)
    order = ["down", "up", "side"]
    for row, facing in enumerate(order):
        for frame in range(FRAMES):
            shadow_c = Canvas(CELL_W, CELL_H)
            shadow_c.drop_shadow(CELL_W // 2, CELL_H - 3, 13, 5)
            frame_c = Canvas(CELL_W, CELL_H)
            draw_character(frame_c, CELL_W // 2, CELL_H - 6, colors, frame, facing)
            frame_c.highlight_top()
            frame_c.outline(INK, width=2)
            sheet.blit(shadow_c, frame * CELL_W, row * CELL_H)
            sheet.blit(frame_c, frame * CELL_W, row * CELL_H)
    sheet.save(out_path)


# ---------------------------------------------------------------------------
# 地块土壤贴图(96×96)
# ---------------------------------------------------------------------------
PLOT_SIZE = 88


def gen_plot_tiles(out_dir):
    """5 种土壤贴图:荒草 / 翻土 / 出苗 / 成熟 / 休耕。"""
    out_dir.mkdir(parents=True, exist_ok=True)
    states = ["untilled", "tilled", "planted", "ready", "fallow"]
    for state in states:
        c = Canvas(PLOT_SIZE, PLOT_SIZE)
        # 稳定种子:Python 的 hash() 对字符串每进程随机,会让 CI 重跑产出不同贴图
        rng = Rng(zlib.crc32(state.encode("utf-8")) & 0xFFFF)
        if state == "untilled":
            # 荒地:枯草为主,露出零星土块 —— 比纯绿更贴黑土地的调子
            c.fill_rect(0, 0, PLOT_SIZE, PLOT_SIZE, (0x7C, 0x7A, 0x46))
            for i in range(22):
                x = rng.uniform(8, PLOT_SIZE - 8)
                y = rng.uniform(8, PLOT_SIZE - 8)
                c.fill_ellipse(x, y, rng.uniform(1.6, 3.2), rng.uniform(1.2, 2.4),
                              PAL["mud"])
            for i in range(90):
                x = rng.uniform(3, PLOT_SIZE - 3)
                y = rng.uniform(3, PLOT_SIZE - 3)
                c.thick_line((x, y), (x + rng.uniform(-3, 3), y - rng.uniform(4, 10)),
                             PAL["grass_dark"] if i % 3 else (0x9A, 0x8E, 0x52), 2)
        elif state == "fallow":
            c.fill_rect(0, 0, PLOT_SIZE, PLOT_SIZE, PAL["soil"])
            for i in range(45):
                x = rng.uniform(3, PLOT_SIZE - 3)
                y = rng.uniform(3, PLOT_SIZE - 3)
                c.thick_line((x, y), (x + rng.uniform(-3, 3), y - rng.uniform(3, 7)),
                             PAL["grass_dark"], 2)
        else:
            c.fill_rect(0, 0, PLOT_SIZE, PLOT_SIZE, PAL["soil"])
            # 翻耕垄沟:横向犁痕 + 垄背高光
            for row in range(4):
                y = 14 + row * 22
                c.fill_rect(0, y, PLOT_SIZE, y + 5, PAL["soil_dark"])
                c.fill_rect(0, y + 5, PLOT_SIZE, y + 8, PAL["soil_light"])
            for i in range(60):
                x = rng.uniform(0, PLOT_SIZE)
                y = rng.uniform(0, PLOT_SIZE)
                c.set(x, y, shade(PAL["soil"], 0.18))
        if state in ("planted", "ready"):
            for row in range(3):
                for col in range(3):
                    x = 16 + col * 32
                    y = 22 + row * 26
                    if state == "planted":
                        c.thick_line((x, y + 8), (x, y - 4), PAL["corn"], 3)
                        c.fill_ellipse(x - 4, y - 4, 4, 2.5, PAL["grass"])
                        c.fill_ellipse(x + 4, y - 6, 4, 2.5, PAL["grass"])
                    else:
                        c.thick_line((x, y + 10), (x, y - 10), PAL["corn"], 4)
                        c.fill_ellipse(x, y - 10, 5, 8, PAL["autumn"])
                        c.fill_ellipse(x - 5, y - 6, 3.5, 6, PAL["autumn"])
                        c.fill_ellipse(x + 5, y - 6, 3.5, 6, PAL["autumn"])
        # 田埂:四周一圈深土色,地块紧贴排布时自然形成网格
        ridge = shade(PAL["soil_dark"], 0.06)
        c.fill_rect(0, 0, PLOT_SIZE, 3, ridge)
        c.fill_rect(0, PLOT_SIZE - 3, PLOT_SIZE, PLOT_SIZE, ridge)
        c.fill_rect(0, 0, 3, PLOT_SIZE, ridge)
        c.fill_rect(PLOT_SIZE - 3, 0, PLOT_SIZE, PLOT_SIZE, ridge)
        # 底边投影:让地块贴在地面上,而不是浮着的贴纸
        c.fill_rect(3, PLOT_SIZE - 4, PLOT_SIZE - 3, PLOT_SIZE, (0, 0, 0, 70))
        # 统一描边(饥荒最标志性的特征)
        c.outline(width=1)
        c.highlight_top()
        c.save(out_dir / ("plot_%s.png" % state))


# ---------------------------------------------------------------------------
# 作物(48×48)
# ---------------------------------------------------------------------------
CROP_SIZE = 48


def _draw_crop(c, kind, scale):
    """在 48×48 画布中央画作物,scale = 0.4(出苗)/0.7(成长)/1.0(成熟)。"""
    cx = CROP_SIZE // 2
    base = CROP_SIZE - 8
    green = PAL["corn"]
    green_dark = shade(green, -0.25)
    gold = PAL["autumn"]
    if kind == "corn":
        h = 30 * scale
        c.thick_line((cx, base), (cx, base - h), green_dark, 4)
        for side in (1, -1):
            c.fill_poly([(cx, base - h * 0.45), (cx + side * 13 * scale, base - h * 0.1),
                         (cx + side * 4 * scale, base - h * 0.05)], green)
        if scale > 0.6:
            c.fill_ellipse(cx, base - h * 0.68, 6 * scale, 12 * scale, gold)
            for i in range(4):
                c.fill_rect(cx - 6 * scale, base - h * 0.68 - 9 * scale + i * 5 * scale,
                            cx + 6 * scale, base - h * 0.68 - 7 * scale + i * 5 * scale,
                            shade(gold, -0.2))
    elif kind in ("rice", "millet", "spring_wheat"):
        h = 30 * scale
        c.thick_line((cx, base), (cx, base - h), green_dark, 3)
        if scale > 0.6:
            for i in range(6):
                y = base - h - i * 3 * scale
                c.fill_ellipse(cx + (2 if i % 2 else -2), y, 3.4 * scale, 4.6 * scale, gold)
            c.thick_line((cx, base - h), (cx, base - h - 10 * scale), gold, 3)
    elif kind == "soybean":
        for side in (1, -1):
            c.fill_ellipse(cx + side * 7 * scale, base - 12 * scale, 7 * scale, 9 * scale, green)
        if scale > 0.6:
            for i in range(3):
                c.fill_ellipse(cx - 6 + i * 6, base - 5 * scale, 4 * scale, 6 * scale,
                               (0xB8, 0x8A, 0x4A))
    elif kind == "potato":
        c.fill_ellipse(cx, base - 8 * scale, 13 * scale, 9 * scale, (0xC2, 0x9A, 0x62))
        if scale > 0.6:
            for side in (1, -1):
                c.thick_line((cx + side * 3, base - 12 * scale),
                             (cx + side * 7, base - 24 * scale), green, 3)
    elif kind == "sugar_beet":
        c.fill_ellipse(cx, base - 8 * scale, 11 * scale, 10 * scale, (0x9E, 0x36, 0x46))
        if scale > 0.6:
            for i in range(4):
                c.fill_ellipse(cx - 7 + i * 5, base - 20 * scale, 4 * scale, 8 * scale, green)
    elif kind == "flax":
        c.thick_line((cx, base), (cx, base - 26 * scale), green_dark, 3)
        if scale > 0.6:
            c.fill_circle(cx, base - 28 * scale, 5 * scale, (0x6E, 0x8A, 0xC4))
            c.fill_circle(cx, base - 28 * scale, 2.2 * scale, PAL["sky_warm"])
    elif kind == "autumn_vegetable":
        for i in range(5):
            c.fill_ellipse(cx - 8 + i * 4, base - 12 * scale, 6 * scale, 11 * scale,
                           (0xE8, 0xE4, 0xC8))
        if scale > 0.6:
            c.fill_ellipse(cx, base - 24 * scale, 8 * scale, 7 * scale, green)
    else:
        c.fill_ellipse(cx, base - 10 * scale, 8 * scale, 10 * scale, green)


def gen_crops(out_dir):
    """9 种作物 × (出苗/成长/成熟)。文件名与 crops.json 的 icon 字段对齐。"""
    out_dir.mkdir(parents=True, exist_ok=True)
    kinds = ["corn", "soybean", "rice", "potato", "millet",
             "sugar_beet", "flax", "spring_wheat", "autumn_vegetable"]
    for kind in kinds:
        for stage, scale in ((0, 0.42), (1, 0.72), (2, 1.0)):
            c = Canvas(CROP_SIZE, CROP_SIZE)
            _draw_crop(c, kind, scale)
            c.outline()
            c.highlight_top()
            if stage == 2:
                c.save(out_dir / ("%s.png" % kind))
            else:
                c.save(out_dir / ("%s_s%d.png" % (kind, stage)))


# ---------------------------------------------------------------------------
# 物品图标(48×48)
# ---------------------------------------------------------------------------
def gen_items(out_dir):
    """12 件物品图标。文件名与 items.json 的 icon 字段对齐。"""
    out_dir.mkdir(parents=True, exist_ok=True)
    cx = 24
    base = 40

    def canvas():
        return Canvas(CROP_SIZE, CROP_SIZE)

    # 种子袋
    for name, tint in (("seed_corn", PAL["autumn"]), ("seed_potato", (0xC2, 0x9A, 0x62)),
                       ("seed_autumn_vegetable", PAL["corn"])):
        c = canvas()
        c.fill_poly([(cx - 12, base), (cx + 12, base), (cx + 9, base - 22),
                     (cx - 9, base - 22)], PAL["sack"])
        c.fill_poly([(cx - 9, base - 22), (cx + 9, base - 22), (cx + 4, base - 30),
                     (cx - 4, base - 30)], shade(PAL["sack"], -0.2))
        for i in range(4):
            c.fill_circle(cx - 6 + i * 4, base - 12, 2.4, tint)
        c.outline()
        c.highlight_top()
        c.save(out_dir / ("%s.png" % name))

    # 铁锹
    c = canvas()
    c.thick_line((cx + 6, base - 32), (cx - 4, base - 6), PAL["wood"], 5)
    c.fill_poly([(cx - 12, base - 8), (cx + 4, base - 2), (cx + 2, base + 4),
                     (cx - 14, base - 2)], (0x9A, 0xA2, 0xAA))
    c.outline()
    c.highlight_top()
    c.save(out_dir / "tool_hoe.png")

    # 水桶
    c = canvas()
    c.fill_poly([(cx - 12, base - 22), (cx + 12, base - 22), (cx + 9, base),
                 (cx - 9, base)], (0x6E, 0x7C, 0x88))
    c.fill_rect(cx - 12, base - 24, cx + 12, base - 20, (0x8A, 0x98, 0xA4))
    c.thick_line((cx - 12, base - 24), (cx + 12, base - 24), INK, 2)
    c.outline()
    c.highlight_top()
    c.save(out_dir / "tool_bucket.png")

    # 镰刀
    c = canvas()
    c.thick_line((cx - 8, base - 2), (cx + 6, base - 28), PAL["wood"], 5)
    c.thick_line((cx + 6, base - 28), (cx + 14, base - 24), (0xB4, 0xBC, 0xC4), 4)
    c.thick_line((cx + 14, base - 24), (cx + 8, base - 16), (0xB4, 0xBC, 0xC4), 4)
    c.outline()
    c.highlight_top()
    c.save(out_dir / "tool_sickle.png")

    # 黏豆包
    c = canvas()
    c.fill_ellipse(cx, base - 12, 13, 11, (0xE0, 0xC8, 0x96))
    c.fill_ellipse(cx, base - 18, 7, 6, (0xE8, 0xD4, 0xA8))
    c.outline()
    c.highlight_top()
    c.save(out_dir / "food_sticky_bean_bun.png")

    # 酸菜(坛子)
    c = canvas()
    c.fill_ellipse(cx, base - 14, 13, 14, (0x9A, 0xA8, 0x7A))
    c.fill_rect(cx - 13, base - 26, cx + 13, base - 22, (0x7A, 0x88, 0x5A))
    c.outline()
    c.highlight_top()
    c.save(out_dir / "food_sour_cabbage.png")

    # 冻梨
    c = canvas()
    c.fill_ellipse(cx, base - 12, 11, 12, (0x5E, 0x3E, 0x34))
    c.thick_line((cx + 1, base - 24), (cx + 5, base - 32), PAL["wood"], 3)
    c.outline()
    c.highlight_top()
    c.save(out_dir / "food_frozen_pear.png")

    # 干玉米
    c = canvas()
    c.fill_ellipse(cx, base - 14, 10, 15, PAL["autumn"])
    for i in range(5):
        c.fill_rect(cx - 8, base - 26 + i * 6, cx + 8, base - 24 + i * 6, shade(PAL["autumn"], -0.22))
    c.outline()
    c.highlight_top()
    c.save(out_dir / "food_dried_corn.png")

    # 农家肥
    c = canvas()
    c.fill_ellipse(cx, base - 10, 15, 11, (0x6A, 0x56, 0x3A))
    for i in range(5):
        c.fill_circle(cx - 8 + i * 4, base - 14 + (i % 2) * 4, 2.6, PAL["grass_dark"])
    c.outline()
    c.highlight_top()
    c.save(out_dir / "material_fertilizer.png")

    # 大粒盐
    c = canvas()
    c.fill_ellipse(cx, base - 10, 13, 10, (0xD8, 0xD4, 0xC4))
    for i in range(6):
        c.fill_rect(cx - 9 + (i % 3) * 6, base - 16 + (i // 3) * 5,
                    cx - 5 + (i % 3) * 6, base - 12 + (i // 3) * 5, (0xF2, 0xF0, 0xE4))
    c.outline()
    c.highlight_top()
    c.save(out_dir / "material_salt.png")


# ---------------------------------------------------------------------------
# 背景分层(960×540)
# ---------------------------------------------------------------------------
BG_W = 960
BG_H = 540


def _sky(c, top, mid, low, sun_x=None, sun_y=None, cloud_seed=7):
    """黄昏天空:上蓝 → 中橙 → 地平线暖黄,加日轮、手绘云带与地平线雾霾。"""
    for y in range(BG_H):
        t = y / float(BG_H - 1)
        if t < 0.55:
            col = mix(top, mid, t / 0.55)
        else:
            col = mix(mid, low, (t - 0.55) / 0.45)
        c.fill_rect(0, y, BG_W, y + 1, col)
    rng = Rng(cloud_seed)
    if sun_x is not None:
        # 日轮 + 三层光晕(手绘感来自边缘的软过渡)
        c.fill_circle(sun_x, sun_y, 50, mix(mid, PAL["sun"], 0.20))
        c.fill_circle(sun_x, sun_y, 36, mix(mid, PAL["sun"], 0.40))
        c.fill_circle(sun_x, sun_y, 25, mix(PAL["sun"], (255, 255, 255), 0.16))
        c.fill_circle(sun_x, sun_y, 18, PAL["sun"])
    for i in range(6):
        cy = rng.uniform(46, 230)
        if sun_x is not None and abs(cy - sun_y) < 86:
            cy += 120 if cy < sun_y else -120
        cx = rng.uniform(30, BG_W - 30)
        w = rng.uniform(100, 210)
        h = rng.uniform(16, 26)
        cloud_col = mix(mid, PAL["sky_warm"], 0.55)
        # 多个 blob 叠成蓬松云带,而不是一条扁平伤疤
        for k in range(4):
            bx = cx + (k - 1.5) * w * 0.24
            by = cy + rng.uniform(-5, 5)
            c.fill_poly(blob(bx, by, w * 0.19, h * rng.uniform(0.8, 1.35),
                             rng, wobble=0.32, points=12), cloud_col)
    # 地平线雾霾:远景往天空色靠拢
    for i in range(40):
        y = 250 + i
        if y >= BG_H:
            break
        c.fill_rect(0, y, BG_W, y + 1, mix(mid, PAL["sky_warm"], 0.12 + i / 40.0 * 0.75))


def _far_layer(c, base_y, tint, seed=3, houses=True, street=False):
    """远景剪影层:树线 + 土房 + 篱笆。颜色向天空色靠拢(大气透视)。"""
    rng = Rng(seed)
    color = tint
    if houses:
        # 泥草房先画 —— 压在树线后面,靠大气透视后退一层
        house_color = mix(color, (0xE8, 0xC0, 0x8A), 0.30)
        for hx in (70, 210, 390, 560, 760, 900):
            hw = rng.uniform(34, 48)
            hh = rng.uniform(22, 30)
            roof_h = rng.uniform(13, 18)
            body = [(hx - hw, base_y + 4), (hx - hw, base_y - hh), (hx + hw, base_y - hh),
                    (hx + hw, base_y + 4)]
            c.fill_poly(body, house_color)
            roof = [(hx - hw - 6, base_y - hh), (hx, base_y - hh - roof_h),
                    (hx + hw + 6, base_y - hh)]
            c.fill_poly(roof, shade(house_color, -0.12))
            if street:
                # 门窗暖光,让镇大街有生活气
                c.fill_rect(hx - 7, base_y - hh + 7, hx - 2, base_y - hh + 14,
                            mix(color, PAL["sun"], 0.6))
                c.fill_rect(hx + 3, base_y - hh + 7, hx + 9, base_y - hh + 17,
                            mix(color, PAL["sun"], 0.45))
    # 树线:白桦/落叶松的挺拔剪影,后画所以压住房子
    for i in range(13):
        x = -30 + i * 78 + rng.uniform(-20, 20)
        h = rng.uniform(58, 118)
        conifer = rng.chance(0.45)
        canopies, trunk = tree_silhouette(x, base_y + 4, h, rng, spread=0.66,
                                          conifer=conifer)
        c.fill_poly(trunk, shade(color, -0.12))
        for poly in canopies:
            c.fill_poly(poly, color)
    # 篱笆:立在地面线上
    for i in range(36):
        x = i * 28 + rng.uniform(-4, 4)
        c.thick_line((x, base_y + 4), (x, base_y - 13), shade(color, -0.14), 3)


def _ground_layer(c, top_y, base_color, ridge_color, seed=11, furrows=False, road=False):
    """地面层:泥土基底 + 边缘过渡 + 黑土斑块(+ 土路)。"""
    rng = Rng(seed)
    # 1) 底色渐变:靠近地平线偏亮(受天光),往下沉成土色
    for y in range(top_y, BG_H):
        t = (y - top_y) / float(max(1, BG_H - top_y))
        col = mix(ridge_color, base_color, min(1.0, t * 1.6))
        c.fill_rect(0, y, BG_W, y + 1, col)
    # 2) 黑土斑块:土壤不能是一整块平涂
    for i in range(26):
        x = rng.uniform(0, BG_W)
        y = rng.uniform(top_y + 10, BG_H)
        c.fill_ellipse(x, y, rng.uniform(18, 46), rng.uniform(6, 13),
                       shade(base_color, rng.uniform(-0.09, 0.09)))
    # 3) 轻微起伏(地块贴图里已有犁沟,这里只做起伏免得打架)
    if furrows:
        for i in range(9):
            y = top_y + 26 + i * 34
            if y >= BG_H:
                break
            c.fill_rect(0, y, BG_W, y + 2, shade(base_color, -0.07 - (i % 3) * 0.01))
    # 4) 草丛与碎石
    for i in range(120):
        x = rng.uniform(0, BG_W)
        y = rng.uniform(top_y + 6, BG_H - 4)
        c.thick_line((x, y), (x + rng.uniform(-4, 4), y - rng.uniform(5, 13)),
                     PAL["grass_dark"], 2)
    # 5) 土路最后画:压住斑块与草丛,近处宽远处窄
    if road:
        for y in range(top_y, BG_H):
            t = (y - top_y) / float(max(1, BG_H - top_y))
            half = int(34 + t * 250)
            c.fill_rect(BG_W // 2 - half, y, BG_W // 2 + half, y + 1,
                        mix(PAL["mud_light"], PAL["sand"], 0.35))
            c.fill_rect(BG_W // 2 - half, y, BG_W // 2 - half + 10, y + 1,
                        shade(PAL["mud_light"], -0.18))
            c.fill_rect(BG_W // 2 + half - 10, y, BG_W // 2 + half, y + 1,
                        shade(PAL["mud_light"], -0.18))


def gen_backgrounds(out_dir):
    """农场 / 镇大街 各三层背景。"""
    out_dir.mkdir(parents=True, exist_ok=True)

    # —— 农场 ——
    c = Canvas(BG_W, BG_H)
    _sky(c, PAL["sky_hi"], PAL["sky_lo"], PAL["sky_warm"], sun_x=760, sun_y=96, cloud_seed=11)
    c.save(out_dir / "bg_farm_sky.png")

    c = Canvas(BG_W, BG_H)
    _far_layer(c, 264, mix(PAL["sky_lo"], INK, 0.52), seed=21, houses=True)
    c.save(out_dir / "bg_farm_far.png")

    c = Canvas(BG_W, BG_H)
    _ground_layer(c, 270, PAL["soil"], PAL["mud"], seed=31, furrows=True)
    c.save(out_dir / "bg_farm_ground.png")

    # —— 镇大街 ——
    c = Canvas(BG_W, BG_H)
    _sky(c, mix(PAL["sky_hi"], PAL["sky_warm"], 0.25), PAL["sky_lo"], PAL["sky_warm"],
         sun_x=180, sun_y=84, cloud_seed=41)
    c.save(out_dir / "bg_town_sky.png")

    c = Canvas(BG_W, BG_H)
    _far_layer(c, 262, mix(PAL["sky_lo"], INK, 0.46), seed=51, houses=True, street=True)
    c.save(out_dir / "bg_town_far.png")

    c = Canvas(BG_W, BG_H)
    _ground_layer(c, 268, PAL["mud"], PAL["mud_light"], seed=61, road=True)
    c.save(out_dir / "bg_town_ground.png")


# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------
def main(argv):
    root = Path(argv[1]) if len(argv) > 1 else Path("assets")
    root = root if root.is_absolute() else Path.cwd() / root
    gen_dir = root / "art" / "generated"
    sprites = root / "sprites"

    print("生成背景层 …")
    gen_backgrounds(gen_dir)
    print("生成角色精灵表 …")
    gen_character_sheet(HERO, sprites / "player_body.png")
    gen_character_sheet(HERO_F, sprites / "player_female.png")
    gen_character_sheet(XIAOFANG, sprites / "npc_zhangxiaofang.png")
    print("生成地块贴图 …")
    gen_plot_tiles(sprites / "plots")
    print("生成作物图 …")
    gen_crops(sprites / "crops")
    print("生成物品图标 …")
    gen_items(sprites / "items")
    print("完成。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
