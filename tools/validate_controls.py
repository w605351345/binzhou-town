#!/usr/bin/env python3
"""校验手柄映射、Steam Input 模板与项目配置一致。

文档曾经把肩键、摇杆按下和 START/BACK 写反，而 GDScript 测试只检查
"有没有绑定"，无法发现文案漂移。本脚本以 project.godot 为唯一真相，
同时检查 Steam 模板是否同步，以及游戏动作之间是否抢占同一条手柄按钮。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


PROJECT_FILE = Path("project.godot")
STEAM_TEMPLATE = Path("steam/controller_ui.txt")


def _read(path: Path) -> str:
    if not path.is_file():
        raise SystemExit(f"❌ 缺少文件: {path}")
    return path.read_text(encoding="utf-8")


def parse_joypad_actions(path: Path) -> dict[str, int]:
    """解析 Godot 配置片段里的动作 → JoyButton 编号。"""
    text = _read(path)
    actions: dict[str, int] = {}
    for match in re.finditer(
        r"^([a-z_]+)=\{\n\"deadzone\".*?^\}", text, re.MULTILINE | re.DOTALL
    ):
        action = match.group(1)
        button = re.search(
            r"InputEventJoypadButton.*?button_index\":(\d+)", match.group(0)
        )
        if button:
            actions[action] = int(button.group(1))
    return actions


def main() -> int:
    project = parse_joypad_actions(PROJECT_FILE)
    steam = parse_joypad_actions(STEAM_TEMPLATE)

    required = {
        "move_left", "move_right", "move_up", "move_down",
        "interact",
        "tool_till", "tool_water", "tool_seed", "tool_harvest", "tool_plough",
        "sleep", "travel", "travel_post", "ui_pause", "ui_inventory",
    }
    missing = sorted(required - project.keys())
    if missing:
        print(f"❌ project.godot 缺少手柄动作: {', '.join(missing)}")
        return 1

    mismatched = sorted(
        action for action in required if project.get(action) != steam.get(action)
    )
    if mismatched:
        print("❌ Steam 模板与 project.godot 不一致:")
        for action in mismatched:
            print(f"  · {action}: project={project.get(action)} steam={steam.get(action)}")
        return 1

    owners: dict[int, str] = {}
    conflicts: list[str] = []
    for action in sorted(required):
        button = project[action]
        if button in owners:
            conflicts.append(f"{owners[button]} 与 {action} 都占用 {button} 号按钮")
        else:
            owners[button] = action
    if conflicts:
        print("❌ 游戏动作手柄按钮冲突:")
        for conflict in conflicts:
            print(f"  · {conflict}")
        return 1

    print(f"✅ 控件校验通过: {len(required)} 个游戏动作与 Steam 模板一致，无按钮冲突")
    return 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    raise SystemExit(main())
