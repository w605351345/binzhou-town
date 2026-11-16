#!/usr/bin/env python3
"""场景截图工具 —— 用 Godot Movie Maker 模式抓帧,产出 before/after 对比图。

美术改动必须有截图对比才算验收,所以这个脚本进 CI 也跑一遍(非阻塞)。

用法:
    python3 tools/capture_scenes.py --out docs/screenshots/after
    python3 tools/capture_scenes.py --out /tmp/x --scenes farm town --frames 12
    python3 tools/capture_scenes.py --out /tmp/seasons --scenes L01 \
        --seasons spring summer autumn winter --time 12:00
"""
import argparse
import shutil
import subprocess
import sys
from pathlib import Path

# 控制台编码未必是 UTF-8(Windows 默认 cp1252),打印中文会抛 UnicodeEncodeError
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8", errors="replace")

SCENES = {
    "farm": "res://scenes/farm.tscn",
    "town": "res://scenes/town_street.tscn",
    "post": "res://scenes/post_office.tscn",
    "menu": "res://scenes/main_menu.tscn",
    "game": "res://scenes/game.tscn",
}
for _i in range(1, 15):
    SCENES["L%02d" % _i] = "res://scenes/locations/L%02d.tscn" % _i


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="docs/screenshots/after")
    ap.add_argument("--scenes", nargs="*", default=["farm", "town"])
    ap.add_argument("--frames", type=int, default=10)
    ap.add_argument("--seasons", nargs="*",
                    choices=["spring", "summer", "autumn", "winter"],
                    help="为每个场景分别抓取四季；不填则只抓当前默认季节")
    ap.add_argument("--time", default="12:00",
                    help="游戏内时刻，截图验收建议固定在白天")
    ap.add_argument("--weather", default="sunny",
                    help="锁定天气，避免截图被随机雨雪染暗")
    ap.add_argument("--godot", default=shutil.which("godot") or "godot")
    args = ap.parse_args(argv[1:])

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    failures = []

    seasons = args.seasons or [None]
    for name in args.scenes:
        scene = SCENES.get(name, name)
        for season in seasons:
            label = name if season is None else "%s_%s" % (name, season)
            tmp = out / ("_tmp_" + label)
            tmp.mkdir(parents=True, exist_ok=True)
            command = [
                args.godot, "--write-movie", str(tmp / (label + ".png")),
                "--quit-after", str(args.frames), scene,
            ]
            if season is not None:
                command.extend([
                    "--", "--season=%s" % season, "--time=%s" % args.time,
                    "--weather=%s" % args.weather,
                ])
            proc = subprocess.run(command, capture_output=True, text=True)
            frames = sorted(tmp.glob("%s*.png" % label))
            if not frames:
                print("✗ %s 没抓到帧" % label)
                if proc.stderr.strip():
                    print(proc.stderr.strip()[-1200:])
                failures.append(label)
                continue
            target = out / ("%s.png" % label)
            shutil.copyfile(frames[-1], target)
            shutil.rmtree(tmp, ignore_errors=True)   # 临时帧序列不入库
            print("✓ %s -> %s(%d 帧)" % (label, target, len(frames)))

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
