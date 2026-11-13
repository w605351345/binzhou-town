#!/usr/bin/env python3
"""《宾州小镇》AI 生图工具 —— 基于 MiniMax image-01

用途:生成美术风格样板 / 概念图 / 背景参考,供美术管线参考与风格统一。

依赖:仅标准库(PNG 转换用 macOS 自带 sips,可用 --no-png 跳过)。

用法:
    # 单张
    python3 tools/ai_imagegen.py --prompt "黑土地上的木屋" --out assets/art/house.jpg

    # 批量(多候选图,便于挑风格)
    python3 tools/ai_imagegen.py --prompt "..." --out assets/art/house_ --n 3 --aspect-ratio 16:9

    # 内置风格预设(自动追加关键词)
    python3 tools/ai_imagegen.py --style dinner_scene --prompt "张晓芳站在院子门口" --out assets/art/npc.jpg

    # 从文件读 prompt(每行一条 = 批量)
    python3 tools/ai_imagegen.py --prompt-file tools/prompts/scene_batch.txt --out-dir assets/art/

鉴权(按优先级):
    1. 环境变量 MINIMAX_API_KEY
    2. ~/.codex/config.toml 里的 experimental_bearer_token
"""
import argparse
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Optional

API_URL = "https://api.minimax.cn/v1/image_generation"
MODEL = "image-01"

# --- 风格预设:统一《饥荒》式手绘像素美术方向 ---
STYLES = {
    "dinner_scene": (
        "Don't Starve inspired hand-painted 2D game art, dark whimsical storybook style, "
        "thick ink outlines, muted desaturated palette of browns olive and dusty blue, "
        "textured brush strokes, warm autumn harvest mood, side scrolling adventure game"
    ),
    "character": (
        "Don't Starve inspired character sprite art, dark whimsical storybook style, "
        "thick ink outlines, muted earthy palette, front facing full body, "
        "plain flat neutral background, centered, game character sheet"
    ),
    "tile": (
        "Don't Starve inspired game background tile, top-down view, dark whimsical storybook style, "
        "seamless texture, thick ink outlines, muted earthy palette of brown olive and grey, "
        "subtle brush texture, cracked dry black soil"
    ),
    "farm": (
        "Don't Starve inspired farming game art, isometric view, dark whimsical storybook style, "
        "thick ink outlines, muted earthy palette, tilled black soil farmland with crops, "
        "warm seasonal lighting, cozy rural survival game"
    ),
    "portrait": (
        "Don't Starve inspired NPC portrait, dark whimsical storybook style, thick ink outlines, "
        "muted earthy palette, head and shoulders, neutral dark background, character portrait"
    ),
}

# 禁止在游戏内出现的真实地域信息(需求 4:游戏中不得提及)
FORBIDDEN = ("binxian", "bin county", "heilongjiang", "harbin", "黑龙江", "宾县", "哈尔滨")

# 通用负面描述(避免 AI 生成的现代/西式元素)
NEGATIVE = (
    "no text, no watermark, no signature, no ui, no modern objects, no cars, no electricity, "
    "no anime style, no photorealistic 3d render, no glossy vector art"
)


def resolve_key() -> str:
    """按优先级拿 API key:环境变量 > ~/.codex/config.toml。"""
    key = os.environ.get("MINIMAX_API_KEY", "").strip()
    if key:
        return key
    cfg = Path.home() / ".codex" / "config.toml"
    if cfg.exists():
        m = re.search(r'experimental_bearer_token\s*=\s*"([^"]+)"', cfg.read_text())
        if m:
            return m.group(1)
    raise SystemExit(
        "❌ 找不到 API key。请设置环境变量:\n"
        "   export MINIMAX_API_KEY='你的 key'\n"
        "或在 ~/.codex/config.toml 里配置 experimental_bearer_token。"
    )


def build_prompt(prompt: str, style: Optional[str], extra: Optional[str]) -> str:
    parts = []
    if style:
        parts.append(STYLES.get(style, style))
    parts.append(prompt.strip())
    if extra:
        parts.append(extra.strip())
    parts.append(NEGATIVE)
    return ", ".join(p for p in parts if p)


def request(key: str, payload: dict, retries: int = 3) -> dict:
    """调用 MiniMax 生图接口,带指数退避重试。"""
    body = json.dumps(payload).encode()
    last_err = ""
    for attempt in range(1, retries + 1):
        req = urllib.request.Request(
            API_URL,
            data=body,
            headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=180) as resp:
                data = json.loads(resp.read().decode())
            if data.get("base_resp", {}).get("status_code") != 0:
                last_err = data.get("base_resp", {}).get("status_msg", "unknown")
            else:
                return data
        except urllib.error.HTTPError as e:
            last_err = f"HTTP {e.code}: {e.read().decode()[:200]}"
        except Exception as e:  # 网络抖动 / 超时
            last_err = f"{type(e).__name__}: {e}"
        if attempt < retries:
            wait = 2 ** attempt
            print(f"  … 第 {attempt} 次失败({last_err}),{wait}s 后重试", file=sys.stderr)
            time.sleep(wait)
    raise SystemExit(f"❌ 生图失败:{last_err}")


