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
              "reset_at": 1779967655
            },
            "secondary_window": {
              "used_percent": 15,
              "limit_window_seconds": 604800,
              "reset_at": 1780392047
            }
          },
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
        XCTAssertEqual(snapshot.secondary?.remainingPercent, 85)
        XCTAssertEqual(snapshot.secondary?.windowDurationMins, 10_080)
        XCTAssertEqual(snapshot.secondary?.resetsAt, 1_780_392_047)
        XCTAssertEqual(snapshot.credits?.hasCredits, false)
        XCTAssertEqual(snapshot.credits?.unlimited, false)
        XCTAssertEqual(snapshot.credits?.balance, "0")
        XCTAssertEqual(recorder.authorizationHeader, "Bearer test-access-token")
        XCTAssertEqual(recorder.requestURL?.absoluteString, "https://example.test/backend-api/wham/usage")
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
    private let responseBody: String
    private let queue = DispatchQueue(label: "CodexUsageTests.RequestRecorder")
    private var recordedAuthorizationHeader: String?
    private var recordedRequestURL: URL?

    init(responseBody: String) {
        self.responseBody = responseBody
    }

    var authorizationHeader: String? {
        queue.sync { recordedAuthorizationHeader }
    }

    var requestURL: URL? {
        queue.sync { recordedRequestURL }
    }

    func transport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        queue.sync {
            recordedAuthorizationHeader = request.value(forHTTPHeaderField: "Authorization")
            recordedRequestURL = request.url
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
