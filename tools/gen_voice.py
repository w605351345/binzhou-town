#!/usr/bin/env python3
"""《宾州小镇》普通话语音包生成器。

把 data/dialogues.json 里每条 NPC 台词录成 wav,供游戏内播放。

命名规则(必须永久稳定,否则真人录音无法对齐):
    <npc_id>__<line_id>__<variant>.wav
例如 zhang_xiaofang__greet__0.wav = 张晓芳开场白的第 1 个季节变体。

播放器选项不配音(那是玩家自己的话),所以只覆盖 lines。

依赖:
    macOS   —— 内置 say(普通话嗓音 Tingting)+ afconvert
    Linux   —— espeak-ng(可选);没有就跳过(语音包已入库,CI 不重录)

用法:
    python3 tools/gen_voice.py                 # 生成到 assets/audio/dialogue
    python3 tools/gen_voice.py --list          # 只列出将要生成的条目
"""
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIALOGUES = ROOT / "data" / "dialogues.json"
OUT_DIR = ROOT / "assets" / "audio" / "dialogue"

# macOS 的普通话嗓音
MAC_VOICE = "Tingting"
# espeak-ng 的普通话
ESPEAK_VOICE = "cmn"


def voice_key(npc_id: str, line_id: str, variant: int) -> str:
    return "%s__%s__%d" % (npc_id, line_id, variant)


def collect() -> list:
    """从 dialogues.json 收集 (npc_id, line_id, variant, text) 列表。"""
    data = json.loads(DIALOGUES.read_text(encoding="utf-8"))
    items = []
    for dialogue in data.get("dialogues", []):
        npc_id = dialogue.get("npc_id") or dialogue.get("id", "")
        for line in dialogue.get("lines", []):
            line_id = line.get("id", "")
            texts = line.get("texts")
            if not texts:
                # 条目直接写 text 的,当第 0 个变体
                items.append((npc_id, line_id, 0, line.get("text", "")))
                continue
            for idx, variant in enumerate(texts):
                items.append((npc_id, line_id, idx, variant.get("text", "")))
    return [(n, l, v, t) for (n, l, v, t) in items if t.strip()]


def synth_macos(text: str, out_path: Path) -> bool:
    if not shutil.which("say") or not shutil.which("afconvert"):
        return False
    with tempfile.TemporaryDirectory() as tmp:
        aiff = Path(tmp) / "line.aiff"
        wav_tmp = Path(tmp) / "line.wav"
        proc = subprocess.run(
            ["say", "-v", MAC_VOICE, "-o", str(aiff), text],
            capture_output=True, text=True)
        if proc.returncode != 0:
            print("  ! say 失败: %s" % proc.stderr.strip()[:120])
            return False
        proc = subprocess.run(
            ["afconvert", "-f", "WAVE", "-d", "LEI16@22050", "-c", "1",
             str(aiff), str(wav_tmp)],
            capture_output=True, text=True)
        if proc.returncode != 0:
            print("  ! afconvert 失败: %s" % proc.stderr.strip()[:120])
            return False
        out_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(wav_tmp, out_path)
    return True


def synth_espeak(text: str, out_path: Path) -> bool:
    if not shutil.which("espeak-ng"):
        return False
    out_path.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        ["espeak-ng", "-v", ESPEAK_VOICE, "-s", "150", "-w", str(out_path), text],
        capture_output=True, text=True)
    return proc.returncode == 0


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="只列出条目,不生成")
    ap.add_argument("--force", action="store_true", help="已存在的也重录")
    ap.add_argument("--out", default=str(OUT_DIR))
    args = ap.parse_args(argv[1:])

    items = collect()
    out_dir = Path(args.out)
    if args.list:
        for npc_id, line_id, variant, text in items:
            print("%s  %s" % (voice_key(npc_id, line_id, variant), text))
        print("共 %d 条" % len(items))
        return 0

    if not shutil.which("say") and not shutil.which("espeak-ng"):
        print("! 本机没有可用的 TTS(macOS 的 say 或 espeak-ng),跳过语音生成")
        return 0

    made = 0
    skipped = 0
    for npc_id, line_id, variant, text in items:
        key = voice_key(npc_id, line_id, variant)
        out_path = out_dir / ("%s.wav" % key)
        if out_path.exists() and not args.force:
            skipped += 1
            continue
        ok = synth_macos(text, out_path)
        if not ok:
            ok = synth_espeak(text, out_path)
        if ok:
            made += 1
            print("  ✓ %s" % key)
        else:
            print("  ✗ %s 生成失败" % key)
    print("语音包:新生成 %d 条,复用 %d 条 → %s" % (made, skipped, out_dir))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
