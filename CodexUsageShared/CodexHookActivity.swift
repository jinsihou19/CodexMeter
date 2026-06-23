import CoreGraphics
import Foundation

/// Codex 生命周期 hook 写入的活动状态；只表达 UI 需要的离散阶段，不保存完整 prompt 或工具输出。
public enum CodexHookActivityState: String, Codable, Equatable, Sendable, CaseIterable {
    case idle
    case thinking
    case running
    case waitingApproval
    case succeeded
    case failed
    case compacting
    case completed

    public var title: String {
        switch self {
        case .idle:
            return "休息中"
        case .thinking:
            return "思考中"
        case .running:
            return "运行中"
        case .waitingApproval:
            return "需确认"
        case .succeeded:
            return "已完成"
        case .failed:
            return "需确认"
        case .compacting:
            return "思考中"
        case .completed:
            return "已完成"
        }
    }

    public var systemImageName: String {
        switch self {
        case .idle:
            return "moon.zzz"
        case .thinking:
            return "brain.head.profile"
        case .running:
            return "hare.fill"
        case .waitingApproval:
            return "hand.raised.fill"
        case .succeeded:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .compacting:
            return "archivebox.fill"
        case .completed:
            return "flag.checkered"
        }
    }

    /// 不同状态使用不同保鲜期：完成类状态短暂闪一下，运行类状态用更长 TTL 兜底异常中断。
    public var expirationInterval: TimeInterval {
        switch self {
        case .idle:
            return 3
        case .succeeded, .completed:
            return 5
        case .failed:
            return 18
        case .thinking, .running, .waitingApproval, .compacting:
            return 60
        }
    }
}

/// Hook 脚本和 App 之间共享的极小 JSON 快照；字段保持扁平，方便 Python、Shell 或其他脚本写入。
public struct CodexHookActivitySnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let state: CodexHookActivityState
    public let sessionID: String?
    public let turnID: String?
    public let eventName: String
    public let toolName: String?
    public let message: String?
    public let updatedAt: TimeInterval

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        state: CodexHookActivityState,
        sessionID: String?,
        turnID: String?,
        eventName: String,
        toolName: String?,
        message: String?,
        updatedAt: TimeInterval
    ) {
        self.schemaVersion = schemaVersion
        self.state = state
        self.sessionID = sessionID
        self.turnID = turnID
        self.eventName = eventName
        self.toolName = toolName
        self.message = message
        self.updatedAt = updatedAt
    }

    public var updatedAtDate: Date {
        Date(timeIntervalSince1970: updatedAt)
    }

    /// 判断快照是否仍可展示；状态文件过期后 UI 自动回到空闲，避免中断后的假运行状态。
    public func isFresh(now: Date = Date()) -> Bool {
        now.timeIntervalSince1970 - updatedAt <= state.expirationInterval
    }
}

/// Hook 活动文件的新结构；按 session/turn 保存多条状态，让菜单栏可以聚合同一时间的多个 Codex 回合。
public struct CodexHookActivityDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let sessions: [String: CodexHookActivitySnapshot]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        sessions: [String: CodexHookActivitySnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.sessions = sessions
    }

    /// 返回仍在保鲜期内且非空闲的状态，顺序固定为最近更新优先，避免轮询时 UI 因字典顺序抖动。
    public func activeSnapshots(now: Date = Date()) -> [CodexHookActivitySnapshot] {
        sessions.values
            .filter { snapshot in
                snapshot.state != .idle && snapshot.isFresh(now: now)
            }
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
    }
}

/// 菜单栏活动指示使用的展示模型；把 TTL、空闲态、多会话聚合和可访问文本集中处理。
public struct CodexHookActivityDisplay: Equatable, Sendable {
    public static let menuBarIndicatorWidth: CGFloat = 16
    public static let menuBarIndicatorSpacing: CGFloat = 3

