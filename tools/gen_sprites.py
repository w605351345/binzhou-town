#!/usr/bin/env python3
"""《宾州小镇》占位精灵表生成器 —— 4 方向 × 8 帧

美术资源到位前,用程序化色块生成占位图,保证动画管线(状态机 + 帧序列 + 翻转)
可运行、可测试、可替换。生成物为 PNG,提交进仓库,CI 可复现。

用法:
    python3 tools/gen_sprites.py [输出目录]

输出:
    assets/sprites/player_body.png   主角行走表 8 列(帧) × 4 行(下/上/左/右)
    assets/sprites/player_female.png  女主行走表(同布局,配色不同)
"""
import struct
import sys
import zlib
from pathlib import Path

# --- 帧布局 ---
FRAMES = 8              # 每方向帧数
CELL = 32               # 单帧宽(px)
CELL_H = 48             # 单帧高(px)
DIRS = ["down", "up", "left", "right"]

# --- 配色(黑龙江黑土地 / 治愈系) ---
MALE = {
    "coat": (72, 106, 148),     # 藏蓝棉袄
    "coat_dark": (52, 78, 112),
    "pants": (58, 62, 78),
    "skin": (238, 205, 178),
    "hair": (46, 42, 40),
}
FEMALE = {
    "coat": (176, 92, 108),    # 玫红棉袄
    "coat_dark": (140, 68, 84),
    "pants": (72, 66, 92),
    "skin": (240, 212, 188),
    "hair": (52, 40, 38),
}


def write_png(path: Path, pixels: list) -> None:
    """写 8-bit RGBA PNG(无外部依赖)。"""
    width = CELL * FRAMES
    height = len(pixels)
    raw = bytearray()
    for row in pixels:
        raw.append(0)  # filter type 0
        for px in row:
            raw.extend(bytes(px))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def blank() -> list:
    return [[(0, 0, 0, 0)] * (CELL * FRAMES) for _ in range(CELL_H * len(DIRS))]


def put(px: list, x: int, y: int, color: tuple, alpha: int = 255) -> None:
    if 0 <= x < CELL * FRAMES and 0 <= y < CELL_H * len(DIRS):
        px[y][x] = (color[0], color[1], color[2], alpha)


def rect(px: list, x0: int, y0: int, w: int, h: int, color: tuple) -> None:
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            put(px, x, y, color)


def draw_body(px: list, row: int, frame: int, pal: dict) -> None:
    """画一帧主角。行 = 方向(down/up/left/right),列 = 帧。"""
    ox = frame * CELL
    oy = row * CELL_H
    direction = DIRS[row]
    # 走路时上下起伏(2 帧一循环)
    bob = -1 if frame % 4 in (1, 2) else 0
    cx = ox + CELL // 2
    side = direction in ("left", "right")

    def R(x, y, w, h, c):
        rect(px, ox + x, oy + y + bob, w, h, c)

    if side:
        # 侧身:身体窄一档,单侧手臂,单只眼
        swing = 2 if frame % 4 in (1, 2) else 0
        R(cx - 4, 32, 4, 10 - swing // 2, pal["pants"])
        R(cx + 1, 32, 4, 10 - (2 - swing // 2), pal["pants"])
        R(cx - 5, 16, 10, 16, pal["coat"])
        R(cx - 5, 16, 10, 3, pal["coat_dark"])
        R(cx - 8, 18 + swing, 3, 10, pal["coat_dark"])
        R(cx - 6, 3, 11, 12, pal["skin"])
        R(cx - 7, 1, 13, 5, pal["hair"])
        R(cx - 7, 1, 2, 11, pal["hair"])
        R(cx + 4, 1, 2, 11, pal["hair"])
        # 侧脸:一只眼 + 朝向侧的刘海
        eye_x = cx - 4 if direction == "left" else cx + 1
        R(eye_x, 8, 2, 2, pal["hair"])
        return

    # 腿:左右交替迈步
    leg_l = 8 + (frame % 4) * 2
    leg_r = 8 + ((frame + 2) % 4) * 2
    R(cx - 6, 32, 4, 10 - abs(leg_l - 8) // 2, pal["pants"])
    R(cx + 2, 32, 4, 10 - abs(leg_r - 8) // 2, pal["pants"])

    # 棉袄身体
    R(cx - 7, 16, 14, 16, pal["coat"])
    R(cx - 7, 16, 14, 3, pal["coat_dark"])   # 领口阴影
    # 手臂(反向摆动)
    arm = 2 if frame % 4 in (1, 2) else 0
    R(cx - 10, 18 + arm, 3, 11, pal["coat_dark"])
    R(cx + 7, 18 - arm, 3, 11, pal["coat_dark"])

    # 头
    R(cx - 6, 3, 12, 12, pal["skin"])
    # 头发
    R(cx - 7, 1, 14, 5, pal["hair"])
    R(cx - 7, 1, 2, 11, pal["hair"])
    R(cx + 5, 1, 2, 11, pal["hair"])
    # 脸(向下时画眼睛,向上是后脑勺)
    if direction == "down":
        R(cx - 3, 8, 2, 2, pal["hair"])
        R(cx + 2, 8, 2, 2, pal["hair"])


def build(pal: dict) -> list:
    px = blank()
    for row in range(len(DIRS)):
        for frame in range(FRAMES):
            draw_body(px, row, frame, pal)
    return px


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("assets/sprites")
    out = root / "player_body.png"
    write_png(out, build(MALE))
    print(f"  · {out} ({CELL * FRAMES}x{CELL_H * len(DIRS)}, 4 方向 x {FRAMES} 帧)")
    out_f = root / "player_female.png"
    write_png(out_f, build(FEMALE))
    print(f"  · {out_f} ({CELL * FRAMES}x{CELL_H * len(DIRS)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
