#!/usr/bin/env python3
"""AI 概念图的清单、哈希、回执与后处理公共逻辑。"""

from __future__ import annotations

import hashlib
import json
import struct
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PROMPTS = PROJECT_ROOT / "tools" / "prompts" / "ai_assets.json"
DEFAULT_MANIFEST = PROJECT_ROOT / "assets" / "art" / "ai" / "manifest.json"
DEFAULT_FINALIZED = PROJECT_ROOT / "assets" / "art" / "ai" / "receipts" / "finalized.json"
DEFAULT_RECEIPT = PROJECT_ROOT / "assets" / "art" / "ai" / "receipts" / "all.json"

FORBIDDEN_PLACE_NAMES = (
    "binxian",
    "bin county",
    "heilongjiang",
    "harbin",
    "黑龙江",
    "宾县",
    "哈尔滨",
)

# AI 概念图不是运行时资产。横版场景统一裁掉生成器常在边缘留下的签名/水印，
# 再回到 16:9 画布；对话框 UI 与人物立绘保持原图。
# 208×117 的对称裁边仍严格保持 16:9，并覆盖 L08 右下角较靠内的生成器签名。
DEFAULT_POSTPROCESS = {
    "seasons": {
        "border_crop_x": 208,
        "border_crop_y": 117,
        "width": 1920,
        "height": 1080,
    },
    "backgrounds": {
        "border_crop_x": 208,
        "border_crop_y": 117,
        "width": 1920,
        "height": 1080,
    },
}


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def atomic_write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f".tmp-{Path(__file__).stem}")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        header = handle.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"不是合法 PNG: {path}")
    width, height = struct.unpack(">II", header[16:24])
    return int(width), int(height)


def parse_size(value: str) -> tuple[int, int]:
    width, height = value.lower().split("x", 1)
    return int(width), int(height)


def postprocess_for(job: dict[str, Any]) -> Optional[dict[str, Any]]:
    explicit = job.get("postprocess")
    if explicit is not None:
        return explicit
    return DEFAULT_POSTPROCESS.get(str(job.get("category", "")))


def build_inventory(data: dict[str, Any], root: Path = PROJECT_ROOT) -> dict[str, Any]:
    jobs = []
    for raw_job in data.get("jobs", []):
        job = dict(raw_job)
        output = root / str(job["output"])
        job["postprocess"] = postprocess_for(job)
        job["exists"] = output.is_file()
        if job["exists"]:
            width, height = read_png_size(output)
            stat = output.stat()
            job.update(
                {
                    "size_bytes": stat.st_size,
                    "sha256": file_sha256(output),
                    "width": width,
                    "height": height,
                    "modified_at": datetime.fromtimestamp(stat.st_mtime, timezone.utc)
                    .isoformat()
                    .replace("+00:00", "Z"),
                }
            )
        jobs.append(job)
    return {
        "version": data.get("version", 1),
        "model": data.get("model", ""),
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "jobs": jobs,
    }


def merge_receipt(
    path: Path,
    *,
    run_id: str,
    manifest: str,
    model: str,
    generated: list[str],
    skipped: list[str],
    finalized: list[str],
) -> dict[str, Any]:
    existing: dict[str, Any] = {}
    if path.exists():
        try:
            loaded = load_json(path)
            if isinstance(loaded, dict):
                existing = loaded
        except (json.JSONDecodeError, OSError):
            existing = {}

    cumulative = sorted(set(existing.get("generated", [])) | set(generated))
    runs = list(existing.get("runs", []))
    runs.append(
        {
            "run_id": run_id,
            "generated": sorted(generated),
            "skipped": sorted(skipped),
            "finalized": sorted(finalized),
        }
    )
    runs = runs[-20:]
    payload = {
        "manifest": manifest,
        "model": model,
        "generated": cumulative,
        "last_run": runs[-1],
        "runs": runs,
    }
    atomic_write_json(path, payload)
    return payload


def forbidden_terms(text: str) -> list[str]:
    lowered = text.lower()
    return [word for word in FORBIDDEN_PLACE_NAMES if word.lower() in lowered]


def run_id_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
