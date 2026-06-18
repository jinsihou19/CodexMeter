import XCTest
@testable import CodexUsageShared

final class DirectCodexUsageClientTests: XCTestCase {
    func testFetchesWhamUsageWithCodexAuthToken() async throws {
        let authFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("auth.json")
        try FileManager.default.createDirectory(
            at: authFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {"tokens":{"access_token":"test-access-token"}}
        """.write(to: authFile, atomically: true, encoding: .utf8)
        let recorder = RequestRecorder(responseBody: """
        {
          "plan_type": "prolite",
          "rate_limit": {
            "allowed": true,
            "limit_reached": false,
            "primary_window": {
              "used_percent": 13,
              "limit_window_seconds": 18000,
              "reset_after_seconds": 15000,
              "reset_at": 1779967655
            },
            "secondary_window": {
              "used_percent": 15,
              "limit_window_seconds": 604800,
              "reset_at": 1780392047
            }
          },
          "additional_rate_limits": [{
            "limit_name": "GPT-5.3-Codex-Spark",
            "metered_feature": "codex_bengalfox",
            "rate_limit": {
              "primary_window": {
                "used_percent": 0,
                "limit_window_seconds": 18000,
                "reset_after_seconds": 18000,
                "reset_at": 1779969999
              },
              "secondary_window": {
                "used_percent": 2,
                "limit_window_seconds": 604800,
                "reset_after_seconds": 604800,
                "reset_at": 1780399999
              }
            }
          }],
          "credits": {
            "has_credits": false,
            "unlimited": false,
            "balance": "0"
          },
          "rate_limit_reached_type": null
        }
        """)
        let client = DirectCodexUsageClient(
            authFileURL: authFile,
            endpointURL: URL(string: "https://example.test/backend-api/wham/usage")!,
            transport: recorder.transport
        )

        let snapshot = try await client.fetchRateLimits()

        XCTAssertEqual(snapshot.limitId, "codex")
        XCTAssertEqual(snapshot.planType, "prolite")
        XCTAssertEqual(snapshot.primary?.remainingPercent, 87)
        XCTAssertEqual(snapshot.primary?.windowDurationMins, 300)
        XCTAssertEqual(snapshot.primary?.resetsAt, 1_779_967_655)
        XCTAssertEqual(snapshot.primary?.resetAfterSeconds, 15_000)
        XCTAssertEqual(snapshot.secondary?.remainingPercent, 85)
        XCTAssertEqual(snapshot.secondary?.windowDurationMins, 10_080)
        XCTAssertEqual(snapshot.secondary?.resetsAt, 1_780_392_047)
        XCTAssertEqual(snapshot.additionalLimits.first?.displayName, "GPT-5.3-Codex-Spark")
        XCTAssertEqual(snapshot.additionalLimits.first?.primary?.remainingPercent, 100)
        XCTAssertEqual(snapshot.additionalLimits.first?.secondary?.remainingPercent, 98)
        XCTAssertEqual(snapshot.credits?.hasCredits, false)
        XCTAssertEqual(snapshot.credits?.unlimited, false)
        XCTAssertEqual(snapshot.credits?.balance, "0")
        XCTAssertEqual(recorder.authorizationHeader, "Bearer test-access-token")
        XCTAssertEqual(recorder.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(recorder.cacheControlHeader, "no-store")
        XCTAssertEqual(recorder.pragmaHeader, "no-cache")
        XCTAssertEqual(recorder.requestURL?.absoluteString, "https://example.test/backend-api/wham/usage")
    }

    func testFetchesUsageSnapshotWithCodexProfileStats() async throws {
        let authFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("auth.json")
        try FileManager.default.createDirectory(
            at: authFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {"tokens":{"access_token":"test-access-token"}}
        """.write(to: authFile, atomically: true, encoding: .utf8)
        let recorder = RequestRecorder(responseBodiesByPath: [
            "/backend-api/wham/usage": """
            {
              "plan_type": "prolite",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 43,
                  "limit_window_seconds": 18000,
                  "reset_after_seconds": 8280,
                  "reset_at": 1779967655
                },
                "secondary_window": {
                  "used_percent": 11,
                  "limit_window_seconds": 604800,
                  "reset_after_seconds": 604800,
                  "reset_at": 1780392047
                }
              }
            }
            """,
            "/backend-api/wham/profiles/me": """
            {
              "stats": {
                "lifetime_tokens": 2018581714,
                "peak_daily_tokens": 226093858,
                "longest_running_turn_sec": 42520,
                "current_streak_days": 1,
                "longest_streak_days": 18,
                "fast_mode_usage_percentage": 0.57142857142857,
                "most_used_reasoning_effort": "xhigh",
                "most_used_reasoning_effort_percentage": 76.34682817978961,
                "total_threads": 249,
                "total_skills_used": 329,
                "unique_skills_used": 27,
                "daily_usage_buckets": [
                  {"start_date": "2026-06-14", "tokens": 1000},
                  {"start_date": "2026-06-15", "tokens": 2000}
                ],
                "weekly_usage_buckets": [
                  {"start_date": "2026-06-15", "tokens": 3000}
                ],
                "cumulative_daily_usage_buckets": [
                  {"start_date": "2026-06-15", "tokens": 4000}
                ],
                "top_invocations": [
                  {"type": "plugin", "plugin_id": null, "plugin_name": "superpowers", "skill_id": null, "skill_name": null, "usage_count": 221}
                ]
              }
            }
            """
        ])
        let client = DirectCodexUsageClient(
            authFileURL: authFile,
            endpointURL: URL(string: "https://example.test/backend-api/wham/usage")!,
            profileEndpointURL: URL(string: "https://example.test/backend-api/wham/profiles/me")!,
            transport: recorder.transport
        )

        let snapshot = try await client.fetchUsageSnapshot()

        XCTAssertEqual(snapshot.rateLimits.primary?.remainingPercent, 57)
        XCTAssertEqual(snapshot.rateLimits.primary?.paceDeltaPercent(now: Date(timeIntervalSince1970: 1_779_960_000)), -11)
        XCTAssertEqual(snapshot.profileStats?.lifetimeTokens, 2_018_581_714)
        XCTAssertEqual(snapshot.profileStats?.peakDailyTokens, 226_093_858)
        XCTAssertEqual(snapshot.profileStats?.longestRunningTurnSeconds, 42_520)
        XCTAssertEqual(snapshot.profileStats?.latestDailyTokens, 2_000)
        XCTAssertEqual(snapshot.profileStats?.recentDailyTokens, 3_000)
        XCTAssertEqual(snapshot.profileStats?.topInvocations.first?.displayName, "superpowers")
        XCTAssertEqual(Set(recorder.requestURLs.map(\.path)), [
            "/backend-api/wham/usage",
            "/backend-api/wham/profiles/me"
        ])
    }

    func testMissingAuthFileProducesDisplayableError() async {
        let client = DirectCodexUsageClient(
            authFileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent("auth.json")
        )

        do {
            _ = try await client.fetchRateLimits()
            XCTFail("Expected missing auth file to throw")
        } catch {
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "找不到 Codex 登录信息。请先在 Codex 登录 ChatGPT。")
        }
    }

