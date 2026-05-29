# CodexUsage

macOS menu bar app plus WidgetKit widget for showing the local Codex quota snapshot.

## What It Shows

- Menu bar title: `5h 83%` and `7d 89%`
- Popover: plan type, 5 hour remaining quota, 7 day remaining quota, reset times, credits status, last sync time
- Desktop widget: latest cached 5 hour and 7 day quota snapshot

## Data Source

The app reads the local Codex auth token from `CODEX_HOME/auth.json` or `~/.codex/auth.json` and calls:

1. `GET https://chatgpt.com/backend-api/wham/usage`

The token is used only in memory for the request. There is no secondary data source or fallback client.

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

This workspace currently has no valid macOS code signing identity. The project uses automatic signing and App Group `group.com.jinsihou.CodexUsage`; open the project in Xcode and select a development team for both app targets to install the WidgetKit widget normally.
