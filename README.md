# CodexUsage

macOS menu bar app plus WidgetKit widget for showing Codex quota and profile usage.

## What It Shows

- Menu bar title: usage pace like `43% · -11%`, with a setting to switch back to `5h 83%` and `7d 89%`
- Popover: plan type, 5 hour remaining quota, 7 day remaining quota, extra Codex Spark limits, reset times, credits status, token activity, profile stats, common plugins, and last sync time
- Desktop widget: latest cached 5 hour and 7 day quota snapshot

## Data Source

The app reads the local Codex auth token from `CODEX_HOME/auth.json` or `~/.codex/auth.json` and calls:

1. `GET https://chatgpt.com/backend-api/wham/usage`
2. `GET https://chatgpt.com/backend-api/wham/profiles/me`

The token is used only in memory for the request. There is no local Codex log scanner or process-based fallback client.

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
