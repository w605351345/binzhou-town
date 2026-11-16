#!/usr/bin/env python3
"""校验 AI 概念图清单、文件尺寸、哈希与最终化状态。"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

import ai_assets_common as common


def validate_prompt_jobs(jobs: list[dict[str, Any]]) -> list[str]:
    errors: list[str] = []
    seen_names: set[str] = set()
    seen_outputs: set[str] = set()
    for job in jobs:
        name = str(job.get("name", "")).strip()
        output = str(job.get("output", "")).strip()
        prompt = str(job.get("prompt", ""))
        if not name:
            errors.append("任务缺少 name")
        elif name in seen_names:
            errors.append(f"任务 name 重复: {name}")
        seen_names.add(name)
        if not output:
            errors.append(f"{name or '(未命名)'} 缺少 output")
        elif output in seen_outputs:
            errors.append(f"输出路径重复: {output}")
        else:
            path = Path(output)
            if path.is_absolute() or ".." in path.parts:
                errors.append(f"{name or output} 的 output 必须是项目内相对路径")
            elif not output.startswith("assets/art/ai/") or path.suffix.lower() != ".png":
                errors.append(f"{name or output} 的 output 必须位于 assets/art/ai/ 且为 PNG")
        seen_outputs.add(output)
        if not prompt.strip():
            errors.append(f"{name or output} 缺少 prompt")
        hits = common.forbidden_terms(prompt)
        if hits:
            errors.append(f"{name or output} 的 prompt 含真实地名 {hits}")
        try:
            width, height = common.parse_size(str(job.get("size", "")))
            if width <= 0 or height <= 0:
                raise ValueError
        except (ValueError, AttributeError):
            errors.append(f"{name or output} 的 size 非法: {job.get('size')!r}")
        postprocess = common.postprocess_for(job)
        if postprocess is not None:
            try:
                crop_x = int(postprocess.get("border_crop_x", -1))
                crop_y = int(postprocess.get("border_crop_y", -1))
                target_width = int(postprocess["width"])
                target_height = int(postprocess["height"])
                source_width, source_height = common.parse_size(str(job.get("size", "")))
                crop_width = source_width - crop_x * 2
                crop_height = source_height - crop_y * 2
                if crop_x < 0 or crop_y < 0 or crop_width <= 0 or crop_height <= 0:
                    raise ValueError
                if target_width <= 0 or target_height <= 0:
                    raise ValueError
                if abs((crop_width / crop_height) - (target_width / target_height)) > 0.002:
                    raise ValueError
            except (KeyError, TypeError, ValueError, AttributeError):
                errors.append(f"{name or output} 的 postprocess 非法: {postprocess!r}")
    return errors


def _state_for(root: Path) -> dict[str, Any]:
    path = root / "assets" / "art" / "ai" / "receipts" / "finalized.json"
    if not path.exists():
        return {}
    try:
        data = common.load_json(path)
    except (ValueError, OSError):
        return {}
    return data.get("files", {}) if isinstance(data, dict) else {}


def validate_inventory(
    prompts_data: dict[str, Any],
    inventory: dict[str, Any],
    root: Path,
    *,
    require_finalized: bool = False,
) -> list[str]:
    errors = validate_prompt_jobs(list(prompts_data.get("jobs", [])))
    prompt_jobs = {str(job["output"]): job for job in prompts_data.get("jobs", []) if job.get("output")}
    inventory_jobs = {
        str(job.get("output")): job for job in inventory.get("jobs", []) if job.get("output")
    }
    if set(prompt_jobs) != set(inventory_jobs):
        missing = sorted(set(prompt_jobs) - set(inventory_jobs))
        extra = sorted(set(inventory_jobs) - set(prompt_jobs))
        if missing:
            errors.append(f"manifest 缺少任务: {missing}")
        if extra:
            errors.append(f"manifest 多出任务: {extra}")

    state = _state_for(root)
    for output, job in prompt_jobs.items():
        path = root / output
        entry = inventory_jobs.get(output, {})
        if not path.is_file():
            errors.append(f"图片不存在: {output}")
            continue
        expected_width, expected_height = common.parse_size(str(job["size"]))
        try:
            width, height = common.read_png_size(path)
        except ValueError as exc:
            errors.append(str(exc))
            continue
        if (width, height) != (expected_width, expected_height):
            errors.append(
                f"图片尺寸不符: {output} 实际 {width}x{height}，期望 {expected_width}x{expected_height}"
            )
        if not entry.get("exists"):
            errors.append(f"manifest 标记不存在: {output}")
        if entry.get("sha256") != common.file_sha256(path):
            errors.append(f"manifest 哈希过期: {output}")
        if (entry.get("width"), entry.get("height")) != (width, height):
            errors.append(f"manifest 尺寸过期: {output}")
        if entry.get("postprocess") != common.postprocess_for(job):
            errors.append(f"manifest 后处理参数过期: {output}")
        if require_finalized and common.postprocess_for(job):
            record = state.get(output)
            if (
                not isinstance(record, dict)
                or record.get("sha256") != common.file_sha256(path)
                or record.get("postprocess") != common.postprocess_for(job)
            ):
                errors.append(f"尚未最终化或已改动: {output}")
    return errors


def _raw_is_ignored(root: Path) -> bool:
    gitignore = root / ".gitignore"
    if not gitignore.exists():
        return False
    lines = {
        line.strip()
        for line in gitignore.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }
    return "assets/art/ai/raw/" in lines or "assets/art/ai/raw" in lines


def main() -> int:
    parser = argparse.ArgumentParser(description="校验 AI 概念图清单、尺寸、哈希与最终化状态")
    parser.add_argument("--prompts", default=str(common.DEFAULT_PROMPTS))
    parser.add_argument("--manifest", default=str(common.DEFAULT_MANIFEST))
    args = parser.parse_args()

    prompts_data = common.load_json(Path(args.prompts))
    manifest = common.load_json(Path(args.manifest))
    errors = validate_inventory(prompts_data, manifest, common.PROJECT_ROOT, require_finalized=True)
    if not _raw_is_ignored(common.PROJECT_ROOT):
        errors.append(".gitignore 未忽略 assets/art/ai/raw/（原始候选可能含签名，不应入库）")

    if errors:
        print(f"❌ AI 资产校验失败，共 {len(errors)} 项：", file=sys.stderr)
        for error in errors:
            print(f"  · {error}", file=sys.stderr)
        return 1

    jobs = prompts_data.get("jobs", [])
    cleaned = sum(1 for job in jobs if common.postprocess_for(job))
    print(
        f"✅ AI 资产校验通过: {len(jobs)} 张概念图，"
        f"{cleaned} 张已最终化，{len(jobs) - cleaned} 张保留原图"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
