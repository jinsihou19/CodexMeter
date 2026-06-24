# CodexUsage

macOS menu bar app plus WidgetKit widget for showing Codex quota and profile usage.

Requires macOS 26.0 or newer because the menu bar activity glyph can use the latest SF Symbols Draw effects.

## What It Shows

- Menu bar item: 5 hour and 7 day quota digits, with an optional selectable Codex lifecycle activity glyph while Codex is active
- Popover: plan type, 5 hour remaining quota, 7 day remaining quota, reset credit cards, extra Codex Spark limits, reset times, credits status, token activity, profile stats, common plugins, and last sync time
- Desktop widget: latest cached 5 hour and 7 day quota snapshot

## Data Source

The app reads the local Codex auth token from `CODEX_HOME/auth.json` or `~/.codex/auth.json` and calls:

1. `GET https://chatgpt.com/backend-api/wham/usage`
2. `GET https://chatgpt.com/backend-api/wham/profiles/me`
3. `GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits`

The token is used only in memory for the request. There is no local Codex log scanner or process-based fallback client.

## Codex Hook Activity

This repo includes a project-local hook bridge:

- `.codex/hooks.json`
- `.codex/hooks/codex_activity.py`

After Codex trusts the project hooks through `/hooks`, the script writes a small JSON status file to:

```text
~/Library/Group Containers/group.com.jinsihou.CodexUsage/CodexUsage/codex-activity.json
```

The menu bar app polls that file and can display a compact animated activity glyph beside the quota digits while Codex is running, thinking, waiting for confirmation, or briefly after completion. The status file keeps one lightweight entry per Codex session/turn, so the menu bar glyph aggregates concurrent work and speeds up its SF Symbols animation as more sessions are active. Users can choose automatic state-based glyphs, a vertical ellipsis, `target`, or `aqi.medium`; glyph colors always follow the highest-priority current hook state. The hook script exits quietly and does not send prompt text, transcript contents, or tool output to the app.

## Build And Test

```bash
rtk xcodebuild -project CodexUsage.xcodeproj -scheme CodexUsage -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
rtk xcodebuild -project CodexUsage.xcodeproj -scheme CodexUsage -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

Run the direct Codex usage endpoint integration test:

```bash
rtk xcodebuild -project CodexUsage.xcodeproj -scheme CodexUsage -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO CODEX_USAGE_RUN_INTEGRATION=1
```

## Signing

Debug uses automatic Apple Development signing with App Group `group.com.jinsihou.CodexUsage`.

Release is configured for ad-hoc signing (`CODE_SIGN_IDENTITY = -`). Release also disables Hardened Runtime and clears the app and widget entitlement files because App Group entitlements require a provisioning profile, and Hardened Runtime library validation can reject embedded ad-hoc frameworks at launch. This is useful for local or small-scope testing, but it is not a notarized Developer ID distribution build and may still be blocked by Gatekeeper after internet download.
