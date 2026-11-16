#!/usr/bin/env python3
"""裁掉 AI 概念图边缘的生成器签名并统一回目标画布。

只处理带 ``postprocess`` 的清单项；人物立绘与对话框 UI 默认不动。
处理结果写入 receipts/finalized.json，重复运行不会二次裁剪。
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

import ai_assets_common as common


def _load_state(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"version": 1, "files": {}}
    try:
        data = common.load_json(path)
    except (json.JSONDecodeError, OSError):
        return {"version": 1, "files": {}}
    if not isinstance(data, dict) or not isinstance(data.get("files"), dict):
        return {"version": 1, "files": {}}
    return data


def _crop_file(source: Path, destination: Path, postprocess: dict[str, Any], sips: str) -> None:
    source_width, source_height = common.read_png_size(source)
    crop_x = int(postprocess.get("border_crop_x", 0))
    crop_y = int(postprocess.get("border_crop_y", 0))
    target_width = int(postprocess["width"])
    target_height = int(postprocess["height"])
    crop_width = source_width - crop_x * 2
    crop_height = source_height - crop_y * 2
    if crop_width <= 0 or crop_height <= 0:
        raise ValueError(f"裁剪尺寸非法: {source} {source_width}x{source_height}")
    if abs((crop_width / crop_height) - (target_width / target_height)) > 0.002:
        raise ValueError(
            f"裁剪后画布不是目标比例: {source} {crop_width}x{crop_height} -> {target_width}x{target_height}"
        )

    temporary = source.with_name(f"{source.stem}.crop-tmp{source.suffix}")
    try:
        subprocess.run(
            [sips, "-c", str(crop_height), str(crop_width),
             "--cropOffset", str(crop_y), str(crop_x), str(source), "--out", str(temporary)],
            check=True,
            capture_output=True,
        )
        destination.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [sips, "-z", str(target_height), str(target_width), str(temporary), "--out", str(destination)],
            check=True,
            capture_output=True,
        )
    finally:
        if temporary.exists():
            temporary.unlink()


def finalize_jobs(jobs: list[dict[str, Any]], root: Path, state_path: Path) -> dict[str, list[str]]:
    sips = shutil.which("sips")
    if sips is None:
        raise SystemExit("❌ 找不到 sips；AI 概念图最终化仅支持 macOS")

    state = _load_state(state_path)
    files = state["files"]
    finalized: list[str] = []
    skipped: list[str] = []
    missing: list[str] = []

    for job in jobs:
        postprocess = job.get("postprocess")
        if not postprocess:
            skipped.append(str(job["output"]))
            continue
        output = root / str(job["output"])
        if not output.exists():
            missing.append(str(job["output"]))
            continue
        digest = common.file_sha256(output)
        previous = files.get(str(job["output"]))
        if (
            isinstance(previous, dict)
            and previous.get("sha256") == digest
            and previous.get("postprocess") == postprocess
        ):
            skipped.append(str(job["output"]))
            continue

        _crop_file(output, output, postprocess, sips)
        width, height = common.read_png_size(output)
        files[str(job["output"])] = {
            "sha256": common.file_sha256(output),
            "width": width,
            "height": height,
            "postprocess": postprocess,
            "finalized_at": common.run_id_now(),
        }
        finalized.append(str(job["output"]))

    common.atomic_write_json(state_path, state)
    return {"finalized": finalized, "skipped": skipped, "missing": missing}


def main() -> int:
    parser = argparse.ArgumentParser(description="裁掉 AI 概念图边缘签名并统一画布")
    parser.add_argument("--prompts", default=str(common.DEFAULT_PROMPTS))
    parser.add_argument("--state", default=str(common.DEFAULT_FINALIZED))
    parser.add_argument("--name", action="append", help="只处理指定名称，可重复")
    parser.add_argument("--category", action="append", help="只处理指定分类，可重复")
    args = parser.parse_args()

    data = common.load_json(Path(args.prompts))
    jobs = list(data.get("jobs", []))
    if args.name:
        wanted = set(args.name)
        jobs = [job for job in jobs if job.get("name") in wanted]
    if args.category:
        wanted = set(args.category)
        jobs = [job for job in jobs if job.get("category") in wanted]
    for job in jobs:
        job["postprocess"] = common.postprocess_for(job)

    result = finalize_jobs(jobs, common.PROJECT_ROOT, Path(args.state))
    for path in result["finalized"]:
        print(f"  ✅ 已裁剪 {path}")
    for path in result["missing"]:
        print(f"  ⚠️  缺图 {path}", file=sys.stderr)
    print(
        f"最终化完成: 裁剪 {len(result['finalized'])} 张，"
        f"已处理跳过 {len(result['skipped'])} 张，缺图 {len(result['missing'])} 张"
    )
    return 1 if result["missing"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
