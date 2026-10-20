// 验证 OpenCode Go 官方响应、凭据边界和启停刷新生命周期，所有凭据均为测试值。
import XCTest
import CodexMeterShared

/// 使用真实解析器和 URLSession 替身验证请求，避免测试依赖用户账户或收费调用。
final class OpenCodeGoTests: XCTestCase {
    /// Go 与 Codex 共用布局保存、图标拆分、双行堆叠、宽度和禁用过滤，缺失窗口不补假值。
    func testGoTokensParticipateInSharedMenuBarLayout() throws {
        let layout = MenuBarLayout(items: [
            [.icon], [.openCodeGoIcon, .openCodeGoPrimary],
            [.openCodeGoSecondary, .openCodeGoMonthly], [.openCodeGoProvider]
        ])
        XCTAssertEqual(layout.items[1], [.openCodeGoIcon])
        XCTAssertEqual(try JSONDecoder().decode(MenuBarLayout.self, from: JSONEncoder().encode(layout)), layout)
        let snapshot = try OpenCodeGoClient.parse(data: Data(#"{"usage":{"rolling":{"percent":25},"weekly":{"percent":50},"monthly":{"percent":90}}}"#.utf8))
        let settings = MenuBarDisplaySettings()
        let enabled = MenuBarLayoutDisplay(
            layout: layout, snapshot: nil, settings: settings,
            openCodeGoEnabled: true, openCodeGoSnapshot: snapshot
        )
        XCTAssertEqual(enabled.codexLines.map(\.value), ["75%", "50%", "10%", "OpenCode Go"])
        XCTAssertTrue(enabled.codexLines.prefix(3).allSatisfy(\.usesUsageColor))
        XCTAssertFalse(try XCTUnwrap(enabled.codexLines.last).usesUsageColor)
        XCTAssertEqual(enabled.items[3].count, 2)
        let disabled = MenuBarLayoutDisplay(
            layout: layout, snapshot: nil, settings: settings,
            openCodeGoEnabled: false, openCodeGoSnapshot: snapshot
        )
        XCTAssertEqual(disabled.items, [[.icon]])
        XCTAssertGreaterThan(
            StatusBarDisplayMetrics.statusItemWidth(for: layout, display: enabled, settings: settings),
            StatusBarDisplayMetrics.statusItemWidth(for: layout, display: disabled, settings: settings)
        )
        let incomplete = try OpenCodeGoClient.parse(data: Data(#"{"usage":{"rolling":{"percent":25}}}"#.utf8))
        XCTAssertNil(StatusLineDisplay.layoutOpenCodeGoLine(for: .openCodeGoMonthly, snapshot: incomplete, settings: settings))
        let removed = MenuBarLayoutDisplay(
            layout: MenuBarLayout(items: [[.icon]]), snapshot: nil, settings: settings,
            openCodeGoEnabled: true, openCodeGoSnapshot: snapshot
        )
        XCTAssertEqual(removed.items, [[.icon]])
    }

    /// 派生显示复用真实窗口；服务端缺少重置时间时不生成预测与倒计时。
    func testDerivedQuotaItemsAndMissingReset() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = try OpenCodeGoClient.parse(data: Data(#"{"usage":{"rolling":{"percent":25,"resetInSec":9000},"weekly":{"percent":50,"resetInSec":302400}}}"#.utf8), now: now)
        let settings = MenuBarDisplaySettings()
        XCTAssertEqual(StatusLineDisplay.layoutOpenCodeGoLine(for: .openCodeGoPaceRemaining, snapshot: snapshot, settings: settings, now: now)?.value, "75%")
        for token: MenuBarLayoutToken in [.openCodeGoFiveHourPaceDelta, .openCodeGoWeeklyPaceDelta, .openCodeGoResetCountdown, .openCodeGoResetTime, .openCodeGoDepletionETA] {
            XCTAssertNotNil(StatusLineDisplay.layoutOpenCodeGoLine(for: token, snapshot: snapshot, settings: settings, now: now))
        }
        XCTAssertEqual(StatusLineDisplay.layoutOpenCodeGoUsageBar(snapshot: snapshot)?.windows.map(\.remainingPercent), [75, 50])
        let incomplete = try OpenCodeGoClient.parse(data: Data(#"{"usage":{"rolling":{"percent":25}}}"#.utf8), now: now)
        for token: MenuBarLayoutToken in [.openCodeGoPaceDelta, .openCodeGoResetCountdown, .openCodeGoResetTime, .openCodeGoDepletionETA] {
            XCTAssertNil(StatusLineDisplay.layoutOpenCodeGoLine(for: token, snapshot: incomplete, settings: settings, now: now))
        }
        let layout = MenuBarLayout(items: MenuBarLayoutToken.openCodeGoTokens.map { [$0] })
        XCTAssertEqual(try JSONDecoder().decode(MenuBarLayout.self, from: JSONEncoder().encode(layout)), layout)
    }

    /// Go 的真实窗口沿用共用消耗规则：刚重置、关闭预期或未知月周期时均不伪造速度。
    func testGoWindowsUseSharedPaceRules() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = try OpenCodeGoClient.parse(data: Data(#"{"usage":{"rolling":{"percent":25,"resetInSec":9000},"weekly":{"percent":0,"resetInSec":604800},"monthly":{"percent":11,"resetInSec":172800}}}"#.utf8), now: now)
        let rolling = try XCTUnwrap(snapshot.windows.first?.quota)
        let pace = try XCTUnwrap(UsageWindowPaceDisplay(id: "rolling", title: "5 小时", window: rolling, now: now, weeklyProgressWorkDays: 5)?.display)
        XCTAssertEqual(pace.deltaPercent, -25)
        XCTAssertNil(UsageWindowPaceDisplay(id: "rolling", title: "5 小时", window: rolling, now: now, weeklyProgressWorkDays: 0))
        for window in snapshot.windows.dropFirst() {
            XCTAssertNil(UsageWindowPaceDisplay(id: window.id, title: window.title, window: window.quota, now: now, weeklyProgressWorkDays: 5))
        }
    }

    /// 官方的百分比不是比例；周/月缺失不补零，ISO 日期与相对重置均保留真实语义。
    func testOfficialWindowsAndInvalidPayloads() throws {
        let data = Data(#"{"usage":{"rolling":{"percent":0.5,"resetsAt":"2026-09-22T12:00:00.000Z"},"weekly":{"percent":75,"resetInSec":600},"monthly":{"percent":91,"resetsAt":1790078400000}}}"#.utf8)
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = try OpenCodeGoClient.parse(data: data, now: now)
        XCTAssertEqual(snapshot.windows.map(\.id), ["rolling", "weekly", "monthly"])
        XCTAssertEqual(snapshot.windows[0].quota.usedPercent, 0.5)
        XCTAssertEqual(snapshot.windows[0].quota.resetsAt, 1_790_078_400)
        XCTAssertEqual(snapshot.windows[1].quota.resetsAt, 1_600)
        XCTAssertEqual(snapshot.windows[2].quota.resetsAt, 1_790_078_400)
        XCTAssertNil(snapshot.windows[2].quota.windowDurationMins)
        let onlyRolling = try OpenCodeGoClient.parse(data: Data(#"{"usage":{"rolling":{"used":1,"limit":200}}}"#.utf8))
        XCTAssertEqual(onlyRolling.windows.count, 1)
        XCTAssertEqual(onlyRolling.windows[0].quota.usedPercent, 0.5)
        XCTAssertNil(onlyRolling.windows[0].quota.resetsAt)
        for json in [#"{}"#, #"{"usage":{"rolling":{"percent":true}}}"#,
                     #"{"usage":{"rolling":{"percent":-1}}}"#,
                     #"{"usage":{"rolling":{"percent":1,"resetInSec":1e99}}}"#,
                     #"{"usage":{"rolling":{"percent":1},"weekly":{}}}"#] {
            XCTAssertThrowsError(try OpenCodeGoClient.parse(data: Data(json.utf8)))
        }
    }

    /// 凭据仅从 Go 专属 API 登录项读取，覆盖 XDG 路径、环境变量优先和拒绝 Zen/OAuth。
    func testAutomaticCredentialsStayScopedToGo() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = home.appendingPathComponent("data/opencode")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let path = directory.appendingPathComponent("auth.json")
        let environment = ["XDG_DATA_HOME": home.appendingPathComponent("data").path]
        try Data(#"{"opencode":{"type":"api","key":"zen"}}"#.utf8).write(to: path)
        XCTAssertThrowsError(try OpenCodeGoCredentials.automaticKey(environment: environment, home: home))
        try Data(#"{"opencode-go":{"type":"api","key":"go-test"}}"#.utf8).write(to: path)
        XCTAssertEqual(try OpenCodeGoCredentials.automaticKey(environment: environment, home: home), "go-test")
        XCTAssertEqual(try OpenCodeGoCredentials.automaticKey(environment: ["OPENCODE_API_KEY": " env-test "], home: home), "env-test")
        try Data(#"{"opencode-go":{"type":"oauth","key":"not-api"}}"#.utf8).write(to: path)
        XCTAssertThrowsError(try OpenCodeGoCredentials.automaticKey(environment: environment, home: home))
    }

    /// 请求必须命中官方只读端点且使用 Bearer；401 与服务失败不被解析为正常额度。
    func testRequestAndHTTPFailures() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenCodeGoTestProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); OpenCodeGoTestProtocol.handler = nil }
        OpenCodeGoTestProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://opencode.ai/zen/go/v1/usage")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-go")
            return (200, Data(#"{"usage":{"rolling":{"percent":32}}}"#.utf8))
        }
        let result = try await OpenCodeGoClient().fetch(apiKey: " test-go ", session: session)
        XCTAssertEqual(result.windows.first?.quota.remainingPercent, 68)
        for status in [401, 403, 429, 500, 302] {
            OpenCodeGoTestProtocol.handler = { _ in (status, Data("credential-must-not-leak".utf8)) }
            do {
                _ = try await OpenCodeGoClient().fetch(apiKey: "test-go", session: session)
                XCTFail("Expected HTTP error")
            } catch {
                XCTAssertFalse(error.localizedDescription.contains("credential-must-not-leak"))
                if status == 401 || status == 403 {
                    guard case OpenCodeGoError.invalidKey = error else { return XCTFail("Expected invalid key") }
                }
            }
        }
    }

    /// 同一凭据失败保留旧值且显示错误；换凭据先清旧数据，关闭后清空并停止请求。
    @MainActor func testRefreshFailureCredentialChangeAndDisable() async throws {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("manual", forKey: AppBehaviorPreferenceKeys.refreshCadence)
        var key = "first"
        var fail = false
        var calls = 0
        let expected = try OpenCodeGoClient.parse(data: Data(#"{"usage":{"rolling":{"percent":25}}}"#.utf8))
        let store = OpenCodeGoStore(defaults: defaults, keyProvider: { key }, fetcher: { _ in
            calls += 1
            if fail { throw OpenCodeGoError.http(500) }
            return expected
        })
        store.isEnabled = true
        await store.refresh()
        XCTAssertEqual(store.snapshot, expected)
        fail = true
        await store.refresh()
        XCTAssertEqual(store.snapshot, expected)
        XCTAssertNotNil(store.errorMessage)
        key = "second"
        await store.refresh()
        XCTAssertNil(store.snapshot)
        store.isEnabled = false
        await store.refresh()
        XCTAssertEqual(calls, 3)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isRefreshing)
    }

    /// 不响应取消的请求也不能在关闭后回填；重复刷新共用同一请求。
    @MainActor func testDisableDiscardsInFlightResultAndCoalescesRefresh() async throws {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("manual", forKey: AppBehaviorPreferenceKeys.refreshCadence)
        let started = expectation(description: "request started")
        var continuation: CheckedContinuation<OpenCodeGoSnapshot, Never>?
        var calls = 0
        let store = OpenCodeGoStore(defaults: defaults, keyProvider: { "test-go" }, fetcher: { _ in
            calls += 1
            return await withCheckedContinuation { continuation = $0; started.fulfill() }
        })
        store.isEnabled = true
        let first = Task { await store.refresh() }
        await fulfillment(of: [started], timeout: 2)
        let second = Task { await store.refresh() }
        await Task.yield()
        store.isEnabled = false
        continuation?.resume(returning: try OpenCodeGoClient.parse(data: Data(#"{"usage":{"rolling":{"percent":25}}}"#.utf8)))
        await first.value
        await second.value
        XCTAssertEqual(calls, 1)
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.isRefreshing)
    }
}

/// 测试专用传输层，返回内存响应，不连接网络。
private final class OpenCodeGoTestProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    /// 拦截注入 session 中的全部测试请求。
    override class func canInit(with request: URLRequest) -> Bool { true }
    /// 保留请求内容供断言检查。
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    /// 用指定状态与 JSON 数据完成一次请求。
    override func startLoading() {
        let (status, data) = Self.handler!(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    /// 响应已同步完成，无需额外取消资源。
    override func stopLoading() {}
}
