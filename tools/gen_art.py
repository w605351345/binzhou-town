#!/usr/bin/env python3
"""《宾州小镇》美术资源生成器 —— 饥荒观感手绘像素资源。

沿用 tools/gen_sprites.py 的思路(纯标准库手写 PNG,零第三方依赖,CI 可复现),
但产出的是《视觉与平台升级设计》§3.2 定义的成套资源:

    assets/art/generated/bg_farm_sky.png      农场天空层   960×540
    assets/art/generated/bg_farm_far.png      农场远景层
    assets/art/generated/bg_farm_ground.png   农场地面层
    assets/art/generated/bg_town_*.png        镇大街三层
    assets/art/generated/bg_post_*.png        老邮局室内三层
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

# 控制台编码未必是 UTF-8(Windows 默认 cp1252),打印中文会抛 UnicodeEncodeError
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8", errors="replace")

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
HAN_SHOUYI = {
    "coat": (0x5D, 0x64, 0x5D), "coat_dark": (0x42, 0x49, 0x45),
    "pants": (0x3D, 0x40, 0x43), "boot": (0x25, 0x22, 0x1F),
    "skin": (0xD9, 0xB9, 0x9B), "hair": (0x8A, 0x87, 0x7D),
    "scarf": (0x7C, 0x54, 0x3C), "hat": (0x3D, 0x45, 0x49),
    "beard": (0xB8, 0xB2, 0xA4), "bag": (0x6B, 0x4D, 0x32), "hunch": True,
}
SUN_YUMEI = {
    "coat": (0x9B, 0x6B, 0x39), "coat_dark": (0x73, 0x4D, 0x29),
    "pants": (0x4E, 0x42, 0x38), "boot": (0x2B, 0x24, 0x1E),
    "skin": (0xE7, 0xC8, 0xAB), "hair": (0x3B, 0x2C, 0x26),
    "scarf": (0xC9, 0x9B, 0x59), "apron": (0xDF, 0xCF, 0xAD),
    "headscarf": (0x9E, 0x55, 0x3B), "wide": True,
}
ZHAO_CHANGHE = {
    "coat": (0x46, 0x57, 0x5E), "coat_dark": (0x30, 0x3D, 0x43),
    "pants": (0x3D, 0x35, 0x2E), "boot": (0x25, 0x20, 0x1A),
    "skin": (0xCF, 0xA8, 0x82), "hair": (0x33, 0x2D, 0x28),
    "scarf": (0x8E, 0x70, 0x44), "hat": (0x6B, 0x52, 0x35),
    "bag": (0x5C, 0x43, 0x2C), "tool": (0xB2, 0xB8, 0xBA),
    "wide": True,
}
LIN_XIAOMAN = {
    "coat": (0xD7, 0xD5, 0xC6), "coat_dark": (0xAE, 0xB4, 0xAB),
    "pants": (0x4A, 0x4E, 0x54), "boot": (0x2A, 0x27, 0x24),
    "skin": (0xEC, 0xCB, 0xAE), "hair": (0x2B, 0x25, 0x23),
    "scarf": (0x78, 0x8E, 0x92), "bag": (0x6C, 0x4D, 0x3A),
    "short_hair": True,
}
ZHOU_DESHUN = {
    "coat": (0x54, 0x39, 0x36), "coat_dark": (0x38, 0x26, 0x25),
    "pants": (0x32, 0x32, 0x35), "boot": (0x22, 0x1F, 0x1C),
    "skin": (0xD4, 0xB0, 0x8B), "hair": (0x9C, 0x98, 0x8C),
    "scarf": (0xB1, 0x8A, 0x4E), "hat": (0x30, 0x2C, 0x28),
    "beard": (0xC5, 0xC0, 0xB3), "cane": (0x6D, 0x4C, 0x2B),
    "hunch": True,
}

WINTER_NPC = {
    "zhang_xiaofang": {
        "coat": (0x78, 0x3F, 0x4B), "coat_dark": (0x50, 0x2D, 0x36),
        "pants": (0x39, 0x35, 0x3E), "boot": (0x28, 0x22, 0x1D),
        "skin": (0xE7, 0xC7, 0xAD), "hair": (0x31, 0x25, 0x22),
        "scarf": (0xD2, 0xBF, 0x92), "hat": (0x5B, 0x3A, 0x35),
        "apron": (0xD8, 0xCC, 0xB0),
    },
    "han_shouyi": {
        "coat": (0x45, 0x4E, 0x4E), "coat_dark": (0x2F, 0x36, 0x36),
        "pants": (0x34, 0x37, 0x39), "boot": (0x22, 0x1F, 0x1D),
        "skin": (0xD7, 0xB8, 0x9C), "hair": (0x91, 0x8D, 0x83),
        "scarf": (0x9C, 0x6C, 0x45), "hat": (0x35, 0x3D, 0x43),
        "beard": (0xC9, 0xC4, 0xB6), "bag": (0x58, 0x3E, 0x29), "hunch": True,
    },
    "sun_yumei": {
        "coat": (0x7B, 0x4E, 0x2D), "coat_dark": (0x57, 0x36, 0x24),
        "pants": (0x42, 0x38, 0x31), "boot": (0x28, 0x22, 0x1D),
        "skin": (0xEC, 0xCB, 0xAD), "hair": (0x38, 0x2B, 0x25),
        "scarf": (0xC6, 0x91, 0x56), "apron": (0xD8, 0xC9, 0xA8),
        "headscarf": (0x7D, 0x3D, 0x31), "wide": True,
    },
    "zhao_changhe": {
        "coat": (0x3A, 0x48, 0x51), "coat_dark": (0x27, 0x31, 0x37),
        "pants": (0x36, 0x2F, 0x2A), "boot": (0x22, 0x1E, 0x1A),
        "skin": (0xCD, 0xA7, 0x83), "hair": (0x30, 0x2A, 0x25),
        "scarf": (0xA3, 0x7A, 0x48), "hat": (0x5B, 0x48, 0x35),
        "bag": (0x54, 0x3D, 0x29), "tool": (0xB8, 0xBD, 0xBD), "wide": True,
    },
    "lin_xiaoman": {
        "coat": (0xC5, 0xC9, 0xBE), "coat_dark": (0x94, 0x9B, 0x96),
        "pants": (0x44, 0x49, 0x4F), "boot": (0x27, 0x24, 0x21),
        "skin": (0xEB, 0xC9, 0xAE), "hair": (0x2A, 0x24, 0x22),
        "scarf": (0x6E, 0x88, 0x92), "hat": (0x8B, 0x9E, 0xA2),
        "bag": (0x63, 0x47, 0x36),
    },
    "zhou_deshun": {
        "coat": (0x4A, 0x31, 0x30), "coat_dark": (0x30, 0x20, 0x20),
        "pants": (0x2E, 0x2E, 0x31), "boot": (0x1F, 0x1C, 0x1A),
        "skin": (0xD2, 0xAE, 0x89), "hair": (0xA2, 0x9D, 0x91),
        "scarf": (0xC0, 0x96, 0x50), "hat": (0x2B, 0x28, 0x25),
        "beard": (0xD0, 0xCB, 0xBD), "cane": (0x64, 0x45, 0x28), "hunch": True,
    },
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
    if "headscarf" in colors:
        c.fill_ellipse(ox, oy - 2, 11.5, 10.5, colors["headscarf"])
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
    if "short_hair" in colors:
        c.fill_ellipse(ox, oy - 7, 9.0, 3.5, colors["hair"])
    if "beard" in colors:
        c.fill_ellipse(ox, oy + 7, 7.5, 5.0, colors["beard"])
        c.fill_rect(ox - 6, oy + 3, ox - 3, oy + 5, colors["beard"])
        c.fill_rect(ox + 3, oy + 3, ox + 6, oy + 5, colors["beard"])
    if "hat" in colors:
        c.fill_ellipse(ox, oy - 7, 11.0, 4.2, colors["hat"])
        c.fill_rect(ox - 9, oy - 12, ox + 9, oy - 7, colors["hat"])
        c.fill_ellipse(ox + 2, oy - 8, 8.5, 1.7, shade(colors["hat"], -0.25))
    # 围巾(脖子)
    c.fill_ellipse(ox, oy + 10, 9.0, 4.5, colors["scarf"])


def draw_character(c, ox, oy, colors, frame, facing):
    """在画布 c 上画一帧角色。ox/oy = 角色脚底中心。

    比例基线(48×72 格):脚底 oy=66,头顶 y=8 —— 角色实高 58px,
    约为一块地(88px)的 2/3,视觉上"人站进地里"而不是"人比地大"。
    """
    bob = BOB[frame]
    if "hunch" in colors:
        bob += 3
    _legs(c, ox, oy + bob, colors, frame, facing)
    body_top = oy - 43 + bob
    body_bot = oy - 19 + bob
    half = 9.0 if facing == "side" else (15.0 if "wide" in colors else 13.0)
    if "hunch" in colors:
        body_top += 4
    if "cane" in colors:
        c.thick_line((ox + 16, oy - 34 + bob), (ox + 18, oy - 3),
                     colors["cane"], 4)
        c.fill_circle(ox + 16, oy - 35 + bob, 3.0, colors["cane"])
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
    if "bag" in colors:
        c.fill_rect(ox + half - 5, body_bot - 12, ox + half + 8, body_bot + 2,
                    colors["bag"])
        c.thick_line((ox - half + 3, body_top + 8), (ox + half - 3, body_bot - 12),
                     shade(colors["bag"], 0.12), 2)
    if "tool" in colors:
        c.thick_line((ox - half - 7, body_bot - 16), (ox - half - 11, body_bot - 2),
                     (0x6D, 0x4C, 0x2B), 4)
        c.fill_rect(ox - half - 16, body_bot - 21, ox - half - 5, body_bot - 16,
                    colors["tool"])


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
    """农场 / 镇大街 / 老邮局 各三层背景。"""
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

    # —— 老邮局室内 ——
    c = Canvas(BG_W, BG_H)
    _post_office_wall(c)
    c.save(out_dir / "bg_post_wall.png")

    c = Canvas(BG_W, BG_H)
    _post_office_far(c)
    c.save(out_dir / "bg_post_far.png")

    c = Canvas(BG_W, BG_H)
    _post_office_ground(c)
    c.save(out_dir / "bg_post_ground.png")


def _post_office_wall(c):
    """老邮局的墙:暖黄灰泥 + 深色护墙板,和镇上的泥草房区分开。"""
    wall_top = (0x9A, 0x82, 0x63)
    wall_bottom = (0x77, 0x61, 0x49)
    for y in range(BG_H):
        t = y / float(BG_H)
        c.fill_rect(0, y, BG_W, y + 1, mix(wall_top, wall_bottom, t * 0.72))

    # 顶梁与旧木护墙板
    c.fill_rect(0, 0, BG_W, 54, (0x4E, 0x38, 0x27))
    c.fill_rect(0, 54, BG_W, 61, (0x69, 0x4D, 0x35))
    c.fill_rect(0, 300, BG_W, 312, (0x5D, 0x43, 0x2D))
    c.fill_rect(0, 312, BG_W, BG_H, (0x69, 0x4D, 0x35))
    for x in range(0, BG_W, 64):
        c.fill_rect(x, 312, x + 2, BG_H, shade((0x69, 0x4D, 0x35), -0.12))
        c.fill_rect(x + 8, 320, x + 58, 326, shade((0x69, 0x4D, 0x35), 0.08))

    # 墙纸的细竖纹与岁月斑驳
    rng = Rng(73)
    for x in range(0, BG_W, 22):
        c.fill_rect(x, 62, x + 1, 300, shade(wall_top, rng.uniform(-0.08, 0.08)))
    for _ in range(90):
        x = rng.uniform(0, BG_W)
        y = rng.uniform(66, 296)
        c.fill_ellipse(x, y, rng.uniform(2, 8), rng.uniform(1, 3),
                       shade(wall_top, rng.uniform(-0.10, 0.08)))


def _post_office_far(c):
    """窗、邮包架、时钟和柜台:让玩家一眼看出这里是老邮局。"""
    ink = (0x34, 0x25, 0x1A)
    wood = (0x6B, 0x48, 0x2D)
    wood_light = (0x91, 0x67, 0x42)
    glass = (0x9F, 0xC1, 0xCF)

    # 左侧窗
    c.fill_rect(62, 104, 306, 274, ink)
    c.fill_rect(69, 111, 299, 267, glass)
    c.fill_rect(177, 111, 190, 267, wood)
    c.fill_rect(69, 184, 299, 195, wood)
    for y, col in ((128, (0xD7, 0xE6, 0xDA)), (152, (0xC2, 0xD9, 0xD5)),
                   (222, (0xB6, 0xCD, 0xC7))):
        c.fill_rect(72, y, 296, y + 3, col)
    # 窗外的白桦枝影
    c.thick_line((92, 260), (112, 120), (0x55, 0x5C, 0x45), 4)
    c.thick_line((112, 120), (96, 82), (0x55, 0x5C, 0x45), 3)
    c.thick_line((112, 120), (142, 88), (0x55, 0x5C, 0x45), 3)
    # 窗帘
    curtain = (0xA7, 0x63, 0x48)
    c.fill_poly([(55, 96), (108, 96), (92, 268), (58, 280)], shade(curtain, -0.12))
    c.fill_poly([(262, 96), (314, 96), (310, 280), (278, 268)], shade(curtain, -0.12))
    c.fill_rect(52, 92, 110, 100, wood_light)
    c.fill_rect(260, 92, 318, 100, wood_light)

    # 右侧邮包架
    c.fill_rect(352, 104, 714, 126, ink)
    c.fill_rect(358, 110, 708, 292, shade(wood, -0.12))
    for y in (168, 226, 284):
        c.fill_rect(352, y, 714, y + 9, wood_light)
        c.fill_rect(352, y + 9, 714, y + 13, ink)
    rng = Rng(83)
    for row_y in (126, 184, 242):
        for i in range(6):
            x = 374 + i * 54 + rng.uniform(-5, 5)
            w = rng.uniform(30, 43)
            h = rng.uniform(24, 34)
            col = mix((0xC8, 0xA1, 0x65), (0x8F, 0xB8, 0xDE), rng.uniform(0.0, 0.35))
            c.fill_rect(x, row_y + 38 - h, x + w, row_y + 38, shade(col, -0.08))
            c.fill_rect(x, row_y + 38 - h, x + w, row_y + 41 - h, shade(col, 0.18))
            c.thick_line((x + w * 0.2, row_y + 10), (x + w * 0.8, row_y + 10),
                         (0x6C, 0x50, 0x36), 2)

    # 邮戳时钟
    c.fill_circle(805, 154, 44, ink)
    c.fill_circle(805, 154, 38, (0xD9, 0xC9, 0xA3))
    c.fill_circle(805, 154, 31, (0xEC, 0xDF, 0xBE))
    c.thick_line((805, 154), (805, 130), ink, 4)
    c.thick_line((805, 154), (826, 164), ink, 4)
    c.fill_circle(805, 154, 5, (0x7D, 0x3F, 0x2B))

    # 柜台与邮件格
    c.fill_rect(728, 242, 916, 370, ink)
    c.fill_rect(736, 250, 908, 362, wood)
    c.fill_rect(730, 236, 914, 252, wood_light)
    for row in range(3):
        for col in range(4):
            x = 750 + col * 38
            y = 264 + row * 30
            c.fill_rect(x, y, x + 30, y + 22, shade((0xC8, 0xA1, 0x65), -0.08))
            c.fill_rect(x + 4, y + 5, x + 26, y + 8, shade((0xC8, 0xA1, 0x65), 0.12))
    c.fill_rect(762, 350, 882, 360, shade(wood, 0.10))

    # 窗光落在地板上的暖色
    c.fill_poly([(72, 272), (304, 272), (394, 366), (18, 366)], (0xE8, 0xC0, 0x8A, 38))


def _post_office_ground(c):
    """木地板与旧地毯;近处留出玩家走动的空间。"""
    ink = (0x34, 0x25, 0x1A)
    floor_top = (0x8A, 0x63, 0x42)
    floor_bottom = (0x57, 0x3C, 0x28)
    for y in range(326, BG_H):
        t = (y - 326) / float(BG_H - 326)
        c.fill_rect(0, y, BG_W, y + 1, mix(floor_top, floor_bottom, t * 0.70))
    # 透视木板:远密近疏
    for i in range(11):
        y = 330 + int((i / 10.0) ** 1.45 * 210)
        c.fill_rect(0, y, BG_W, y + 2, shade(floor_bottom, -0.10))
    for i in range(9):
        x = -120 + i * 148
        c.thick_line((x, 328), (x + 180, BG_H), shade(floor_bottom, 0.08), 2)

    # 旧地毯:暗红与土黄,边缘有磨损
    rug = (0x7E, 0x3F, 0x30)
    c.fill_rect(286, 356, 674, 522, ink)
    c.fill_rect(294, 362, 666, 514, rug)
    c.fill_rect(306, 374, 654, 502, shade(rug, -0.15))
    c.fill_rect(320, 388, 640, 488, mix(rug, (0xC8, 0xA1, 0x65), 0.22))
    for x in range(336, 630, 34):
        c.fill_rect(x, 404, x + 5, 472, mix((0xC8, 0xA1, 0x65), rug, 0.38))
    c.fill_rect(300, 510, 660, 514, shade(rug, -0.24))
    rng = Rng(97)
    for _ in range(80):
        x = rng.uniform(294, 666)
        y = rng.uniform(362, 514)
        c.fill_rect(x, y, x + rng.uniform(1, 4), y + 1,
                    shade(rug, rng.uniform(-0.18, 0.12)))


# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Task 9: 四季地形、地点道具、NPC 立绘与季节场景板
# ---------------------------------------------------------------------------
TILE = 256
SEASON_TINT = {
    "spring": {"grass": (0x67, 0x72, 0x45), "grass_dark": (0x4F, 0x5A, 0x3A),
               "moss": (0x5D, 0x6B, 0x3D), "dirt": (0x4F, 0x3D, 0x2D),
               "soil": (0x3B, 0x2B, 0x20), "road": (0x6D, 0x5A, 0x43),
               "plaza": (0x79, 0x68, 0x50), "sand": (0x9B, 0x83, 0x5D),
               "water": (0x45, 0x68, 0x72), "wall": (0x69, 0x57, 0x44),
               "floor_wood": (0x7A, 0x58, 0x3B), "floor_tile": (0x8A, 0x88, 0x79),
               "rug": (0x75, 0x35, 0x31), "stage_floor": (0x86, 0x5D, 0x35)},
    "summer": {"grass": (0x49, 0x63, 0x35), "grass_dark": (0x35, 0x4B, 0x2A),
               "moss": (0x42, 0x5B, 0x32), "dirt": (0x57, 0x42, 0x2D),
               "soil": (0x3B, 0x2A, 0x1E), "road": (0x78, 0x61, 0x43),
               "plaza": (0x83, 0x6D, 0x4E), "sand": (0xA9, 0x8D, 0x60),
               "water": (0x3D, 0x65, 0x70), "wall": (0x70, 0x5A, 0x43),
               "floor_wood": (0x80, 0x5A, 0x38), "floor_tile": (0x92, 0x8F, 0x7D),
               "rug": (0x7D, 0x38, 0x32), "stage_floor": (0x8F, 0x62, 0x36)},
    "autumn": {"grass": (0x7C, 0x6D, 0x3D), "grass_dark": (0x5D, 0x51, 0x31),
               "moss": (0x6B, 0x5D, 0x36), "dirt": (0x5C, 0x44, 0x2D),
               "soil": (0x3E, 0x2B, 0x1D), "road": (0x7C, 0x61, 0x43),
               "plaza": (0x8A, 0x70, 0x4D), "sand": (0xA8, 0x88, 0x59),
               "water": (0x4E, 0x62, 0x68), "wall": (0x71, 0x58, 0x3F),
               "floor_wood": (0x7D, 0x55, 0x35), "floor_tile": (0x8A, 0x83, 0x72),
               "rug": (0x72, 0x30, 0x2A), "stage_floor": (0x89, 0x59, 0x31)},
    "winter": {"grass": (0xA7, 0xB5, 0xBC), "grass_dark": (0x7E, 0x91, 0x9C),
               "moss": (0x91, 0xA1, 0xA7), "dirt": (0x6A, 0x66, 0x60),
               "soil": (0x47, 0x48, 0x47), "road": (0x9A, 0xA5, 0xA8),
               "plaza": (0xA7, 0xAC, 0xAA), "sand": (0xB4, 0xB4, 0xA8),
               "water": (0x8A, 0xA9, 0xB7), "wall": (0x5B, 0x50, 0x48),
               "floor_wood": (0x62, 0x47, 0x34), "floor_tile": (0x7A, 0x7D, 0x79),
               "rug": (0x5F, 0x2F, 0x2A), "stage_floor": (0x6A, 0x47, 0x2D)},
}


def _grass_tile(c, rng, season, base):
    blade_hi = {
        "spring": (0x9A, 0xA4, 0x62, 210),
        "summer": (0x83, 0x9A, 0x4D, 220),
        "autumn": (0xC3, 0x9E, 0x55, 210),
        "winter": (0xE2, 0xE8, 0xE7, 190),
    }[season]
    blade_lo = {
        "spring": (0x36, 0x43, 0x2C, 150),
        "summer": (0x27, 0x3E, 0x24, 160),
        "autumn": (0x65, 0x4E, 0x2C, 160),
        "winter": (0x55, 0x68, 0x71, 150),
    }[season]
    for _ in range(320):
        x, y = rng.uniform(1, TILE - 1), rng.uniform(3, TILE)
        h = rng.uniform(5, 15)
        lean = rng.uniform(-4, 4)
        c.thick_line((x, y), (x + lean, y - h), blade_lo if rng.chance(0.3) else base, 1)
        c.thick_line((x + 1, y), (x + lean + 1, y - h * 0.78), blade_hi, 1)
    if season == "spring":
        for _ in range(20):
            x, y = rng.uniform(8, TILE - 8), rng.uniform(8, TILE - 8)
            c.fill_ellipse(x, y, rng.uniform(6, 15), rng.uniform(1, 3),
                           (0xD8, 0xDC, 0xD4, rng.uniform(0.28, 0.58)))
        for _ in range(30):
            x, y = rng.uniform(8, TILE - 8), rng.uniform(8, TILE - 8)
            c.fill_circle(x, y, 2.0, (0xE7, 0xD7, 0x8D, 210))
    elif season == "summer":
        for _ in range(48):
            x, y = rng.uniform(8, TILE - 8), rng.uniform(8, TILE - 8)
            c.fill_circle(x, y, 1.8, (0xE3, 0xC7, 0x62, 220))
    elif season == "autumn":
        for _ in range(90):
            x, y = rng.uniform(2, TILE - 2), rng.uniform(2, TILE - 2)
            col = rng.pick([(0xC4, 0x7B, 0x35, 220), (0x9C, 0x51, 0x2D, 210),
                            (0xD7, 0xAF, 0x5D, 220)])
            c.fill_ellipse(x, y, rng.uniform(2, 4), rng.uniform(1, 2), col)
    elif season == "winter":
        for _ in range(52):
            x, y = rng.uniform(0, TILE), rng.uniform(0, TILE)
            c.fill_ellipse(x, y, rng.uniform(7, 20), rng.uniform(2, 5),
                           (0xF0, 0xF4, 0xF2, rng.uniform(0.25, 0.60)))
        for _ in range(18):
            x = rng.uniform(0, TILE)
            c.thick_line((x, rng.uniform(0, TILE)), (x + rng.uniform(-8, 8),
                         rng.uniform(0, TILE)), (0x55, 0x6D, 0x74, 70), 1)


def _soil_tile(c, rng, season, kind, base):
    if kind == "soil":
        # 田土：犁沟、碎土块和镇压后的硬边，专门给可耕作地块使用。
        furrow = shade(base, -0.15)
        ridge = shade(base, 0.12)
        for i in range(10):
            y = i * 14 + rng.uniform(-2, 2)
            c.fill_rect(0, y, TILE, y + 3, furrow)
            c.fill_rect(0, y + 3, TILE, y + 5, ridge)
        for _ in range(150):
            x, y = rng.uniform(0, TILE), rng.uniform(0, TILE)
            c.fill_ellipse(x, y, rng.uniform(2.0, 6.0), rng.uniform(1.0, 3.0),
                           shade(base, rng.uniform(-0.20, 0.17)))
    elif kind == "road":
        # 车辙土路：中间被车轮压实，两侧散着砾石和草屑。
        c.fill_rect(0, 0, TILE, TILE, shade(base, -0.03))
        for x in (54, 116, 182):
            c.fill_rect(x + rng.uniform(-4, 4), 0, x + 28, TILE, shade(base, -0.09))
            c.fill_rect(x + 4, 0, x + 6, TILE, shade(base, 0.07))
        for _ in range(260):
            x, y = rng.uniform(0, TILE), rng.uniform(0, TILE)
            c.fill_ellipse(x, y, rng.uniform(0.8, 2.8), rng.uniform(0.7, 2.0),
                           shade(base, rng.uniform(-0.22, 0.20)))
        for _ in range(36):
            x, y = rng.uniform(0, TILE), rng.uniform(0, TILE)
            c.thick_line((x, y), (x + rng.uniform(-3, 3), y - rng.uniform(3, 8)),
                         (0x5E, 0x6B, 0x39, 120), 1)
    elif kind == "dirt":
        # 院坝泥土：大片潮痕、草根与踩踏形成的深浅斑块。
        for _ in range(46):
            x, y = rng.uniform(0, TILE), rng.uniform(0, TILE)
            c.fill_ellipse(x, y, rng.uniform(10, 38), rng.uniform(5, 22),
                           shade(base, rng.uniform(-0.16, 0.12)))
        for _ in range(190):
            x, y = rng.uniform(0, TILE), rng.uniform(0, TILE)
            c.fill_ellipse(x, y, rng.uniform(1.0, 3.0), rng.uniform(0.8, 2.2),
                           shade(base, rng.uniform(-0.22, 0.18)))
        for _ in range(24):
            x, y = rng.uniform(0, TILE), rng.uniform(0, TILE)
            c.thick_line((x, y), (x + rng.uniform(-9, 9), y + rng.uniform(-5, 5)),
                         shade(base, -0.26), 1)
    else:
        # 河沙：细波纹与碎贝壳色颗粒。
        for i in range(14):
            y = i * 18 + rng.uniform(-4, 4)
            for x in range(0, TILE, 38):
                c.fill_ellipse(x + rng.uniform(-7, 7), y + rng.uniform(-3, 3),
                               rng.uniform(12, 27), rng.uniform(2, 5),
                               shade(base, rng.uniform(-0.10, 0.13)))
        for _ in range(100):
            x, y = rng.uniform(0, TILE), rng.uniform(0, TILE)
            c.fill_circle(x, y, rng.uniform(0.8, 2.2), shade(base, rng.uniform(-0.18, 0.22)))
    if season == "spring":
        for _ in range(22):
            x, y = rng.uniform(0, TILE), rng.uniform(0, TILE)
            c.fill_ellipse(x, y, rng.uniform(6, 16), rng.uniform(2, 5),
                           (0x35, 0x42, 0x44, rng.uniform(0.20, 0.38)))
        for _ in range(20):
            x, y = rng.uniform(0, TILE), rng.uniform(0, TILE)
            c.fill_ellipse(x, y, rng.uniform(4, 11), rng.uniform(1, 3),
                           (0xE1, 0xE4, 0xDB, rng.uniform(0.25, 0.52)))
    elif season == "autumn":
        for _ in range(46):
            x, y = rng.uniform(0, TILE), rng.uniform(0, TILE)
            c.fill_ellipse(x, y, 3.0, 1.4, (0xBF, 0x7D, 0x36, 190))
    elif season == "winter":
        for _ in range(36):
            x, y = rng.uniform(0, TILE), rng.uniform(0, TILE)
            c.fill_ellipse(x, y, rng.uniform(12, 28), rng.uniform(3, 7),
                           (0xDF, 0xE8, 0xEA, rng.uniform(0.42, 0.75)))


def _water_tile(c, rng, season, base):
    bands = {
        "spring": [(0x8C, 0xAA, 0xAC, 95), (0x2A, 0x4C, 0x55, 80)],
        "summer": [(0x99, 0xC8, 0xC2, 105), (0x24, 0x48, 0x53, 85)],
        "autumn": [(0x9C, 0xAC, 0xAF, 90), (0x34, 0x43, 0x4D, 80)],
        "winter": [(0xDB, 0xEA, 0xEE, 100), (0x67, 0x8F, 0xA1, 90)],
    }[season]
    for i in range(28):
        y = i * 9 + rng.uniform(-2, 2)
        c.fill_rect(0, y, TILE, y + 1, bands[0])
        c.fill_rect(0, y + 3, TILE, y + 4, bands[1])
    if season == "winter":
        for _ in range(16):
            x, y = rng.uniform(0, TILE), rng.uniform(0, TILE)
            c.thick_line((x, y), (x + rng.uniform(-18, 18), y + rng.uniform(-12, 12)),
                         (0x5D, 0x82, 0x91, 110), 1)


def _indoor_tile(c, rng, season, kind, base):
    if kind == "plaza":
        # 不规则石铺地：错缝、磨损、草缝与冬日薄雪。
        c.fill_rect(0, 0, TILE, TILE, shade(base, -0.10))
        row_h = 46
        for row in range(0, TILE // row_h + 1):
            y = row * row_h
            offset = -34 if row % 2 else 0
            for col in range(-1, TILE // 72 + 2):
                x = offset + col * 72
                w = rng.uniform(58, 80)
                inset = rng.uniform(2, 5)
                stone = shade(base, rng.uniform(-0.10, 0.13))
                c.fill_poly([(x + inset, y + inset), (x + w - inset, y + inset + 2),
                             (x + w - inset - 2, y + row_h - inset),
                             (x + inset + 3, y + row_h - inset - 1)], stone)
                c.fill_rect(x + 7, y + 7, x + w - 10, y + 9,
                            shade(stone, 0.10))
                if rng.chance(0.35):
                    cx = x + rng.uniform(14, w - 14)
                    c.thick_line((cx, y + 12), (cx + rng.uniform(-9, 9), y + 32),
                                 shade(stone, -0.20), 1)
        if season in ("spring", "summer"):
            for _ in range(34):
                x = rng.uniform(0, TILE)
                y = rng.uniform(0, TILE)
                c.thick_line((x, y), (x + rng.uniform(-3, 3), y - rng.uniform(4, 10)),
                             (0x6C, 0x7C, 0x43, 105), 1)
        if season == "autumn":
            for _ in range(26):
                c.fill_ellipse(rng.uniform(0, TILE), rng.uniform(0, TILE), 3, 1.5,
                               (0xB9, 0x77, 0x35, 160))
        if season == "winter":
            for _ in range(28):
                x, y = rng.uniform(0, TILE), rng.uniform(0, TILE)
                c.fill_ellipse(x, y, rng.uniform(7, 22), rng.uniform(2, 6),
                               (0xEE, 0xF3, 0xF2, rng.uniform(0.25, 0.60)))
    elif kind in ("wall", "floor_wood", "stage_floor"):
        for x in range(0, TILE, 18):
            c.fill_rect(x, 0, x + 1, TILE, shade(base, -0.12))
        for y in range(0, TILE, 34):
            c.fill_rect(0, y, TILE, y + 2, shade(base, -0.16))
        for _ in range(55):
            x, y = rng.uniform(0, TILE), rng.uniform(0, TILE)
            c.thick_line((x, y), (x + rng.uniform(5, 24), y),
                         shade(base, rng.uniform(-0.08, 0.11)), 1)
    elif kind == "floor_tile":
        for x in range(0, TILE, 32):
            c.fill_rect(x, 0, x + 1, TILE, shade(base, -0.11))
        for y in range(0, TILE, 32):
            c.fill_rect(0, y, TILE, y + 1, shade(base, -0.11))
        for _ in range(38):
            x, y = rng.uniform(0, TILE), rng.uniform(0, TILE)
            c.fill_circle(x, y, rng.uniform(1, 2.5), shade(base, -0.14))
    elif kind == "rug":
        for x in range(8, TILE, 22):
            c.fill_rect(x, 0, x + 4, TILE, shade(base, 0.18))
        c.fill_rect(0, 10, TILE, 14, shade(base, 0.12))
        c.fill_rect(0, TILE - 18, TILE, TILE - 14, shade(base, 0.12))
        for _ in range(60):
            x, y = rng.uniform(0, TILE), rng.uniform(0, TILE)
            c.fill_rect(x, y, x + rng.uniform(1, 3), y + 1,
                        shade(base, rng.uniform(-0.18, 0.12)))


def gen_terrain(out_dir: Path) -> None:
    """四季 × 地形 的 128×128 手绘贴图。"""
    out_dir.mkdir(parents=True, exist_ok=True)
    for season, palette in SEASON_TINT.items():
        for kind, base in palette.items():
            c = Canvas(TILE, TILE)
            c.fill_rect(0, 0, TILE, TILE, base)
            rng = Rng(zlib.crc32((season + kind).encode("utf-8")) & 0xFFFF)
            if kind in ("grass", "grass_dark", "moss"):
                _grass_tile(c, rng, season, base)
            elif kind in ("dirt", "soil", "road", "sand"):
                _soil_tile(c, rng, season, kind, base)
            elif kind == "water":
                _water_tile(c, rng, season, base)
            else:
                _indoor_tile(c, rng, season, kind, base)
            c.dry_brush(rng, 70, (255, 244, 218, 24), 0, 0, TILE, TILE, 8, 34, 1)
            c.dry_brush(rng, 52, (24, 18, 14, 28), 0, 0, TILE, TILE, 8, 36, 1)
            c.paper_grain(rng, chance=0.14, strength=9)
            c.save(out_dir / f"{season}_{kind}.png")


def _prop_outline(c: Canvas, kind: str) -> None:
    c.outline(INK, width=2, diagonal=True)
    c.highlight_top()
    rng = Rng(zlib.crc32(("prop:" + kind).encode("utf-8")) & 0xFFFF)
    c.dry_brush(rng, 34, (255, 241, 211, 26), 18, 24, 238, 238, 8, 34, 1)
    c.dry_brush(rng, 22, (32, 20, 13, 34), 18, 24, 238, 238, 6, 24, 1)
    c.paper_grain(rng, chance=0.20, strength=15)


def _draw_prop_art(c: Canvas, kind: str) -> None:
    """256×256 透明道具/地标母版。"""
    ink = INK
    wood, wood_d, wood_l = (0x75, 0x50, 0x31), (0x4A, 0x32, 0x21), (0xA3, 0x76, 0x49)
    wall, roof, metal = (0x9A, 0x81, 0x62), (0x4B, 0x31, 0x24), (0x6A, 0x74, 0x78)
    green, pale, red = (0x4A, 0x5E, 0x35), (0xD3, 0xC8, 0xAB), (0x83, 0x3E, 0x32)

    if kind in ("house", "building", "barn", "backstage"):
        # 东北木刻楞/泥草房：先立烟囱与石基，再压屋顶，最后做门窗和木构。
        is_barn = kind == "barn"
        wall_col = mix(wall, (0x78, 0x45, 0x37), 0.34) if is_barn else wall
        if kind == "backstage":
            wall_col = mix(wall, (0x4B, 0x39, 0x31), 0.46)

        # 烟囱与淡烟：只在轮廓上方加一点生活气，不画成现代工业烟柱。
        c.fill_rect(166, 18, 190, 66, (0x63, 0x4A, 0x3A))
        c.fill_rect(161, 15, 195, 24, (0x43, 0x34, 0x2C))
        c.fill_rect(169, 24, 187, 30, shade((0x63, 0x4A, 0x3A), 0.16))
        for cx, cy, r, a in ((177, 8, 10, 34), (188, -3, 13, 24), (201, -14, 16, 16)):
            c.fill_circle(cx, cy, r, (0xD9, 0xD3, 0xC3, a))

        # 墙体与木板缝：横向叠板 + 竖向立柱，避免整面平涂。
        c.fill_rect(38, 92, 218, 218, wall_col)
        c.fill_rect(38, 92, 218, 102, shade(wall_col, 0.12))
        for y in range(104, 212, 14):
            c.fill_rect(42, y, 214, y + 2, shade(wall_col, -0.10))
            c.fill_rect(42, y + 2, 214, y + 3, shade(wall_col, 0.06))
        for x in (56, 94, 162, 200):
            c.fill_rect(x, 102, x + 3, 210, shade(wall_col, -0.15))
        c.thick_line((42, 104), (42, 212), shade(wood_d, 0.08), 6)
        c.thick_line((214, 104), (214, 212), shade(wood_d, 0.08), 6)
        c.thick_line((42, 198), (214, 198), shade(wood_d, 0.04), 5)

        # 石砌地基：大小不一的石块，底部压暗。
        c.fill_rect(34, 208, 222, 228, (0x5B, 0x57, 0x4D))
        stone_rng = Rng(zlib.crc32(("foundation:" + kind).encode("utf-8")) & 0xFFFF)
        for x in range(38, 218, 22):
            c.fill_rect(x + 1, 211, x + 20, 224,
                        shade((0x78, 0x71, 0x61), stone_rng.uniform(-0.12, 0.10)))
        c.fill_rect(34, 222, 222, 228, (0x43, 0x3E, 0x36))

        # 大坡屋顶：层层木瓦，边缘有滴水檐和压脊。
        c.fill_poly([(24, 96), (128, 24), (232, 96)], shade(roof, 0.04))
        c.fill_poly([(34, 96), (128, 36), (222, 96)], roof)
        roof_rng = Rng(zlib.crc32(("roof:" + kind).encode("utf-8")) & 0xFFFF)
        for y in range(39, 95, 8):
            half = int(8 + (y - 36) * 1.72)
            c.fill_rect(128 - half, y, 128 + half, y + 2,
                        shade(roof, -0.16 if (y // 8) % 2 else -0.09))
            for x in range(128 - half + (7 if (y // 8) % 2 else 0), 128 + half, 17):
                c.fill_rect(x, y + 2, x + 1, min(95, y + 8),
                            shade(roof, roof_rng.uniform(-0.10, 0.10)))
        c.fill_poly([(34, 96), (128, 36), (222, 96), (216, 102),
                     (128, 44), (40, 102)], shade(roof, -0.28))
        c.thick_line((128, 26), (128, 47), shade(roof, 0.16), 5)

        # 窗：木框、窗棂、两侧旧布帘与窗台。
        for x in (58, 156):
            c.fill_rect(x - 5, 115, x + 47, 165, shade(wood_d, 0.06))
            c.fill_rect(x, 120, x + 42, 160, (0xE6, 0xB3, 0x5E))
            c.fill_rect(x + 3, 123, x + 39, 157, (0xF4, 0xD0, 0x79))
            c.fill_rect(x + 17, 123, x + 20, 157, shade(wood_d, 0.12))
            c.fill_rect(x + 3, 137, x + 39, 140, shade(wood_d, 0.12))
            c.fill_poly([(x + 3, 123), (x + 13, 123), (x + 9, 157), (x + 3, 157)],
                        (0x9D, 0x5B, 0x45, 150))
            c.fill_poly([(x + 29, 123), (x + 39, 123), (x + 39, 157), (x + 33, 157)],
                        (0x9D, 0x5B, 0x45, 150))
            c.fill_rect(x - 9, 164, x + 51, 170, shade(wood, 0.08))

        # 门：厚木板、门楣、铁合页和门槛。
        door_l, door_r = (92, 156) if is_barn else (108, 148)
        door_top = 132 if is_barn else 140
        c.fill_rect(door_l - 5, door_top - 5, door_r + 5, 218, shade(wood_d, 0.08))
        c.fill_rect(door_l, door_top, door_r, 214, shade(wood, 0.02))
        for x in range(door_l + 8, door_r, 11):
            c.fill_rect(x, door_top + 4, x + 2, 211, shade(wood_d, 0.10))
            c.fill_rect(x + 2, door_top + 4, x + 4, 211, shade(wood, 0.12))
        c.fill_rect(door_l + 5, door_top + 18, door_r - 5, door_top + 23, ink)
        c.fill_rect(door_l + 5, 184, door_r - 5, 189, ink)
        c.fill_rect(door_r - 14, 170, door_r - 9, 176, (0xB6, 0x8B, 0x42))
        c.fill_rect(door_l - 10, 212, door_r + 10, 220, shade(wood_l, -0.06))
        if is_barn:
            c.thick_line((door_l + 4, door_top + 10), (door_r - 4, 208), ink, 4)
            c.thick_line((door_r - 4, door_top + 10), (door_l + 4, 208), ink, 4)
        else:
            c.fill_rect(door_l + 9, door_top + 8, door_r - 9, door_top + 42,
                        (0xD8, 0xB1, 0x6B))
            c.fill_rect(door_l + 31, door_top + 8, door_r - 31, door_top + 42, wood_d)
            c.fill_rect(door_l + 9, door_top + 23, door_r - 9, door_top + 26, wood_d)

        # 门边小灯与柴堆，补足生活痕迹。
        c.fill_rect(78, 148, 88, 196, metal)
        c.fill_rect(73, 140, 93, 153, ink)
        c.fill_rect(77, 144, 89, 151, (0xE5, 0x9A, 0x48))
        c.fill_circle(83, 148, 9, (0xF5, 0xC9, 0x69, 48))
        if is_barn:
            for i in range(4):
                c.fill_ellipse(196 + i * 5, 224 - i * 6, 15, 7,
                               shade((0xB5, 0x91, 0x49), i * 0.04))
    elif kind in ("tree", "birch"):
        trunk = (0xD8, 0xD4, 0xC4) if kind == "birch" else (0x4B, 0x31, 0x21)
        canopy = (0x56, 0x68, 0x3A) if kind == "birch" else (0x3F, 0x54, 0x31)
        # 树干与根部：先画外扩的根盘，再收成主干，避免一根直棍。
        c.thick_line((128, 224), (124, 108), trunk, 21 if kind == "birch" else 18)
        c.thick_line((124, 218), (96, 232), shade(trunk, -0.12), 8)
        c.thick_line((126, 219), (158, 233), shade(trunk, -0.18), 7)
        c.thick_line((124, 116), (92, 92), shade(trunk, -0.10), 8)
        c.thick_line((125, 122), (162, 94), shade(trunk, -0.04), 7)
        c.thick_line((121, 136), (86, 132), shade(trunk, -0.14), 5)
        c.thick_line((127, 148), (170, 137), shade(trunk, -0.08), 5)
        if kind == "birch":
            for y in range(124, 218, 19):
                c.fill_rect(115, y, 129, y + 5, ink)
                c.fill_rect(120, y + 5, 127, y + 7, shade(trunk, -0.16))
        else:
            for y in range(128, 214, 16):
                c.thick_line((118, y), (123, y + 6), shade(trunk, 0.10), 2)
                c.thick_line((130, y + 4), (136, y + 11), shade(trunk, -0.18), 2)
        # 树冠由大小不一的团块组成，边缘用高光叶簇打散。
        clusters = (
            (91, 98, 42, -0.13), (158, 95, 45, -0.04), (126, 62, 51, 0.10),
            (108, 128, 35, -0.17), (153, 131, 31, -0.10), (127, 100, 43, 0.04),
        )
        for cx, cy, r, amount in clusters:
            c.fill_circle(cx, cy, r, shade(canopy, amount))
        for cx, cy, r, amount in ((78, 83, 19, 0.10), (137, 49, 23, 0.14),
                                  (177, 96, 20, 0.02), (117, 124, 16, 0.08)):
            c.fill_circle(cx, cy, r, shade(canopy, amount))
        prop_seed = zlib.crc32(kind.encode("utf-8"))
        for _ in range(30):
            c.fill_ellipse(72 + (prop_seed + _ * 13) % 112,
                           42 + (_ * 17) % 100, 5, 3,
                           shade(canopy, 0.18 if _ % 3 else -0.18))
    elif kind == "well":
        c.fill_ellipse(128, 185, 65, 25, (0x82, 0x89, 0x86))
        c.fill_rect(64, 145, 192, 185, (0x72, 0x79, 0x78))
        c.fill_ellipse(128, 145, 64, 22, (0x35, 0x3B, 0x3C))
        c.fill_ellipse(128, 145, 54, 16, (0x22, 0x2B, 0x31))
        c.thick_line((82, 145), (82, 63), wood, 10)
        c.thick_line((174, 145), (174, 63), wood, 10)
        c.fill_poly([(58, 76), (128, 34), (198, 76)], roof)
        c.thick_line((82, 78), (174, 78), wood_l, 8)
        c.thick_line((128, 78), (128, 116), (0x8C, 0x72, 0x4D), 3)
        c.fill_rect(117, 116, 139, 134, (0x5A, 0x3B, 0x28))
    elif kind in ("fence", "board", "sign", "lamp", "lantern"):
        if kind == "fence":
            for x in (56, 122, 188):
                c.fill_rect(x, 70, x + 14, 218, wood)
                c.fill_poly([(x, 70), (x + 7, 52), (x + 14, 70)], wood_l)
            for y in (94, 150):
                c.fill_rect(48, y, 208, y + 14, wood_l)
        elif kind in ("board", "sign"):
            c.fill_rect(114, 120, 142, 226, wood_d)
            c.fill_rect(44, 50, 212, 142, wood)
            c.fill_rect(55, 61, 201, 131, pale)
            for i in range(4):
                c.fill_rect(70, 75 + i * 13, 186 - i * 9, 78 + i * 13,
                            shade(pale, -0.20))
            c.fill_circle(72, 70, 5, red)
        elif kind == "lamp":
            c.fill_rect(121, 72, 135, 226, metal)
            c.fill_rect(98, 44, 158, 94, ink)
            c.fill_rect(104, 50, 152, 88, (0xE5, 0x9A, 0x48))
            c.fill_ellipse(128, 88, 30, 12, (0xF5, 0xC9, 0x69, 80))
        else:
            c.fill_rect(113, 40, 143, 57, metal)
            c.fill_rect(93, 58, 163, 178, red)
            c.fill_rect(101, 67, 155, 169, (0xC8, 0x69, 0x45))
            c.fill_rect(88, 174, 168, 187, ink)
            c.thick_line((128, 39), (128, 16), ink, 4)
    elif kind in ("dock", "boat", "reeds"):
        if kind == "dock":
            for x in range(26, 232, 22):
                c.fill_rect(x, 112, x + 18, 218, wood)
            for y in (130, 172):
                c.fill_rect(18, y, 238, y + 9, wood_d)
            c.fill_rect(54, 176, 64, 242, wood_l)
            c.fill_rect(192, 176, 202, 242, wood_l)
        elif kind == "boat":
            c.fill_poly([(30, 120), (226, 120), (184, 210), (72, 210)], wood)
            c.fill_poly([(44, 132), (212, 132), (181, 194), (75, 194)], wood_l)
            c.thick_line((54, 120), (54, 226), wood_d, 4)
        else:
            for i in range(22):
                x = 34 + i * 9
                h = 55 + (i * 37) % 105
                c.thick_line((x, 226), (x + 6, 226 - h), green, 2)
                c.fill_ellipse(x + 4, 190 - h // 3, 3, 7, shade(green, 0.18))
    elif kind in ("fallen_log", "mushroom_log", "woodpile", "lumber", "crate", "chest"):
        c.fill_ellipse(128, 190, 92, 30, wood)
        c.fill_rect(38, 168, 218, 196, wood)
        c.fill_ellipse(128, 166, 92, 30, wood_l)
        for x in (74, 112, 150, 188):
            c.fill_circle(x, 166, 11, shade(wood_l, 0.10))
            c.fill_circle(x, 166, 5, shade(wood_d, 0.15))
        if kind in ("mushroom_log", "fallen_log"):
            for x, y, r in ((94, 143, 13), (132, 135, 17), (168, 150, 10)):
                c.fill_rect(x - 3, y, x + 3, y + 22, pale)
                c.fill_ellipse(x, y, r, r * 0.48, (0xA5, 0x5A, 0x38))
        if kind in ("chest", "crate"):
            c.fill_rect(54, 96, 202, 194, wood)
            c.fill_rect(54, 123, 202, 140, metal)
            c.fill_rect(119, 120, 137, 154, (0xC7, 0x9C, 0x4B))
    elif kind in ("stage", "counter", "shelf", "desk", "table", "bench", "workbench", "bed", "exam_bed"):
        c.fill_rect(30, 104, 226, 193, wood)
        c.fill_rect(24, 94, 232, 113, wood_l)
        for x in (47, 197):
            c.fill_rect(x, 190, x + 15, 232, wood_d)
        if kind in ("bed", "exam_bed"):
            c.fill_rect(46, 113, 210, 176, (0xB8, 0xB5, 0xA0))
            c.fill_rect(46, 113, 90, 176, pale)
        if kind == "stage":
            c.fill_rect(20, 70, 236, 101, red)
            c.fill_rect(28, 81, 228, 94, shade(red, 0.18))
        if kind == "shelf":
            c.fill_rect(50, 62, 206, 94, wood_d)
            c.fill_rect(50, 202, 206, 228, wood_d)
        if kind == "workbench":
            c.fill_rect(72, 70, 120, 111, metal)
            c.thick_line((128, 74), (158, 54), wood_l, 6)
    elif kind in ("stove", "instrument", "calendar", "medicine_cabinet", "mailboxes", "shrine", "half_built", "saw"):
        if kind == "stove":
            c.fill_rect(58, 72, 198, 218, (0x4A, 0x50, 0x4D))
            c.fill_rect(76, 94, 180, 125, (0x2D, 0x32, 0x31))
            c.fill_circle(128, 166, 24, (0xE0, 0x7A, 0x35))
            c.fill_circle(128, 166, 12, (0xF3, 0xC0, 0x5E))
            c.fill_rect(103, 50, 153, 76, metal)
        elif kind == "instrument":
            c.fill_ellipse(128, 142, 66, 57, (0x9C, 0x3F, 0x2E))
            c.fill_ellipse(128, 142, 55, 46, (0xD6, 0xAF, 0x6B))
            c.fill_ellipse(128, 142, 33, 27, (0x7B, 0x36, 0x2B))
            c.thick_line((64, 210), (192, 210), wood_d, 8)
        elif kind == "calendar":
            c.fill_rect(48, 64, 208, 210, pale)
            c.fill_rect(48, 64, 208, 90, red)
            for row in range(5):
                for col in range(5):
                    c.fill_rect(61 + col * 28, 102 + row * 20, 78 + col * 28,
                                114 + row * 20, shade(pale, -0.12))
        elif kind in ("medicine_cabinet", "mailboxes"):
            c.fill_rect(48, 58, 208, 220, wood)
            for row in range(4):
                for col in range(3):
                    x, y = 62 + col * 47, 72 + row * 35
                    c.fill_rect(x, y, x + 38, y + 27, shade(pale, -0.08))
                    c.fill_rect(x + 5, y + 6, x + 33, y + 9, shade(wood_d, 0.10))
        elif kind == "shrine":
            for x, y, r in ((128, 64, 30), (88, 108, 34), (168, 108, 32), (128, 155, 48)):
                c.fill_ellipse(x, y, r, r * 0.82, (0x72, 0x74, 0x6D))
                c.fill_ellipse(x - 6, y - 8, r * 0.62, r * 0.48,
                               (0x8B, 0x8D, 0x84))
        elif kind == "saw":
            c.fill_poly([(48, 180), (204, 85), (218, 108), (78, 214)], metal)
            for i in range(10):
                x = 62 + i * 14
                c.fill_poly([(x, 184 - i * 6), (x + 7, 191 - i * 6),
                             (x + 12, 181 - i * 6)], metal)
        else:
            c.fill_rect(52, 132, 204, 218, wood)
            c.fill_rect(68, 74, 118, 138, wood_l)
            c.fill_rect(138, 96, 202, 145, wood)
            c.thick_line((56, 156), (208, 108), wood_l, 8)
    else:
        c.fill_rect(58, 80, 198, 214, wood)
        c.fill_rect(58, 80, 198, 94, wood_l)
        c.fill_rect(105, 132, 151, 214, wood_d)


PROP_NAMES = [
    "house", "building", "barn", "tree", "birch", "well", "woodpile", "fence",
    "dock", "board", "stall", "lamp", "counter", "shelf", "bed", "stove", "table",
    "chest", "calendar", "bench", "stage", "backstage", "instrument", "lantern",
    "fallen_log", "mushroom_log", "shrine", "reeds", "boat", "crate", "workbench",
    "exam_bed", "medicine_cabinet", "mailboxes", "desk", "lumber", "saw",
    "half_built", "sign", "sofa", "barrel", "tool_rack", "plow", "cart",
    "gravestone", "haystack", "water_trough", "fish_rack", "clothesline", "mud_puddle",
    "ice_block",
]


def gen_props(out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    for kind in PROP_NAMES:
        c = Canvas(256, 256)
        _draw_prop_art(c, kind)
        _prop_outline(c, kind)
        c.save(out_dir / f"{kind}.png")


PORTRAIT_PEOPLE = {
    "zhang_xiaofang": {"name": "张晓芳", "skin": (0xE1, 0xBC, 0x9E), "hair": (0x35, 0x27, 0x23),
                       "coat": (0x9B, 0x4C, 0x5B), "accent": (0xD5, 0xC9, 0xA9),
                       "style": "bun", "age_lines": True},
    "han_shouyi": {"name": "韩守义", "skin": (0xCA, 0xA8, 0x8A), "hair": (0xA9, 0xA5, 0x98),
                   "coat": (0x50, 0x5A, 0x59), "accent": (0x6E, 0x4B, 0x34),
                   "style": "postman", "age_lines": True},
    "sun_yumei": {"name": "孙玉梅", "skin": (0xE1, 0xBE, 0x9D), "hair": (0x3D, 0x2C, 0x25),
                  "coat": (0x8C, 0x5D, 0x32), "accent": (0x9A, 0x4C, 0x37),
                  "style": "headscarf", "age_lines": True},
    "zhao_changhe": {"name": "赵长河", "skin": (0xC7, 0xA0, 0x7C), "hair": (0x37, 0x2E, 0x27),
                     "coat": (0x3C, 0x50, 0x58), "accent": (0x6A, 0x4F, 0x32),
                     "style": "workcap", "age_lines": True},
    "lin_xiaoman": {"name": "林小满", "skin": (0xE8, 0xC5, 0xA5), "hair": (0x2D, 0x26, 0x24),
                    "coat": (0xD0, 0xD3, 0xC8), "accent": (0x6C, 0x86, 0x8B),
                    "style": "bob", "age_lines": False},
    "zhou_deshun": {"name": "周德顺", "skin": (0xC9, 0xA5, 0x80), "hair": (0xB8, 0xB3, 0xA3),
                    "coat": (0x50, 0x34, 0x32), "accent": (0xA9, 0x7D, 0x45),
                    "style": "opera", "age_lines": True},
}


def _organic_face(c, cx, cy, rx, ry, seed, skin):
    rng = Rng(seed)
    pts = []
    for i in range(28):
        a = math.tau * i / 28
        wobble = 1.0 + math.sin(i * 2.7 + seed) * 0.025 + rng.uniform(-0.012, 0.012)
        pts.append((cx + math.cos(a) * rx * wobble, cy + math.sin(a) * ry * wobble))
    c.fill_poly(pts, skin)
    return pts


def _portrait_background(c, npc_id, accent):
    rng = Rng(zlib.crc32(("portrait-bg:" + npc_id).encode("utf-8")) & 0xFFFF)
    for y in range(256):
        t = y / 255.0
        c.fill_rect(0, y, 256, y + 1, mix((0x42, 0x43, 0x39), (0x12, 0x15, 0x14), t))
    c.fill_circle(128, 118, 104, shade(accent, -0.56))
    c.fill_circle(128, 112, 88, mix(shade(accent, -0.36), (0x2A, 0x2D, 0x28), 0.38))
    c.dry_brush(rng, 80, (0xE2, 0xD3, 0xB2, 18), 0, 0, 256, 256, 14, 50, 2)
    c.dry_brush(rng, 55, (0x11, 0x0D, 0x0A, 28), 0, 0, 256, 256, 12, 46, 2)
    # 边角压暗，让中央人物从背景里提出来。
    for i in range(36):
        a = int(4 + i * 1.8)
        c.fill_rect(i, i, 256 - i, i + 1, (0x08, 0x08, 0x07, a))
        c.fill_rect(i, 255 - i, 256 - i, 256 - i, (0x08, 0x08, 0x07, a))


def _draw_portrait_figure(c, p, npc_id):
    """透明人物层：轮廓、体态与服饰都按角色分开画。"""
    skin = p["skin"]
    hair = p["hair"]
    coat = p["coat"]
    accent = p["accent"]
    style = p["style"]
    rng = Rng(zlib.crc32(("portrait-figure:" + npc_id).encode("utf-8")) & 0xFFFF)
    skin_shadow = shade(skin, -0.20)
    inkline = (0x24, 0x1A, 0x12, 255)
    red = (0x78, 0x36, 0x30, 255)

    # 肩背与衣领：宽窄、驼背和领口各自不同。
    shoulder = 40 if style in ("postman", "workcap", "opera") else 32
    c.fill_poly([(20, 256), (30, 218), (65 + shoulder // 3, 190),
                 (91, 176), (165, 176), (192, 190),
                 (226 - shoulder // 3, 218), (236, 256)], coat)
    c.fill_poly([(30, 256), (44, 218), (78, 198), (92, 256)], shade(coat, -0.12))
    c.fill_poly([(226, 256), (212, 218), (178, 198), (164, 256)], shade(coat, 0.06))
    c.fill_rect(105, 158, 151, 188, shade(skin, -0.13))

    if style == "postman":
        c.thick_line((84, 256), (156, 194), shade(accent, -0.18), 12)
        c.fill_rect(176, 207, 222, 256, accent)
        c.fill_rect(183, 214, 215, 220, shade(accent, 0.16))
    elif style == "opera":
        c.fill_poly([(76, 196), (106, 176), (128, 208), (150, 176), (180, 196),
                     (164, 256), (92, 256)], red)
        c.thick_line((128, 198), (128, 250), shade(red, -0.28), 4)
    elif style == "bob":
        c.fill_poly([(82, 190), (108, 176), (128, 196), (148, 176), (176, 190),
                     (160, 256), (96, 256)], shade(coat, -0.10))
        c.thick_line((90, 202), (116, 256), shade(coat, -0.30), 4)
        c.thick_line((166, 202), (140, 256), shade(coat, -0.30), 4)
    elif style == "headscarf":
        c.fill_poly([(78, 194), (104, 178), (128, 202), (152, 178), (178, 194),
                     (160, 256), (96, 256)], shade(accent, -0.12))
        c.fill_rect(108, 208, 148, 214, shade(accent, 0.18))
    else:
        c.fill_poly([(84, 192), (108, 176), (128, 200), (148, 176), (172, 192),
                     (158, 256), (98, 256)], shade(accent, -0.10))

    # 耳朵与脸。
    c.fill_ellipse(70, 119, 10, 19, skin_shadow)
    c.fill_ellipse(186, 119, 10, 19, skin_shadow)
    face_seed = zlib.crc32(npc_id.encode("utf-8"))
    _organic_face(c, 128, 116, 57, 66, face_seed, skin)
    c.fill_poly([(82, 88), (111, 72), (150, 74), (176, 91), (184, 115),
                 (171, 98), (145, 91), (108, 94)], shade(skin, 0.08))
    # 鼻梁与颧骨阴影。
    c.fill_ellipse(128, 136, 13, 23, shade(skin, 0.05))
    c.fill_ellipse(98, 132, 18, 11, (0xC7, 0x86, 0x77, 24))
    c.fill_ellipse(158, 132, 18, 11, (0xC7, 0x86, 0x77, 20))
    c.thick_line((128, 115), (125, 137), shade(skin, -0.24), 3)
    c.thick_line((125, 137), (135, 141), skin_shadow, 2)
    c.fill_ellipse(128, 151, 20, 7, shade(skin, -0.14))
    c.thick_line((113, 151), (143, 151), (0x6A, 0x34, 0x30, 220), 3)
    c.thick_line((118, 157), (138, 157), shade(skin, -0.27), 1)

    # 眼睛：上眼睑略压，眼神不完全对称。
    for ex, flip in ((104, -1), (152, 1)):
        c.fill_ellipse(ex, 113, 15, 9, (0xED, 0xDF, 0xC8))
        c.fill_ellipse(ex, 114, 8, 7, (0x4A, 0x35, 0x2A))
        c.fill_ellipse(ex + flip, 115, 4, 5, (0x1C, 0x17, 0x13))
        c.fill_circle(ex + 2, 111, 2.0, (0xF6, 0xEC, 0xD4, 230))
        c.thick_line((ex - 16, 104), (ex + 15, 106 - flip * 2), shade(hair, -0.10), 3)
        c.thick_line((ex - 14, 108), (ex + 14, 109), skin_shadow, 1)
    c.thick_line((121, 102), (135, 101), skin_shadow, 2)

    # 头发/帽子/头巾：用不同轮廓来区分人物。
    if style == "bun":
        c.fill_ellipse(128, 67, 61, 35, hair)
        c.fill_circle(128, 38, 26, hair)
        c.fill_circle(128, 38, 14, shade(hair, 0.10))
        c.fill_poly([(74, 88), (85, 50), (102, 138), (88, 154)], hair)
        c.fill_poly([(182, 88), (171, 50), (154, 138), (168, 154)], hair)
        c.fill_circle(75, 145, 3, (0xD5, 0xB0, 0x5B, 230))
        c.fill_circle(181, 145, 3, (0xD5, 0xB0, 0x5B, 230))
        c.thick_line((86, 73), (171, 72), shade(hair, 0.16), 3)
    elif style == "postman":
        c.fill_ellipse(128, 64, 60, 33, hair)
        c.fill_rect(73, 53, 183, 72, accent)
        c.fill_poly([(66, 71), (193, 71), (181, 88), (77, 88)], shade(accent, -0.16))
        c.fill_rect(70, 51, 186, 62, shade(accent, 0.10))
        c.fill_rect(115, 55, 141, 68, (0xD9, 0xC7, 0x91))
        c.fill_poly([(91, 143), (105, 164), (128, 177), (151, 164), (165, 143),
                     (151, 153), (128, 159), (105, 153)], hair)
        c.fill_ellipse(128, 148, 35, 22, hair)
        c.thick_line((117, 55), (121, 68), shade(accent, -0.25), 2)
    elif style == "headscarf":
        c.fill_ellipse(128, 64, 64, 38, shade(accent, -0.28))
        c.fill_poly([(55, 91), (72, 48), (111, 34), (149, 37), (190, 59),
                     (205, 93), (174, 77), (159, 62), (98, 62), (78, 80)], accent)
        c.fill_poly([(190, 85), (217, 118), (203, 143), (184, 110)], shade(accent, -0.10))
        c.thick_line((64, 84), (190, 86), shade(accent, 0.17), 3)
        c.fill_circle(96, 106, 2.5, (0xE1, 0xC5, 0x91, 175))
        c.fill_circle(160, 103, 2.5, (0xE1, 0xC5, 0x91, 175))
    elif style == "workcap":
        c.fill_ellipse(128, 66, 60, 33, hair)
        c.fill_rect(73, 57, 181, 72, accent)
        c.fill_ellipse(126, 58, 61, 22, accent)
        c.fill_poly([(65, 72), (193, 72), (185, 88), (72, 88)], shade(accent, -0.20))
        c.thick_line((163, 108), (183, 144), (0xD6, 0xB4, 0x6B, 230), 4)
        c.fill_circle(185, 148, 4, (0xE7, 0xC7, 0x6E, 220))
        c.fill_poly([(98, 145), (128, 176), (158, 145), (148, 160), (128, 170),
                     (108, 160)], shade(hair, -0.04))
    elif style == "bob":
        c.fill_ellipse(128, 64, 65, 35, hair)
        c.fill_poly([(62, 84), (83, 47), (105, 36), (151, 37), (178, 55),
                     (195, 91), (188, 145), (171, 151), (166, 93), (127, 76),
                     (89, 94), (85, 151), (68, 143)], hair)
        c.fill_ellipse(128, 92, 52, 20, shade(hair, 0.08))
        c.thick_line((85, 73), (170, 74), shade(hair, 0.18), 2)
        c.thick_line((112, 184), (104, 219), (0x3A, 0x3D, 0x3B), 5)
        c.thick_line((144, 184), (152, 219), (0x3A, 0x3D, 0x3B), 5)
        c.fill_circle(128, 206, 24, (0x55, 0x59, 0x58))
        c.fill_circle(128, 206, 16, (0xB9, 0xC4, 0xBE))
        c.fill_circle(128, 206, 8, (0x49, 0x59, 0x57))
    elif style == "opera":
        c.fill_ellipse(128, 66, 59, 34, hair)
        c.fill_rect(76, 53, 180, 71, shade(accent, -0.22))
        c.fill_rect(69, 67, 187, 80, inkline)
        c.fill_rect(74, 55, 182, 67, shade(accent, -0.06))
        c.fill_ellipse(128, 158, 42, 34, hair)
        c.fill_poly([(85, 137), (102, 191), (128, 224), (154, 191), (171, 137),
                     (151, 158), (128, 165), (105, 158)], hair)
        c.thick_line((107, 186), (118, 211), shade(hair, -0.16), 2)
        c.thick_line((149, 186), (138, 211), shade(hair, -0.16), 2)

    if p["age_lines"]:
        c.thick_line((91, 137), (106, 140), shade(skin, -0.24), 2)
        c.thick_line((150, 140), (165, 137), shade(skin, -0.24), 2)
        c.thick_line((94, 127), (108, 128), shade(skin, -0.18), 1)
        c.thick_line((148, 128), (162, 127), shade(skin, -0.18), 1)
        c.thick_line((118, 165), (138, 166), shade(skin, -0.20), 1)
    c.dry_brush(rng, 26, (255, 235, 205, 20), 40, 55, 215, 240, 8, 24, 1)
    c.paper_grain(rng, chance=0.20, strength=13)
    c.outline(inkline, width=2, diagonal=True)
    c.highlight_top((255, 244, 218, 42))


def gen_portraits(out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    for npc_id, p in PORTRAIT_PEOPLE.items():
        c = Canvas(256, 256)
        _portrait_background(c, npc_id, p["accent"])
        figure = Canvas(256, 256)
        _draw_portrait_figure(figure, p, npc_id)
        c.blit(figure, 0, 0)
        c.save(out_dir / f"{npc_id}.png")


def _board_base(c: Canvas, top, bottom, seed=97):
    for y in range(540):
        c.fill_rect(0, y, 960, y + 1, mix(top, bottom, (y / 539.0) ** 0.86))
    rng = Rng(seed)
    for _ in range(130):
        c.fill_ellipse(rng.uniform(0, 960), rng.uniform(12, 520),
                       rng.uniform(20, 110), rng.uniform(2, 6),
                       (0xEA, 0xDF, 0xC5, rng.uniform(0.025, 0.075)))
    c.dry_brush(rng, 160, (0xF5, 0xE9, 0xCE, 15), 0, 0, 960, 540, 30, 120, 2)
    c.dry_brush(rng, 95, (0x16, 0x12, 0x0E, 24), 0, 0, 960, 540, 24, 100, 2)


def _board_cloud(c, x, y, w, h, color):
    for dx, dy, rw, rh in ((-0.34, 0.08, 0.36, 0.70), (-0.08, -0.12, 0.40, 1.00),
                            (0.24, 0.00, 0.38, 0.80), (0.48, 0.10, 0.26, 0.56)):
        c.fill_ellipse(x + w * dx, y + h * dy, w * rw * 0.5, h * rh * 0.5, color)


def _board_birch(c, x, base_y, height, seed, leaf=None):
    rng = Rng(seed)
    top_x = x + rng.uniform(-16, 16)
    c.thick_line((x, base_y), (top_x, base_y - height), (0xD7, 0xD4, 0xC7), 9)
    c.thick_line((x + 3, base_y), (top_x + 3, base_y - height), (0xF0, 0xEC, 0xDD), 2)
    for i in range(8):
        y = base_y - 24 - i * (height - 40) / 8.0
        c.fill_rect(top_x + rng.uniform(-4, 2), y, top_x + rng.uniform(3, 7), y + 3,
                    (0x3A, 0x34, 0x2E, 220))
    for i in range(5):
        y = base_y - height * rng.uniform(0.45, 0.92)
        direction = -1 if i % 2 else 1
        c.thick_line((top_x, y), (top_x + direction * rng.uniform(25, 55), y - 34),
                     (0x4E, 0x42, 0x34), 3)
        if leaf is not None:
            c.fill_ellipse(top_x + direction * 38, y - 31, 24, 12, leaf)


def _board_house(c, x, y, w, h, wall, roof, snow=False):
    c.fill_rect(x, y, x + w, y + h, wall)
    c.fill_rect(x, y, x + 10, y + h, shade(wall, -0.18))
    c.fill_rect(x + w - 12, y, x + w, y + h, shade(wall, 0.06))
    c.fill_poly([(x - 18, y + 12), (x + w * 0.5, y - h * 0.52),
                 (x + w + 18, y + 12)], roof)
    c.fill_poly([(x - 18, y + 12), (x + w * 0.5, y - h * 0.52),
                 (x + w + 18, y + 12)], roof)
    if snow:
        c.fill_poly([(x - 22, y + 9), (x + w * 0.5, y - h * 0.56),
                     (x + w + 22, y + 9), (x + w + 2, y + 18),
                     (x + w * 0.5, y - h * 0.40), (x - 2, y + 18)],
                    (0xE4, 0xEB, 0xEC))
    c.fill_rect(x + w * 0.46, y + h * 0.48, x + w * 0.56, y + h, (0x27, 0x1A, 0x13))
    for wx in (x + w * 0.18, x + w * 0.70):
        c.fill_rect(wx, y + h * 0.28, wx + w * 0.14, y + h * 0.50, (0x35, 0x23, 0x19))
        c.fill_rect(wx + 4, y + h * 0.30, wx + w * 0.14 - 4, y + h * 0.47,
                    (0xEA, 0xB3, 0x59))
        c.fill_rect(wx + w * 0.07 - 1, y + h * 0.30, wx + w * 0.07 + 1,
                    y + h * 0.47, (0x5C, 0x3C, 0x25))


def _board_vignette(c):
    for i in range(34):
        a = int(3 + i * 1.2)
        c.fill_rect(i, i, 960 - i, i + 1, (0x0B, 0x09, 0x07, a))
        c.fill_rect(i, 539 - i, 960 - i, 540 - i, (0x0B, 0x09, 0x07, a))
        c.fill_rect(i, i, i + 1, 540 - i, (0x0B, 0x09, 0x07, a))
        c.fill_rect(959 - i, i, 960 - i, 540 - i, (0x0B, 0x09, 0x07, a))


def gen_season_boards(out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)

    # 春：冻土返浆、残雪、刚返青的柳枝与湿黑土。
    c = Canvas(960, 540)
    _board_base(c, (0x82, 0xA1, 0xAE), (0xD4, 0xC8, 0xA9), seed=101)
    _board_cloud(c, 180, 92, 250, 58, (0xEE, 0xE8, 0xD8, 118))
    _board_cloud(c, 690, 132, 210, 46, (0xE2, 0xDF, 0xD0, 96))
    c.fill_rect(0, 288, 960, 540, (0x43, 0x36, 0x2A))
    for i in range(14):
        c.fill_rect(0, 320 + i * 16, 960, 322 + i * 16, (0x66, 0x50, 0x38, 76))
    for x, y, rx, ry in ((135, 348, 98, 15), (420, 404, 142, 18), (720, 356, 86, 12),
                          (260, 474, 126, 17)):
        c.fill_ellipse(x, y, rx, ry, (0xCF, 0xD3, 0xC8, 180))
        c.fill_ellipse(x, y + 3, rx * 0.72, ry * 0.48, (0x7B, 0x7E, 0x73, 95))
    for x, y, rx, ry in ((58, 330, 58, 12), (805, 315, 106, 14), (590, 468, 76, 13)):
        c.fill_ellipse(x, y, rx, ry, (0x65, 0x44, 0x2F, 190))
    _board_house(c, 650, 182, 232, 164, (0x6C, 0x4D, 0x36), (0x38, 0x27, 0x20))
    c.fill_rect(742, 128, 766, 188, (0x3B, 0x2E, 0x27))
    for i in range(7):
        c.fill_circle(754 + i * 4, 119 - i * 10, 10 + i, (0xD9, 0xDE, 0xD9, 58 - i * 5))
    _board_birch(c, 90, 330, 168, 7, (0x7D, 0x8D, 0x4B, 165))
    _board_birch(c, 182, 346, 128, 9, (0x8C, 0x9D, 0x54, 150))
    for x in (28, 270, 330):
        c.thick_line((x, 350), (x, 286), (0x52, 0x3A, 0x28), 8)
    for y in (306, 330):
        c.thick_line((20, y), (346, y + 3), (0x76, 0x55, 0x36), 7)
    rng = Rng(103)
    for _ in range(220):
        x, y = rng.uniform(0, 960), rng.uniform(310, 536)
        c.thick_line((x, y), (x + rng.uniform(-3, 4), y - rng.uniform(5, 19)),
                     (0x8A, 0x96, 0x50, rng.uniform(0.38, 0.9)), 1)
    c.dry_brush(rng, 100, (0x2A, 0x1E, 0x15, 24), 0, 330, 960, 540, 24, 96, 2)
    _board_vignette(c)
    c.save(out_dir / "season_spring.png")

    # 夏：河岸强光、深绿芦苇、旧木码头与缓慢发亮的水面。
    c = Canvas(960, 540)
    _board_base(c, (0x69, 0x97, 0xB0), (0xDD, 0xC8, 0x8F), seed=201)
    c.fill_circle(790, 96, 39, (0xF5, 0xE4, 0xAA, 230))
    c.fill_circle(790, 96, 64, (0xF2, 0xD8, 0x93, 36))
    _board_cloud(c, 250, 86, 250, 54, (0xEE, 0xE9, 0xDA, 110))
    c.fill_poly([(0, 286), (170, 252), (365, 274), (520, 246), (728, 270),
                 (960, 242), (960, 330), (0, 330)], (0x3E, 0x55, 0x32))
    for x in range(20, 950, 48):
        h = 50 + (x * 17) % 88
        c.fill_ellipse(x, 288 - h * 0.22, 24, h * 0.35, (0x3A, 0x53, 0x31))
    c.fill_rect(0, 316, 960, 470, (0x3D, 0x64, 0x70))
    for y in range(328, 466, 12):
        c.fill_rect(0, y, 960, y + 2, (0x91, 0xB7, 0xB4, 70))
        if y % 36 == 4:
            c.dry_brush(Rng(y), 8, (0xD3, 0xDF, 0xD0, 65), 80, y, 880, y + 4, 20, 120, 2)
    c.fill_rect(0, 464, 960, 540, (0x4C, 0x60, 0x36))
    c.fill_poly([(238, 324), (500, 312), (530, 372), (210, 384)], (0x71, 0x4D, 0x31))
    for y in (334, 354, 374):
        c.fill_rect(214 if y > 365 else 224, y, 526 if y > 365 else 515, y + 7,
                    (0x4D, 0x34, 0x23))
    c.thick_line((252, 382), (238, 500), (0x4A, 0x31, 0x21), 12)
    c.thick_line((502, 372), (524, 494), (0x4A, 0x31, 0x21), 12)
    c.fill_poly([(92, 406), (252, 392), (224, 445), (112, 452)], (0x5C, 0x3E, 0x28))
    c.fill_poly([(108, 414), (238, 401), (218, 432), (120, 438)], (0x8D, 0x66, 0x40))
    for x in range(8, 960, 18):
        h = 34 + (x * 11) % 92
        c.thick_line((x, 526), (x + 6, 526 - h), (0x4F, 0x69, 0x35), 3)
    for x in (682, 714, 870):
        c.thick_line((x, 478), (x + 2, 300), (0x4B, 0x35, 0x24), 6)
        c.fill_ellipse(x, 286, 46, 20, (0x3B, 0x54, 0x32))
    rng = Rng(211)
    for _ in range(110):
        x, y = rng.uniform(0, 960), rng.uniform(450, 536)
        c.thick_line((x, y), (x + rng.uniform(-5, 5), y - rng.uniform(12, 38)),
                     (0x6F, 0x85, 0x40, 190), 2)
    c.dry_brush(rng, 80, (0xED, 0xE4, 0xB9, 24), 0, 280, 960, 540, 24, 92, 2)
    _board_vignette(c)
    c.save(out_dir / "season_summer.png")

    # 秋：玉米楼子、金色茬地、初霜与低角度灰蓝天光。
    c = Canvas(960, 540)
    _board_base(c, (0x73, 0x87, 0x96), (0xD0, 0xAF, 0x70), seed=301)
    _board_cloud(c, 260, 92, 300, 58, (0xD7, 0xD3, 0xC5, 100))
    c.fill_poly([(0, 298), (180, 270), (330, 288), (520, 264), (740, 282),
                 (960, 260), (960, 330), (0, 330)], (0x6B, 0x5B, 0x38))
    c.fill_rect(0, 306, 960, 540, (0xA0, 0x7D, 0x3D))
    for i in range(15):
        c.fill_rect(0, 328 + i * 15, 960, 331 + i * 15, (0x78, 0x5A, 0x2D, 95))
    for x in range(-20, 980, 42):
        h = 104 + (x * 7) % 72
        c.thick_line((x, 490), (x + 8, 490 - h), (0x6A, 0x56, 0x27), 5)
        c.fill_ellipse(x + 10, 490 - h + 10, 10, 28, (0xCD, 0xA1, 0x4A))
        c.fill_ellipse(x - 3, 458, 16, 6, (0x9E, 0x78, 0x30, 230))
    _board_house(c, 684, 186, 194, 162, (0x5F, 0x42, 0x2D), (0x3B, 0x28, 0x20))
    c.fill_rect(556, 222, 662, 442, (0x6B, 0x49, 0x29))
    for y in range(242, 424, 23):
        c.fill_rect(562, y, 656, y + 5, (0x38, 0x26, 0x1A))
        for x in range(574, 650, 15):
            c.fill_ellipse(x, y - 6, 6, 10, (0xD7, 0xAD, 0x51))
    c.fill_poly([(540, 430), (680, 430), (648, 520), (570, 520)], (0x8F, 0x46, 0x2C))
    c.fill_ellipse(604, 428, 66, 14, (0xE0, 0xBC, 0x55))
    for x, y in ((112, 424), (380, 490), (830, 462)):
        c.fill_ellipse(x, y, 86, 11, (0xD8, 0xDA, 0xCF, 120))
    for _ in range(180):
        x, y = 8 + (_ * 79) % 940, 330 + (_ * 37) % 194
        c.fill_ellipse(x, y, 4, 2, (0xC2, 0x7C, 0x33, 170))
    for _ in range(110):
        x, y = 10 + (_ * 67) % 940, 320 + (_ * 41) % 200
        c.thick_line((x, y), (x + 3, y - 13), (0x88, 0x6E, 0x34, 180), 2)
    _board_vignette(c)
    c.save(out_dir / "season_autumn.png")

    # 冬：雪青天光、暖窗、烟囱白烟、冰路与黑桦枝影。
    c = Canvas(960, 540)
    _board_base(c, (0x60, 0x7A, 0x8C), (0xAD, 0xBD, 0xC5), seed=401)
    _board_cloud(c, 220, 88, 340, 52, (0xBF, 0xCB, 0xD1, 92))
    _board_cloud(c, 660, 130, 220, 38, (0xB0, 0xBF, 0xC8, 70))
    c.fill_poly([(0, 304), (168, 272), (336, 294), (505, 268), (700, 290),
                 (960, 262), (960, 326), (0, 326)], (0x77, 0x89, 0x90))
    c.fill_rect(0, 310, 960, 540, (0xC2, 0xCF, 0xD3))
    for i in range(16):
        c.fill_rect(0, 330 + i * 14, 960, 333 + i * 14, (0xDC, 0xE5, 0xE7, 72))
    c.fill_ellipse(460, 468, 370, 62, (0x9E, 0xB8, 0xC3, 120))
    c.fill_ellipse(460, 468, 322, 42, (0xCB, 0xDC, 0xE1, 150))
    for _ in range(14):
        x, y = 60 + (_ * 61) % 820, 420 + (_ * 19) % 86
        c.thick_line((x, y), (x + 42, y - 14), (0x89, 0xA2, 0xAC, 95), 2)
    _board_house(c, 466, 192, 286, 174, (0x61, 0x4B, 0x3C), (0x33, 0x2C, 0x2A), snow=True)
    _board_house(c, 126, 242, 192, 132, (0x57, 0x45, 0x38), (0x30, 0x2A, 0x28), snow=True)
    c.fill_rect(610, 132, 636, 198, (0x39, 0x31, 0x2D))
    for i in range(10):
        c.fill_circle(622 + i * 4, 118 - i * 10, 8 + i, (0xE4, 0xE8, 0xE7, 74 - i * 4))
    _board_birch(c, 834, 392, 218, 41, None)
    _board_birch(c, 890, 410, 158, 43, None)
    for x in (62, 92):
        c.thick_line((x, 374), (x + 2, 240), (0x3D, 0x35, 0x31), 8)
        c.fill_ellipse(x, 228, 46, 19, (0xA8, 0xB5, 0xB7))
    for x, y, rx, ry in ((70, 470, 132, 22), (796, 492, 112, 18), (280, 360, 96, 15)):
        c.fill_ellipse(x, y, rx, ry, (0xF0, 0xF4, 0xF4, 150))
    rng = Rng(411)
    for _ in range(220):
        c.fill_circle(rng.uniform(0, 960), rng.uniform(16, 526), rng.uniform(1.4, 4.0),
                      (0xF5, 0xF8, 0xF8, rng.uniform(0.35, 0.88)))
    c.dry_brush(rng, 80, (0xE8, 0xEF, 0xF0, 30), 0, 300, 960, 540, 28, 110, 2)
    _board_vignette(c)
    c.save(out_dir / "season_winter.png")


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
    npc_dir = sprites / "npcs"
    npc_dir.mkdir(parents=True, exist_ok=True)
    for npc_id, palette in (
        ("zhang_xiaofang", XIAOFANG), ("han_shouyi", HAN_SHOUYI),
        ("sun_yumei", SUN_YUMEI), ("zhao_changhe", ZHAO_CHANGHE),
        ("lin_xiaoman", LIN_XIAOMAN), ("zhou_deshun", ZHOU_DESHUN),
    ):
        gen_character_sheet(palette, npc_dir / f"npc_{npc_id}.png")
        gen_character_sheet(WINTER_NPC[npc_id], npc_dir / f"npc_{npc_id}_winter.png")
    print("生成地块贴图 …")
    gen_plot_tiles(sprites / "plots")
    print("生成作物图 …")
    gen_crops(sprites / "crops")
    print("生成物品图标 …")
    gen_items(sprites / "items")
    print("生成四季地形 …")
    gen_terrain(gen_dir / "terrain")
    print("生成地点道具 …")
    gen_props(gen_dir / "props")
    print("生成 NPC 立绘 …")
    gen_portraits(root / "art" / "portraits")
    print("生成四季场景板 …")
    gen_season_boards(root / "art" / "concept")
    print("完成。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