def save_images(data: dict, out: Path, prefix: str, as_png: bool, size: Optional[str]) -> list:
    """把返回的图片落盘,返回写出的文件列表。"""
    out.parent.mkdir(parents=True, exist_ok=True)
    written = []
    items = data.get("data", {})
    blobs = []
    if items.get("image_base64"):
        for b64 in items["image_base64"]:
            blobs.append(base64.b64decode(b64))
    elif items.get("image_urls"):
        for url in items["image_urls"]:
            with urllib.request.urlopen(url, timeout=120) as r:
                blobs.append(r.read())
    else:
        raise SystemExit("❌ 响应里没有图片数据")

    for i, blob in enumerate(blobs):
        suffix = "" if len(blobs) == 1 else f"_{i + 1}"
        # 统一先写成 .jpg 临时文件,再转 PNG,避免输出名已是 .png 时被覆盖后删除
        path = out.with_name(f"{out.stem}{suffix}.jpg")
        path.write_bytes(blob)
        written.append(path)

    if as_png:
        final = []
        for src in written:
            png = src.with_name(f"{src.stem}.png")
            subprocess.run(["sips", "-s", "format", "png", str(src), "--out", str(png)],
                           check=True, capture_output=True)
            if size:
                w, h = size.lower().split("x")
                subprocess.run(["sips", "-z", h, w, str(png), "--out", str(png)],
                               check=True, capture_output=True)
            src.unlink()
            final.append(png)
        written = final
    else:
        written = [p.with_suffix(out.suffix or ".jpg") if p.suffix != (out.suffix or ".jpg") else p
                   for p in written]
    return written


def main() -> int:
    ap = argparse.ArgumentParser(description="《宾州小镇》AI 生图工具(MiniMax image-01)")
    ap.add_argument("--prompt", help="图片描述")
    ap.add_argument("--prompt-file", help="从文件读 prompt(每行一条)")
    ap.add_argument("--style", choices=sorted(STYLES.keys()), help="内置风格预设")
    ap.add_argument("--out", help="输出文件路径(多图时自动加序号)")
    ap.add_argument("--out-dir", default="assets/art", help="批量输出目录(配合 --prompt-file)")
    ap.add_argument("--n", type=int, default=1, help="生成张数(1-9)")
    ap.add_argument("--aspect-ratio", default="1:1", help="1:1 / 16:9 / 9:16 / 4:3 / 3:4 / 21:9 / 2:3 / 3:2")
    ap.add_argument("--seed", type=int, help="随机种子(同 seed 出同图)")
    ap.add_argument("--optimizer", action="store_true", help="开启 prompt 自动优化")
    ap.add_argument("--no-png", action="store_true", help="不转 PNG(默认转,Godot 用 PNG)")
    ap.add_argument("--size", help="输出尺寸,如 512x512(用 sips 缩放)")
    ap.add_argument("--extra", help="追加到 prompt 末尾的自定义描述")
    args = ap.parse_args()

    if not args.prompt and not args.prompt_file:
        ap.error("需要 --prompt 或 --prompt-file")

    prompts = []
    if args.prompt_file:
        prompts = [l.strip() for l in Path(args.prompt_file).read_text().splitlines()
                   if l.strip() and not l.startswith("#")]
    else:
        prompts = [args.prompt]

    key = resolve_key()
    print(f"🔑 已加载 key({key[:6]}…),模型 {MODEL},共 {len(prompts)} 组 prompt × {args.n} 张")

    all_files = []
    for idx, p in enumerate(prompts, 1):
        full = build_prompt(p, args.style, args.extra)
        low = full.lower()
        hit = [w for w in FORBIDDEN if w.lower() in low]
        if hit:
            print(f"  ⚠️  提示词含真实地名 {hit},已按需求剔除")
            for w in hit:
                full = full.replace(w, "").replace(w.lower(), "")
        payload = {
            "model": MODEL,
            "prompt": full,
            "aspect_ratio": args.aspect_ratio,
            "response_format": "base64",
            "n": args.n,
            "prompt_optimizer": args.optimizer,
        }
        if args.seed is not None:
            payload["seed"] = args.seed
        print(f"\n[{idx}/{len(prompts)}] {p[:60]}…")
        t0 = time.time()
        data = request(key, payload)
        if args.prompt_file or len(prompts) > 1:
            out = Path(args.out_dir) / (re.sub(r"[^\w一-鿿-]+", "_", p)[:40])
        else:
            out = Path(args.out)
        files = save_images(data, out, args.prompt, not args.no_png, args.size)
        dt = time.time() - t0
        for f in files:
            print(f"  ✅ {f}  ({f.stat().st_size // 1024} KB, {dt:.1f}s)")
        all_files.extend(files)
    print(f"\n共写出 {len(all_files)} 张图。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
