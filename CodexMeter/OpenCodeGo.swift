// OpenCode Go 官方额度读取、凭据存储和独立刷新生命周期；不使用本机成本推算订阅额度。
import Combine
import CodexMeterShared
import Foundation
import LocalAuthentication
import Security

/// 保存接口实际返回的窗口；月额度保留独立名称，不假定自然月恒为 30 天。
struct OpenCodeGoSnapshot: Equatable, Sendable {
    let windows: [Window]
    let fetchedAt: Date

    /// 以接口窗口名作为稳定标识，复用通用额度模型展示剩余和重置时间。
    struct Window: Identifiable, Equatable, Sendable {
        let id: String
        let quota: RateLimitWindow
        var title: String { ["rolling": "5 小时", "weekly": "7 天", "monthly": "月额度"][id] ?? id }
    }
}

/// 对用户只暴露可操作错误，不输出接口响应正文或凭据。
enum OpenCodeGoError: LocalizedError {
    case missingKey, invalidKey, invalidResponse, http(Int), keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingKey: "请先在 OpenCode 登录 OpenCode Go，或在设置中保存 API Key。"
        case .invalidKey: "OpenCode Go API Key 无效或无权读取额度，请检查凭据。"
        case .invalidResponse: "OpenCode Go 返回了无法识别的额度数据。"
        case .http(let status): "OpenCode Go 请求失败（HTTP \(status)）。"
        case .keychain(let status): "无法读写 OpenCode Go 钥匙串凭据（\(status)）。"
        }
    }
}

/// 仅访问官方 HTTPS 端点；禁止重定向携带凭据，URLSession 可注入以验证真实请求路径。
final class OpenCodeGoClient: NSObject, URLSessionTaskDelegate, Sendable {
    /// 拒绝重定向，避免令牌被意外转发到登录页或其他来源。
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    /// 拉取只读额度；空凭据、非成功状态和缺失窗口均抛错，不生成虚假的零用量。
    func fetch(apiKey: String, session: URLSession? = nil) async throws -> OpenCodeGoSnapshot {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("\n"), !key.contains("\r") else { throw OpenCodeGoError.missingKey }
        var request = URLRequest(url: URL(string: "https://opencode.ai/zen/go/v1/usage")!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let activeSession = session ?? URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { if session == nil { activeSession.invalidateAndCancel() } }
        let (data, response) = try await activeSession.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw OpenCodeGoError.invalidResponse }
        guard response.statusCode != 401, response.statusCode != 403 else { throw OpenCodeGoError.invalidKey }
        guard response.statusCode == 200 else { throw OpenCodeGoError.http(response.statusCode) }
        return try Self.parse(data: data)
    }

    /// 解析官方百分比和绝对重置时间；小于 1 的百分比仍是百分数，缺省周/月窗口保持缺省。
    static func parse(data: Data, now: Date = Date()) throws -> OpenCodeGoSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = root["usage"] as? [String: Any], usage["rolling"] is [String: Any] else {
            throw OpenCodeGoError.invalidResponse
        }
        let windows = try ["rolling", "weekly", "monthly"].compactMap { id -> OpenCodeGoSnapshot.Window? in
            guard let value = usage[id], !(value is NSNull) else { return nil }
            guard let fields = value as? [String: Any] else { throw OpenCodeGoError.invalidResponse }
            var percent = number(fields["percent"] ?? fields["usagePercent"] ?? fields["usedPercent"])
            if percent == nil, let used = number(fields["used"]), let limit = number(fields["limit"]), limit > 0 {
                percent = used / limit * 100
            }
            guard let percent, percent.isFinite, percent >= 0 else { throw OpenCodeGoError.invalidResponse }
            let reset: Int?
            if let raw = fields["resetsAt"] ?? fields["resetAt"], !(raw is NSNull) {
                guard let timestamp = timestamp(raw) else { throw OpenCodeGoError.invalidResponse }
                reset = timestamp
            } else if let raw = fields["resetInSec"], !(raw is NSNull) {
                guard let seconds = number(raw), seconds >= 0,
                      let timestamp = Int(exactly: (now.timeIntervalSince1970 + seconds).rounded(.down)) else {
                    throw OpenCodeGoError.invalidResponse
                }
                reset = timestamp
            } else {
                reset = nil
            }
            return .init(id: id, quota: RateLimitWindow(
                usedPercent: min(percent, 100),
                windowDurationMins: id == "rolling" ? 300 : (id == "weekly" ? 10_080 : nil),
                resetsAt: reset
            ))
        }
        return OpenCodeGoSnapshot(windows: windows, fetchedAt: now)
    }

    /// 接受 JSON 数字或数字字符串，但拒绝布尔值和非有限值。
    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() { return nil }
        let result = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        return result.flatMap { $0.isFinite ? $0 : nil }
    }

    /// 兼容秒、毫秒时间戳以及带或不带小数秒的 ISO 8601 时间，避免溢出转换。
    private static func timestamp(_ value: Any) -> Int? {
        if let value = number(value), value >= 0 {
            return Int(exactly: (value > 100_000_000_000 ? value / 1_000 : value).rounded(.down))
        }
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = formatter.date(from: text)
        formatter.formatOptions = [.withInternetDateTime]
        return (fractional ?? formatter.date(from: text)).flatMap { Int(exactly: $0.timeIntervalSince1970.rounded(.down)) }
    }
}