    public let snapshot: CodexHookActivitySnapshot?
    public let activeSessionCount: Int
    public let state: CodexHookActivityState
    public let isVisible: Bool
    public let isActive: Bool

    public init(
        snapshot: CodexHookActivitySnapshot?,
        now: Date = Date(),
        showsIdleState: Bool = false
    ) {
        self.init(snapshots: snapshot.map { [$0] } ?? [], now: now, showsIdleState: showsIdleState)
    }

    public init(
        snapshots: [CodexHookActivitySnapshot],
        now: Date = Date(),
        showsIdleState: Bool = false
    ) {
        let activeSnapshots = snapshots
            .filter { snapshot in
                snapshot.state != .idle && snapshot.isFresh(now: now)
            }
            .sorted { lhs, rhs in
                let lhsPriority = Self.statePriority(lhs.state)
                let rhsPriority = Self.statePriority(rhs.state)
                if lhsPriority == rhsPriority {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhsPriority > rhsPriority
            }

        if let selectedSnapshot = activeSnapshots.first {
            self.snapshot = selectedSnapshot
            self.activeSessionCount = activeSnapshots.count
            self.state = selectedSnapshot.state
            self.isVisible = true
            self.isActive = true
            return
        }

        self.snapshot = nil
        self.activeSessionCount = 0
        self.state = .idle
        self.isVisible = showsIdleState
        self.isActive = false
    }

    /// 聚合多会话时优先展示需要处理的状态，再展示运行中，最后展示普通完成态。
    private static func statePriority(_ state: CodexHookActivityState) -> Int {
        switch state {
        case .waitingApproval, .failed:
            return 50
        case .running:
            return 40
        case .thinking, .compacting:
            return 30
        case .succeeded, .completed:
            return 20
        case .idle:
            return 0
        }
    }

    public var title: String {
        state.title
    }

    public var systemImageName: String {
        state.systemImageName
    }

    public var detailText: String {
        guard let snapshot else {
            return "等待 Codex hook 事件"
        }
        if let toolName = snapshot.toolName, !toolName.isEmpty {
            return "\(snapshot.eventName) · \(toolName)"
        }
        return snapshot.eventName
    }

    public var accessibilityText: String {
        if activeSessionCount > 1 {
            return "Codex 活动：\(title)，\(detailText)，活跃会话 \(activeSessionCount) 个"
        }
        return "Codex 活动：\(title)，\(detailText)"
    }

    public var statusItemWidth: CGFloat {
        isVisible ? Self.menuBarIndicatorWidth + Self.menuBarIndicatorSpacing : 0
    }
}

/// 统一计算 hook 活动状态文件位置，保证 App、设置页和外部脚本使用同一条约定。
public enum CodexHookActivityLocation {
    public static let fileName = "codex-activity.json"

    public static func activityURL(
        appGroupIdentifier: String = UsageSnapshotStore.defaultAppGroupIdentifier,
        fallbackDirectory: URL? = nil
    ) -> URL {
        activityDirectoryURL(
            appGroupIdentifier: appGroupIdentifier,
            fallbackDirectory: fallbackDirectory
        )
        .appendingPathComponent(fileName, isDirectory: false)
    }

    public static func activityDirectoryURL(
        appGroupIdentifier: String = UsageSnapshotStore.defaultAppGroupIdentifier,
        fallbackDirectory: URL? = nil
    ) -> URL {
        if !appGroupIdentifier.isEmpty,
           let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return appGroupURL.appendingPathComponent("CodexUsage", isDirectory: true)
        }
        return fallbackDirectory ?? externalWritableDirectory(appGroupIdentifier: appGroupIdentifier)
    }

    /// 外部 hook 脚本没有 App Group entitlement 时仍能按同一目录约定写入文件。
    public static func externalWritableDirectory(appGroupIdentifier: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent(appGroupIdentifier, isDirectory: true)
            .appendingPathComponent("CodexUsage", isDirectory: true)
    }
}