    func testDefaultTimeoutLeavesRoomForProxiedUsageEndpoint() throws {
        let timeout = try XCTUnwrap(Mirror(reflecting: DirectCodexUsageClient()).children.first { child in
            child.label == "timeoutSeconds"
        }?.value as? TimeInterval)

        XCTAssertGreaterThanOrEqual(timeout, 45)
    }

    func testIntegrationFetchesWhamUsageWhenEnabled() async throws {
        let integrationFlag = ProcessInfo.processInfo.environment["CODEX_USAGE_RUN_INTEGRATION"]
            ?? Bundle(for: Self.self).object(forInfoDictionaryKey: "CODEX_USAGE_RUN_INTEGRATION") as? String
        guard integrationFlag == "1" else {
            throw XCTSkip("Set CODEX_USAGE_RUN_INTEGRATION=1 to exercise the direct Codex usage endpoint. Current value: \(integrationFlag ?? "<nil>")")
        }

        let snapshot = try await DirectCodexUsageClient().fetchRateLimits()

        XCTAssertEqual(snapshot.limitId, "codex")
        XCTAssertNotNil(snapshot.primary)
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let responseBodiesByPath: [String: String]
    private let queue = DispatchQueue(label: "CodexUsageTests.RequestRecorder")
    private var recordedAuthorizationHeader: String?
    private var recordedCachePolicy: URLRequest.CachePolicy?
    private var recordedCacheControlHeader: String?
    private var recordedPragmaHeader: String?
    private var recordedRequestURL: URL?
    private var recordedRequestURLs: [URL] = []

    init(responseBody: String) {
        self.responseBodiesByPath = ["*": responseBody]
    }

    init(responseBodiesByPath: [String: String]) {
        self.responseBodiesByPath = responseBodiesByPath
    }

    var authorizationHeader: String? {
        queue.sync { recordedAuthorizationHeader }
    }

    var cachePolicy: URLRequest.CachePolicy? {
        queue.sync { recordedCachePolicy }
    }

    var cacheControlHeader: String? {
        queue.sync { recordedCacheControlHeader }
    }

    var pragmaHeader: String? {
        queue.sync { recordedPragmaHeader }
    }

    var requestURL: URL? {
        queue.sync { recordedRequestURL }
    }

    var requestURLs: [URL] {
        queue.sync { recordedRequestURLs }
    }

    func transport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let responseBody = responseBodiesByPath[request.url?.path ?? ""] ?? responseBodiesByPath["*"] ?? "{}"
        queue.sync {
            recordedAuthorizationHeader = request.value(forHTTPHeaderField: "Authorization")
            recordedCachePolicy = request.cachePolicy
            recordedCacheControlHeader = request.value(forHTTPHeaderField: "Cache-Control")
            recordedPragmaHeader = request.value(forHTTPHeaderField: "Pragma")
            recordedRequestURL = request.url
            if let url = request.url {
                recordedRequestURLs.append(url)
            }
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(responseBody.utf8), response)
    }
}
