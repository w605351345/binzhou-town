#!/usr/bin/env python3
"""按清单批量生成 MiniMax 概念图，支持断点续跑。"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import ai_assets_common as common
import ai_imagegen
import finalize_ai_assets


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "tools" / "prompts" / "ai_assets.json"


def main() -> int:
    parser = argparse.ArgumentParser(description="批量生成《麦溪镇》MiniMax 概念图")
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST))
    parser.add_argument("--config", help="Codex TOML 配置路径")
    parser.add_argument("--only", action="append", help="只生成指定分类，可重复")
    parser.add_argument("--name", action="append", help="只生成指定名称，可重复")
    parser.add_argument("--force", action="store_true", help="覆盖已有图片")
    parser.add_argument("--refresh", action="store_true", help="不调用 API，只刷新清单、回执与最终化状态")
    parser.add_argument("--no-finalize", action="store_true", help="跳过边缘签名裁剪与画布归一化")
    args = parser.parse_args()

    manifest_path = Path(args.manifest)
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    jobs = data.get("jobs", [])
    if args.only:
        allowed = set(args.only)
        jobs = [job for job in jobs if job.get("category") in allowed]
    if args.name:
        wanted = set(args.name)
        jobs = [job for job in jobs if job.get("name") in wanted]
    if not jobs:
        raise SystemExit("❌ 清单中没有可生成的任务")

    for job in jobs:
        job["postprocess"] = common.postprocess_for(job)

    pending = [] if args.refresh else [
        job for job in jobs if args.force or not (ROOT / job["output"]).exists()
    ]
    key = ai_imagegen.resolve_key(args.config) if pending else None
    if key:
        print(f"🔑 已加载 MiniMax key(长度 {len(key)}),模型 {ai_imagegen.MODEL},待生成 {len(pending)} 张")
    elif args.refresh:
        print("↷ 刷新模式：不调用 API，只重建清单、回执与最终化状态")
    else:
        print("↷ 所有图片已存在：不调用 API，只重建清单、回执与最终化状态")

    generated = []
    skipped = []
    failed = []
    for index, job in enumerate(jobs, 1):
        output = ROOT / job["output"]
        label = f"{job.get('category', 'misc')}/{job.get('name', output.stem)}"
        if output.exists() and not args.force:
            print(f"[{index}/{len(jobs)}] ↷ 跳过已有 {label}")
            skipped.append(job["output"])
            continue
        if args.refresh:
            continue

        full_prompt = ai_imagegen.build_prompt(job["prompt"], job.get("style"), job.get("extra"))
        payload = {
            "model": ai_imagegen.MODEL,
            "prompt": full_prompt,
            "aspect_ratio": job.get("aspect_ratio", "1:1"),
            "response_format": "base64",
            "n": 1,
            "prompt_optimizer": False,
        }
        if job.get("seed") is not None:
            payload["seed"] = int(job["seed"])

        print(f"[{index}/{len(jobs)}] ▶ {label}")
        started = time.time()
        try:
            result = ai_imagegen.request(key, payload)
            files = ai_imagegen.save_images(result, output, job["prompt"], True, job.get("size"))
        except Exception as exc:
            failed.append(job["output"])
            print(f"  ❌ {label}: {exc}", file=sys.stderr)
            continue
        for path in files:
            print(f"  ✅ {path.relative_to(ROOT)} ({path.stat().st_size // 1024} KB, {time.time() - started:.1f}s)")
            generated.append(str(path.relative_to(ROOT)))

    finalize_result = {"finalized": [], "skipped": [], "missing": []}
    if not args.no_finalize:
        finalize_result = finalize_ai_assets.finalize_jobs(
            jobs, ROOT, common.DEFAULT_FINALIZED
        )
        for path in finalize_result["finalized"]:
            print(f"  ✂️  已裁边 {path}")
        for path in finalize_result["missing"]:
            print(f"  ⚠️  最终化缺图 {path}", file=sys.stderr)

    inventory = common.build_inventory(
        {**data, "model": data.get("model", ai_imagegen.MODEL)}, ROOT
    )
    common.atomic_write_json(common.DEFAULT_MANIFEST, inventory)

    receipt = common.merge_receipt(
        common.DEFAULT_RECEIPT,
        run_id=common.run_id_now(),
        manifest=str(manifest_path.relative_to(ROOT)),
        model=data.get("model", ai_imagegen.MODEL),
        generated=generated,
        skipped=skipped,
        finalized=finalize_result["finalized"],
    )
    if failed:
        receipt["last_run"]["failed"] = sorted(failed)
        common.atomic_write_json(common.DEFAULT_RECEIPT, receipt)

    print(
        f"\n完成: 新生成 {len(generated)} 张, 跳过 {len(skipped)} 张, 失败 {len(failed)} 张, "
        f"裁边 {len(finalize_result['finalized'])} 张"
    )
    print(f"回执: {common.DEFAULT_RECEIPT.relative_to(ROOT)}")
    print(f"清单: {common.DEFAULT_MANIFEST.relative_to(ROOT)}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
