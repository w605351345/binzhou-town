#!/usr/bin/env python3
"""手写像素绘图基元库 —— 《宾州小镇》美术资源生成的地基。

为什么不用 PIL/Pillow:CI 与开发机都不保证有第三方库,项目坚持零依赖,
所以这里手写 PNG 编码器 + 一套够用的绘图基元,沿用 tools/gen_sprites.py 的套路。

观感目标(对齐《饥荒》家族):
  · 粗描边(暖黑 #241A12,2–3px),不画纯黑
  · 有限色盘(每场景 8–12 色,低饱和暖调)
  · 有机轮廓(贝塞尔 + 噪声扰动,禁用纯圆纯方)
  · 纸片分层(天空 → 远景 → 中景 → 地面,远景向天空色靠拢)
  · 实心阴影 + 上缘高光 / 下缘暗部
"""
import math
import struct
import zlib
from pathlib import Path

# --- 《饥荒》式暖黑描边 ---
INK = (0x24, 0x1A, 0x12, 255)


# --------------------------------------------------------------------------
# 颜色工具
# --------------------------------------------------------------------------
def rgb(r, g, b, a=255):
    return (r, g, b, a)


def _rgba(c):
    """3 元组补成 4 元组,方便直接用十六进制色板。"""
    return c if len(c) >= 4 else (c[0], c[1], c[2], 255)


def mix(c1, c2, t):
    """线性混色,t ∈ [0,1]。"""
    c1 = _rgba(c1)
    c2 = _rgba(c2)
    t = max(0.0, min(1.0, t))
    return tuple(int(round(c1[i] + (c2[i] - c1[i]) * t)) for i in range(4))


def shade(c, amount):
    """amount > 0 提亮,amount < 0 压暗(朝暖黑偏)。"""
    c = _rgba(c)
    if amount >= 0:
        return mix(c, (255, 250, 235, c[3]), amount)
    return mix(c, INK[:3] + (c[3],), -amount)


def with_alpha(c, a):
    return (c[0], c[1], c[2], a)


