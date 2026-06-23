#!/usr/bin/env python3
"""把 Codex 生命周期 hook 事件压缩成菜单栏 App 可读取的活动状态。"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path
from typing import Any


APP_GROUP_ID = "group.com.jinsihou.CodexUsage"
STATE_FILE_NAME = "codex-activity.json"
STATE_EXPIRATION_SECONDS = {
    "idle": 3,
    "succeeded": 5,
    "completed": 5,
    "failed": 18,
    "thinking": 60,
    "running": 60,
    "waitingApproval": 60,
    "compacting": 60,
}


def activity_file_path() -> Path:
    """返回状态文件路径；允许环境变量覆盖，方便调试和测试。"""
    override_path = os.environ.get("CODEX_USAGE_ACTIVITY_FILE")
    if override_path:
        return Path(override_path).expanduser()
    return (
        Path.home()
        / "Library"
        / "Group Containers"
        / APP_GROUP_ID
        / "CodexUsage"
        / STATE_FILE_NAME
    )


def read_hook_payload() -> dict[str, Any]:
    """读取 Codex 从 stdin 传入的单个 JSON 对象；异常时返回空事件。"""
    raw_input = sys.stdin.read()
    if not raw_input.strip():
        return {}
    try:
        payload = json.loads(raw_input)
    except json.JSONDecodeError:
        return {}
    return payload if isinstance(payload, dict) else {}


def tool_response_failed(tool_response: Any) -> bool:
    """尽量从不同工具输出形状里识别失败信号，不依赖不稳定的完整 transcript。"""
    if not isinstance(tool_response, dict):
        return False

    for key in ("exit_code", "exitCode", "status_code", "statusCode", "code"):
        value = tool_response.get(key)
        if isinstance(value, int) and value != 0:
            return True

    if tool_response.get("success") is False or tool_response.get("error"):
        return True

    nested_response = tool_response.get("result") or tool_response.get("response")
    if isinstance(nested_response, dict) and nested_response is not tool_response:
        return tool_response_failed(nested_response)

    return False


def state_for_event(payload: dict[str, Any]) -> tuple[str, str]:
    """把 hook 事件映射成 UI 状态和短消息，供菜单栏状态灯直接展示。"""
    event_name = str(payload.get("hook_event_name") or "")
    tool_name = str(payload.get("tool_name") or "")

    if event_name == "SessionStart":
        return "idle", "Codex 会话已就绪"
    if event_name == "UserPromptSubmit":
        return "running", "任务已提交"
    if event_name == "PermissionRequest":
        return "waitingApproval", "等待权限确认"
    if event_name == "PreToolUse":
        return "running", f"准备运行 {tool_name}" if tool_name else "准备运行工具"
    if event_name == "PostToolUse":
        if tool_response_failed(payload.get("tool_response")):
            return "failed", f"{tool_name} 异常" if tool_name else "工具异常"
        return "thinking", f"{tool_name} 完成" if tool_name else "工具完成"
    if event_name in ("PreCompact", "PostCompact"):
        return "compacting", "整理上下文"
    if event_name == "SubagentStart":
        return "running", "子任务启动"
    if event_name == "SubagentStop":
        return "succeeded", "子任务完成"
    if event_name == "Stop":
        return "completed", "回合完成"
    return "thinking", event_name or "Codex 活动"


def compact_identifier(value: Any) -> str | None:
    """把 Codex 传入的可选 id 转成短字符串；空值不写入状态文件。"""
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def snapshot_key(snapshot: dict[str, Any]) -> str:
    """用 session/turn 组合定位一条活动记录；缺失时降级为稳定的全局键。"""
    session_id = compact_identifier(snapshot.get("sessionID")) or "global"
    turn_id = compact_identifier(snapshot.get("turnID"))
    if turn_id:
        return f"{session_id}:{turn_id}"
    return session_id


def snapshot_is_fresh(snapshot: Any, now: float) -> bool:
    """按状态 TTL 判断旧记录是否还应参与多会话聚合。"""
    if not isinstance(snapshot, dict):
        return False
    state = str(snapshot.get("state") or "")
    if state == "idle":
        return False
    updated_at = snapshot.get("updatedAt")
    if not isinstance(updated_at, (int, float)):
        return False
    expiration = STATE_EXPIRATION_SECONDS.get(state, 60)
    return now - float(updated_at) <= expiration


def load_activity_document(output_path: Path, now: float) -> dict[str, Any]:
    """读取现有状态文件；兼容旧版单 snapshot，并清理过期会话。"""
    try:
        existing = json.loads(output_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        existing = {}

    sessions: dict[str, Any] = {}
    if isinstance(existing, dict) and isinstance(existing.get("sessions"), dict):
        sessions = dict(existing["sessions"])
    elif isinstance(existing, dict) and "state" in existing:
        sessions[snapshot_key(existing)] = existing

    fresh_sessions = {
        key: value
        for key, value in sessions.items()
        if snapshot_is_fresh(value, now)
    }
    return {
        "schemaVersion": 2,
        "sessions": fresh_sessions,
    }


def write_activity_file(payload: dict[str, Any]) -> None:
    """用原子替换写入多会话状态文档，避免 App 读取到半截 JSON。"""
    state, message = state_for_event(payload)
    event_name = str(payload.get("hook_event_name") or "Unknown")
    tool_name = (
        compact_identifier(payload.get("tool_name"))
        or compact_identifier(payload.get("agent_type"))
        or compact_identifier(payload.get("source"))
    )
    snapshot = {
        "schemaVersion": 1,
        "state": state,
        "sessionID": compact_identifier(payload.get("session_id")),
        "turnID": compact_identifier(payload.get("turn_id")),
        "eventName": event_name,
        "toolName": tool_name,
        "message": message,
        "updatedAt": time.time(),
    }

    output_path = activity_file_path()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    document = load_activity_document(output_path, snapshot["updatedAt"])
    key = snapshot_key(snapshot)
    if state == "idle":
        document["sessions"].pop(key, None)
    else:
        document["sessions"][key] = snapshot

    temporary_path = output_path.with_suffix(f".{os.getpid()}.tmp")
    temporary_path.write_text(
        json.dumps(document, ensure_ascii=False, sort_keys=True),
        encoding="utf-8",
    )
    os.replace(temporary_path, output_path)


def main() -> int:
    """入口保持静默成功；状态灯失败不应该阻塞 Codex 主流程。"""
    payload = read_hook_payload()
    try:
        if payload:
            write_activity_file(payload)
    except OSError:
        pass

    # Stop/SubagentStop 要求 stdout 是 JSON；其他事件保持静默，避免污染上下文。
    if payload.get("hook_event_name") in {"Stop", "SubagentStop"}:
        print('{"continue": true}')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