/// 手动凭据只存入系统钥匙串；自动模式只读 OpenCode Go 的专属登录项，不误用 Zen 凭据。
enum OpenCodeGoCredentials {
    private static var query: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.jinsihou.CodexMeter.opencodego",
        kSecAttrAccount as String: "api-key"
    ] }

    /// 按手动钥匙串、环境变量、本机登录文件的顺序解析；缺失或损坏时返回可操作错误。
    static func load(environment: [String: String] = ProcessInfo.processInfo.environment,
                     home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> String {
        var lookup = query
        lookup[kSecReturnData as String] = true
        let context = LAContext()
        context.interactionNotAllowed = true
        lookup[kSecUseAuthenticationContext as String] = context
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty {
            return key
        }
        guard status == errSecItemNotFound else { throw OpenCodeGoError.keychain(status) }
        return try automaticKey(environment: environment, home: home)
    }

    /// 只读显式的 OpenCode 环境变量或 opencode-go API 项；支持 XDG_DATA_HOME。
    static func automaticKey(environment: [String: String], home: URL) throws -> String {
        if let key = environment["OPENCODE_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        let directory = environment["XDG_DATA_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? home.appendingPathComponent(".local/share")
        let url = directory.appendingPathComponent("opencode/auth.json")
        guard let data = try? Data(contentsOf: url),
              let auth = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = auth["opencode-go"] as? [String: Any], entry["type"] as? String == "api",
              let key = entry["key"] as? String, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenCodeGoError.missingKey
        }
        return key
    }

    /// 原子替换已有钥匙串项；空值仅删除本应用的手动覆盖，不修改 OpenCode 登录文件。
    static func save(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw OpenCodeGoError.keychain(status) }
            return
        }
        let attributes = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw OpenCodeGoError.keychain(status) }
    }
}

/// 独立管理 Go 额度刷新与显示偏好；隐藏卡片不影响后台刷新，关闭或换凭据时丢弃旧账号状态。
@MainActor
final class OpenCodeGoStore: ObservableObject {
    static let shared = OpenCodeGoStore()
    @Published private(set) var snapshot: OpenCodeGoSnapshot?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: "openCodeGo.enabled"); restart(clear: true) } }
    /// 仅控制下拉面板中的卡片，保留设置预览、菜单栏项目和当前额度状态。
    @Published var showsInPopover: Bool { didSet { defaults.set(showsInPopover, forKey: "openCodeGo.showsInPopover") } }
    private let defaults: UserDefaults
    private let keyProvider: () throws -> String
    private let fetcher: (String) async throws -> OpenCodeGoSnapshot
    private var refreshTask: Task<Void, Never>?
    private var loopTask: Task<Void, Never>?
    // 令牌只在主线程注册；允许非隔离析构调用线程安全的 removeObserver，防止监听泄漏。
    nonisolated(unsafe) private var observer: NSObjectProtocol?
    private var generation = 0
    private var activeKey: String?

    /// 未保存显示偏好时沿用显示卡片的行为；测试可注入凭据和请求函数以隔离钥匙串与网络。
    init(defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults,
         keyProvider: @escaping () throws -> String = { try OpenCodeGoCredentials.load() },
         fetcher: @escaping (String) async throws -> OpenCodeGoSnapshot = { try await OpenCodeGoClient().fetch(apiKey: $0) }) {
        self.defaults = defaults
        self.keyProvider = keyProvider
        self.fetcher = fetcher
        isEnabled = defaults.bool(forKey: "openCodeGo.enabled")
        showsInPopover = defaults.object(forKey: "openCodeGo.showsInPopover") as? Bool ?? true
    }

    /// 随所有者释放取消后台任务并注销偏好监听。
    deinit {
        refreshTask?.cancel()
        loopTask?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// 启动一次偏好监听，刷新周期沿用通用设置，手动模式不发起启动请求。
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .appBehaviorSettingsDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restart(clear: false) }
        }
        restart(clear: false)
    }

    /// 保存成功后清除旧账户状态再刷新；钥匙串失败不会覆盖现有凭据或额度。
    func saveKey(_ key: String) throws {
        try OpenCodeGoCredentials.save(key)
        restart(clear: true)
        if isEnabled { Task { await refresh() } }
    }

    /// 重建后台循环；禁用时同步清空状态，generation 防止取消不及时的请求回填。
    private func restart(clear: Bool) {
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        loopTask?.cancel()
        loopTask = nil
        isRefreshing = false
        if clear { snapshot = nil; errorMessage = nil; activeKey = nil }
        guard isEnabled, let interval = AppBehaviorSettings(defaults: defaults).refreshCadence.intervalNanoseconds else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(nanoseconds: interval) } catch { return }
            }
        }
    }

    /// 合并同时触发的刷新，失败保留同一凭据的最近成功快照并公开错误状态。
    func refresh() async {
        guard isEnabled else { return }
        if let refreshTask { await refreshTask.value; return }
        let currentGeneration = generation
        isRefreshing = true
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == currentGeneration { isRefreshing = false; refreshTask = nil }
            }
            do {
                let key = try keyProvider()
                if key != activeKey { snapshot = nil; activeKey = key }
                let result = try await fetcher(key)
                guard !Task.isCancelled, isEnabled, generation == currentGeneration else { return }
                snapshot = result
                errorMessage = nil
            } catch {
                guard !Task.isCancelled, isEnabled, generation == currentGeneration else { return }
                errorMessage = error.localizedDescription
            }
        }
        refreshTask = task
        await task.value
    }
}