class Rng:
    """确定性随机(同一 seed 同一结果,保证 CI 可复现)。"""

    def __init__(self, seed=0):
        self.state = (seed * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFF

    def next(self):
        self.state = (self.state * 1664525 + 1013904223) & 0xFFFFFFFF
        return self.state

    def rand(self):
        return self.next() / 0xFFFFFFFF

    def uniform(self, lo, hi):
        return lo + (hi - lo) * self.rand()

    def chance(self, p):
        return self.rand() < p

    def pick(self, seq):
        return seq[self.next() % len(seq)]


# --------------------------------------------------------------------------
# 画布
# --------------------------------------------------------------------------
class Canvas:
    """RGBA 像素画布,提供填充/描边/描线/高光等基元。"""

    def __init__(self, width, height, fill=None):
        self.w = width
        self.h = height
        self.px = [[(0, 0, 0, 0)] * width for _ in range(height)]

    # -- 基础 --
    def set(self, x, y, color):
        color = _rgba(color)
        x = int(x)
        y = int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            if color[3] >= 255:
                self.px[y][x] = color
            elif color[3] > 0:
                old = self.px[y][x]
                a = color[3] / 255.0
                self.px[y][x] = (
                    int(color[0] * a + old[0] * (1 - a)),
                    int(color[1] * a + old[1] * (1 - a)),
                    int(color[2] * a + old[2] * (1 - a)),
                    max(color[3], old[3]),
                )

    def get(self, x, y):
        x = int(x)
        y = int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[y][x]
        return (0, 0, 0, 0)

    def alpha_at(self, x, y):
        return self.get(x, y)[3]

    # -- 填充 --
    def fill_rect(self, x0, y0, x1, y1, color):
        for y in range(int(y0), int(y1)):
            for x in range(int(x0), int(x1)):
                self.set(x, y, color)

    def fill_ellipse(self, cx, cy, rx, ry, color):
        for y in range(int(cy - ry), int(cy + ry) + 1):
            for x in range(int(cx - rx), int(cx + rx) + 1):
                nx = (x - cx) / max(rx, 0.001)
                ny = (y - cy) / max(ry, 0.001)
                if nx * nx + ny * ny <= 1.0:
                    self.set(x, y, color)

    def fill_circle(self, cx, cy, r, color):
        self.fill_ellipse(cx, cy, r, r, color)

    def fill_poly(self, points, color):
        """扫描线填充多边形(偶奇规则)。points = [(x,y), ...]"""
        if len(points) < 3:
            return
        ys = [p[1] for p in points]
        y_min = max(0, int(math.floor(min(ys))))
        y_max = min(self.h - 1, int(math.ceil(max(ys))))
        n = len(points)
        for y in range(y_min, y_max + 1):
            scan = y + 0.5
            xs = []
            for i in range(n):
                x1, y1 = points[i]
                x2, y2 = points[(i + 1) % n]
                if y1 == y2:
                    continue
                if (y1 <= scan < y2) or (y2 <= scan < y1):
                    t = (scan - y1) / (y2 - y1)
                    xs.append(x1 + (x2 - x1) * t)
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                for x in range(int(math.floor(xs[i])), int(math.ceil(xs[i + 1]))):
                    self.set(x, y, color)

    def stroke_poly(self, points, color, width=2):
        """多边形描边(沿线段画粗线)。"""
        n = len(points)
        for i in range(n):
            self.line(points[i], points[(i + 1) % n], color, width)

    def line(self, p0, p1, color, width=1):
        x0, y0 = p0
        x1, y1 = p1
        dx = x1 - x0
        dy = y1 - y0
        length = math.hypot(dx, dy)
        if length < 0.0001:
            self.set(x0, y0, color)
            return
        steps = int(length * 2) + 1
        for i in range(steps + 1):
            t = i / steps
            self.set(x0 + dx * t, y0 + dy * t, color)

    def thick_line(self, p0, p1, color, width=3):
        """带圆头的粗线 —— 画枝干、篱笆、垄沟。"""
        x0, y0 = p0
        x1, y1 = p1
        dx = x1 - x0
        dy = y1 - y0
        length = math.hypot(dx, dy)
        if length < 0.0001:
            self.fill_circle(x0, y0, width / 2.0, color)
            return
        nx = -dy / length * (width / 2.0)
        ny = dx / length * (width / 2.0)
        self.fill_poly([
            (x0 + nx, y0 + ny), (x1 + nx, y1 + ny),
            (x1 - nx, y1 - ny), (x0 - nx, y0 - ny),
        ], color)
        self.fill_circle(x0, y0, width / 2.0, color)
        self.fill_circle(x1, y1, width / 2.0, color)

    # -- 后处理 --
    def outline(self, color=INK, alpha_threshold=8, diagonal=False, width=1):
        """外描边:给所有不透明像素的外邻域涂描边色。

        width=2 即两圈 —— 饥荒风的粗描边(2–3px)靠这个。
        """
        offsets = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        if diagonal:
            offsets += [(-1, -1), (1, -1), (-1, 1), (1, 1)]
        for _ in range(max(1, width)):
            targets = []
            for y in range(self.h):
                for x in range(self.w):
                    if self.alpha_at(x, y) > alpha_threshold:
                        continue
                    for dx, dy in offsets:
                        if self.alpha_at(x + dx, y + dy) > alpha_threshold:
                            targets.append((x, y))
                            break
            for x, y in targets:
                self.set(x, y, color)

    def drop_shadow(self, cx, cy, rx, ry, color=(0, 0, 0, 55)):
        """脚底椭圆软阴影。"""
        for i in range(3):
            k = 1.0 - i * 0.28
            self.fill_ellipse(cx, cy + i, rx * k, ry * k,
                             (color[0], color[1], color[2], int(color[3] * (1 - i * 0.25))))

    def highlight_top(self, color=(255, 246, 220, 70)):
        """上缘 1px 高光 —— 手绘笔触的关键。"""
        for y in range(self.h):
            for x in range(self.w):
                if self.alpha_at(x, y) > 8 and self.alpha_at(x, y - 1) <= 8:
                    self.set(x, y, color)

    def shade_bottom(self, color=(0x24, 0x1A, 0x12, 60)):
        """下缘暗部。"""
        for y in range(self.h):
            for x in range(self.w):
                if self.alpha_at(x, y) > 8 and self.alpha_at(x, y + 1) <= 8:
                    self.set(x, y, color)

    def noise_texture(self, rng, amount=0.06, color=(0, 0, 0, 30)):
        """轻微颗粒感,避免大片纯色显得死板。"""
        for y in range(self.h):
            for x in range(self.w):
                if self.alpha_at(x, y) <= 8:
                    continue
                if rng.chance(amount):
                    c = self.get(x, y)
                    self.set(x, y, (c[0], c[1], c[2], max(0, min(255, c[3] - 18))))

    def blit(self, other, ox, oy):
        """把另一张画布贴到 (ox, oy),用于逐帧合成精灵表。"""
        for y in range(other.h):
            for x in range(other.w):
                c = other.px[y][x]
                if c[3] > 0:
                    self.set(ox + x, oy + y, c)

    # -- 输出 --
    def save(self, path):
        write_png(path, self.px, self.w, self.h)


def write_png(path, pixels, width, height):
    """写 8-bit RGBA PNG(无外部依赖)。"""
    raw = bytearray()
    for row in pixels:
        raw.append(0)  # filter type 0
        for p in row:
            raw.extend(bytes(p[:4]))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


# --------------------------------------------------------------------------
# 曲线工具
# --------------------------------------------------------------------------
def bezier(p0, p1, p2, p3, steps=24):
    """三次贝塞尔采样成折线点列。"""
    pts = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        x = (u ** 3 * p0[0] + 3 * u * u * t * p1[0]
             + 3 * u * t * t * p2[0] + t ** 3 * p3[0])
        y = (u ** 3 * p0[1] + 3 * u * u * t * p1[1]
             + 3 * u * t * t * p2[1] + t ** 3 * p3[1])
        pts.append((x, y))
    return pts


def blob(cx, cy, rx, ry, rng, wobble=0.18, points=14):
    """有机椭圆轮廓:半径按噪声扰动,避免纯圆纯方的死板感。"""
    pts = []
    phase = rng.uniform(0, math.tau)
    for i in range(points):
        a = math.tau * i / points
        # 只用低频谐波扰动半径:高频会让多边形自交,填充后出现空洞
        k = 1.0 + math.sin(a * 2 + phase) * wobble * 0.62 \
            + math.sin(a * 3 + phase * 1.3) * wobble * 0.38
        pts.append((cx + math.cos(a) * rx * k, cy + math.sin(a) * ry * k))
    return pts


def tree_silhouette(x, base_y, height, rng, spread=0.55, conifer=False):
    """饥荒味的树:粗树干 + 不规则树冠剪影。返回可填充多边形。

    conifer=True 画挺拔针叶(落叶松),否则画阔叶(白桦/杨树)。
    """
    # 窄冠 + 明显树干,别画成蘑菇
    trunk_w = max(2.5, height * 0.075)
    crown_h = height * 0.66
    canopy = []
    if conifer:
        tiers = 3
        for i in range(tiers):
            t = i / float(tiers - 1)
            tier_y = base_y - height * 0.26 - crown_h * t
            tier_w = height * spread * (0.62 - 0.30 * t)
            canopy.append(blob(x + rng.uniform(-3, 3), tier_y, tier_w,
                          crown_h * 0.32, rng, wobble=0.20, points=14))
    else:
        # 阔叶:两蓬圆冠就够,blob 叠太多会碎成纸屑
        canopy.append(blob(x, base_y - height * 0.60, height * spread * 0.52,
                       height * 0.31, rng, wobble=0.16, points=18))
        canopy.append(blob(x + height * spread * 0.24, base_y - height * 0.72,
                       height * spread * 0.30, height * 0.19, rng, wobble=0.18, points=14))
    trunk = [(x - trunk_w, base_y), (x - trunk_w * 0.62, base_y - height * 0.46),
             (x + trunk_w * 0.62, base_y - height * 0.46), (x + trunk_w, base_y)]
    # 返回多边形列表:合并成一个多边形会自交,填充后树冠会破洞
    return list(canopy), trunk
