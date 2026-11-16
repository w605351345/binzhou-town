from __future__ import annotations

import json
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import ai_assets_common as common
import finalize_ai_assets as finalize
import validate_ai_assets as validate


def write_png(path: Path, width: int, height: int, rgb: tuple[int, int, int] = (32, 48, 64)) -> None:
    row = b"\x00" + bytes(rgb) * width
    raw = row * height

    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


class AiAssetTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = Path(tempfile.mkdtemp(prefix="binzhou-ai-assets-"))

    def tearDown(self) -> None:
        shutil.rmtree(self.temp, ignore_errors=True)

    def test_png_dimensions_and_manifest_hash(self) -> None:
        image = self.temp / "seasons" / "spring.png"
        write_png(image, 16, 9)
        self.assertEqual(common.read_png_size(image), (16, 9))

        job = {
            "category": "seasons",
            "name": "spring",
            "output": "seasons/spring.png",
            "size": "16x9",
            "prompt": "冻土返浆",
        }
        inventory = common.build_inventory({"version": 1, "model": "image-01", "jobs": [job]}, self.temp)
        entry = inventory["jobs"][0]
        self.assertTrue(entry["exists"])
        self.assertEqual((entry["width"], entry["height"]), (16, 9))
        self.assertEqual(entry["sha256"], common.file_sha256(image))
        self.assertEqual(entry["size_bytes"], image.stat().st_size)
        self.assertIsNotNone(entry["postprocess"])

    def test_receipt_merge_keeps_cumulative_generated(self) -> None:
        receipt = self.temp / "receipts" / "all.json"
        common.merge_receipt(
            receipt,
            run_id="run-a",
            manifest="tools/prompts/ai_assets.json",
            model="image-01",
            generated=["assets/art/ai/seasons/spring.png"],
            skipped=[],
            finalized=[],
        )
        merged = common.merge_receipt(
            receipt,
            run_id="run-b",
            manifest="tools/prompts/ai_assets.json",
            model="image-01",
            generated=["assets/art/ai/backgrounds/L01.png"],
            skipped=["assets/art/ai/seasons/spring.png"],
            finalized=["assets/art/ai/seasons/winter.png"],
        )
        self.assertEqual(
            merged["generated"],
            [
                "assets/art/ai/backgrounds/L01.png",
                "assets/art/ai/seasons/spring.png",
            ],
        )
        self.assertEqual(merged["last_run"]["run_id"], "run-b")
        self.assertEqual(len(merged["runs"]), 2)

    def test_forbidden_place_names_are_rejected(self) -> None:
        jobs = [{"name": "bad", "output": "bad.png", "prompt": "哈尔滨郊外的雪镇"}]
        errors = validate.validate_prompt_jobs(jobs)
        self.assertTrue(any("真实地名" in error for error in errors))

    def test_finalize_is_idempotent(self) -> None:
        if shutil.which("sips") is None:
            self.skipTest("sips is only available on macOS")
        image = self.temp / "scene.png"
        write_png(image, 192, 108)
        job = {
            "category": "seasons",
            "name": "scene",
            "output": "scene.png",
            "size": "192x108",
            "prompt": "场景",
            "postprocess": {
                "border_crop_x": 16,
                "border_crop_y": 9,
                "width": 192,
                "height": 108,
            },
        }
        state_path = self.temp / "receipts" / "finalized.json"
        first = finalize.finalize_jobs([job], self.temp, state_path)
        self.assertEqual(len(first["finalized"]), 1)
        self.assertEqual(common.read_png_size(image), (192, 108))
        first_hash = common.file_sha256(image)

        second = finalize.finalize_jobs([job], self.temp, state_path)
        self.assertEqual(second["finalized"], [])
        self.assertEqual(second["skipped"], ["scene.png"])
        self.assertEqual(common.file_sha256(image), first_hash)

        job["postprocess"] = {
            "border_crop_x": 32,
            "border_crop_y": 18,
            "width": 192,
            "height": 108,
        }
        third = finalize.finalize_jobs([job], self.temp, state_path)
        self.assertEqual(third["finalized"], ["scene.png"])
        self.assertEqual(common.read_png_size(image), (192, 108))
        state = json.loads(state_path.read_text(encoding="utf-8"))
        self.assertEqual(state["files"]["scene.png"]["postprocess"], job["postprocess"])

    def test_validate_rejects_missing_and_wrong_dimensions(self) -> None:
        image = self.temp / "wrong.png"
        write_png(image, 8, 8)
        job = {
            "category": "backgrounds",
            "name": "wrong",
            "output": "wrong.png",
            "size": "16x16",
            "prompt": "场景",
        }
        inventory = common.build_inventory({"version": 1, "jobs": [job]}, self.temp)
        errors = validate.validate_inventory({"jobs": [job]}, inventory, self.temp)
        self.assertTrue(any("尺寸不符" in error for error in errors))

        job["output"] = "missing.png"
        inventory = common.build_inventory({"version": 1, "jobs": [job]}, self.temp)
        errors = validate.validate_inventory({"jobs": [job]}, inventory, self.temp)
        self.assertTrue(any("不存在" in error for error in errors))

    def test_validate_rejects_unsafe_output_and_bad_postprocess(self) -> None:
        jobs = [
            {
                "name": "escape",
                "output": "../outside.png",
                "size": "1920x1080",
                "prompt": "场景",
            },
            {
                "name": "bad-crop",
                "output": "assets/art/ai/bad.png",
                "size": "1920x1080",
                "prompt": "场景",
                "postprocess": {
                    "border_crop_x": 300,
                    "border_crop_y": 100,
                    "width": 1920,
                    "height": 1080,
                },
            },
        ]
        errors = validate.validate_prompt_jobs(jobs)
        self.assertTrue(any("相对路径" in error for error in errors))
        self.assertTrue(any("postprocess 非法" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
