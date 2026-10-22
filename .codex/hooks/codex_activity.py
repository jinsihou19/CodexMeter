#!/usr/bin/env python3
"""项目 Hook 只转交已安装的原生处理器，所有写入共用文件锁与回合状态机。"""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys


def main() -> int:
    """保留 stdin 和原生退出协议；未安装或执行失败时静默降级，不启动 App 界面或自行写状态。"""
    data = sys.stdin.buffer.read()
    executable = Path(os.environ.get(
        "CODEX_METER_HOOK_EXECUTABLE",
        "/Applications/CodexMeter.app/Contents/MacOS/CodexMeter",
    ))
    try:
        if executable.is_file():
            result = subprocess.run(
                [str(executable), "--codexmeter-activity-hook"],
                input=data, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=1.5,
            )
            if result.returncode == 0:
                sys.stdout.buffer.write(result.stdout)
                return 0
    except (OSError, subprocess.TimeoutExpired):
        pass
    try:
        if json.loads(data).get("hook_event_name") in {"Stop", "SubagentStop"}:
            print('{"continue":true}')
    except (ValueError, AttributeError):
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
