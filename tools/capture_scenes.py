#!/usr/bin/env python3
"""场景截图工具 —— 用 Godot Movie Maker 模式抓帧,产出 before/after 对比图。

美术改动必须有截图对比才算验收,所以这个脚本进 CI 也跑一遍(非阻塞)。

用法:
    python3 tools/capture_scenes.py --out docs/screenshots/after
    python3 tools/capture_scenes.py --out /tmp/x --scenes farm town --frames 12
"""
import argparse
import shutil
import subprocess
import sys
from pathlib import Path

SCENES = {
    "farm": "res://scenes/farm.tscn",
    "town": "res://scenes/town_street.tscn",
    "menu": "res://scenes/main_menu.tscn",
    "game": "res://scenes/game.tscn",
}


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="docs/screenshots/after")
    ap.add_argument("--scenes", nargs="*", default=["farm", "town"])
    ap.add_argument("--frames", type=int, default=10)
    ap.add_argument("--godot", default=shutil.which("godot") or "godot")
    args = ap.parse_args(argv[1:])

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    failures = []

    for name in args.scenes:
        scene = SCENES.get(name, name)
        tmp = out / ("_tmp_" + name)
        tmp.mkdir(parents=True, exist_ok=True)
        proc = subprocess.run(
            [args.godot, "--write-movie", str(tmp / (name + ".png")),
             "--quit-after", str(args.frames), scene],
            capture_output=True, text=True)
        frames = sorted(tmp.glob("%s*.png" % name))
        if not frames:
            print("✗ %s 没抓到帧" % name)
            failures.append(name)
            continue
        target = out / ("%s.png" % name)
        shutil.copyfile(frames[-1], target)
        shutil.rmtree(tmp, ignore_errors=True)   # 临时帧序列不入库
        print("✓ %s -> %s(%d 帧)" % (name, target, len(frames)))

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
