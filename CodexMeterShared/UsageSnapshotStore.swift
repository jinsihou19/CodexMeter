import Foundation
import Security

public struct UsageSnapshotStore: Sendable {
    // 兼容标识：更换 App Group 或 Widget Bundle ID 会导致旧设置、快照和桌面组件失联。
    public static let defaultAppGroupIdentifier = "group.com.jinsihou.CodexUsage"
    private static let widgetExtensionBundleIdentifier = "com.jinsihou.CodexUsage.WidgetExtension"

    private let appGroupIdentifier: String
    private let fallbackDirectory: URL
    private let fileName: String
    private let usesDefaultFallbackDirectory: Bool

    public init(
        appGroupIdentifier: String = Self.defaultAppGroupIdentifier,
        fallbackDirectory: URL? = nil,
        fileName: String = "latest-snapshot-v3.json"
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.usesDefaultFallbackDirectory = fallbackDirectory == nil
        self.fallbackDirectory = fallbackDirectory ?? Self.defaultSharedDirectory()
        self.fileName = fileName
    }

    public func save(_ snapshot: UsageSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        var errors: [Error] = []
        var savedCount = 0
        for url in uniqueSnapshotURLs() {
            do {
                try write(data, to: url)
                savedCount += 1
            } catch {
                errors.append(error)
            }
        }
        if savedCount == 0, let error = errors.first {
            throw error
        }
    }

    public func load() throws -> UsageSnapshot? {
        var firstError: Error?
        for url in uniqueSnapshotURLs() where FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(UsageSnapshot.self, from: data)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }
        if let firstError {
            throw firstError
        }
        return nil
    }

    /// 删除最近一次成功同步的快照；文件不存在时视为已经清理完成，方便设置页重复触发。
    public func deleteSnapshot() throws {
        for url in uniqueSnapshotURLs() where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func snapshotURL() -> URL {
        uniqueSnapshotURLs().first ?? fallbackSnapshotURL()
    }

    /// 返回兼容缓存文件位置；App Group 新路径无数据时会读取这里，保证旧版本升级后首屏仍有缓存。
    private func fallbackSnapshotURL() -> URL {
        fallbackDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// 返回去重后的主缓存和兼容缓存路径；Widget 沙箱无法读取 App Group 时会继续使用兼容路径。
    private func uniqueSnapshotURLs() -> [URL] {
        var urls: [URL] = []
        for url in candidateSnapshotURLs() where !urls.contains(url) {
            urls.append(url)
        }
        return urls
    }

    /// ad-hoc 下恢复旧版可写 Group Containers 目录，同时保留 Widget 自身容器作为桌面小组件兼容路径。
    private func candidateSnapshotURLs() -> [URL] {
        let fallbackURL = fallbackSnapshotURL()
        let appGroupURL = AppGroupAccess.containerURL(for: appGroupIdentifier)?
            .appendingPathComponent("CodexUsage", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        let externalGroupURL = usesDefaultFallbackDirectory ? AppGroupAccess.externalDirectory(
            for: appGroupIdentifier
        )?.appendingPathComponent(fileName, isDirectory: false) : nil

        if Self.prefersFallbackDirectoryFirst() {
            return [fallbackURL, appGroupURL, externalGroupURL].compactMap { $0 }
        }
        return [appGroupURL, externalGroupURL, fallbackURL].compactMap { $0 }
    }

    /// Widget extension 在 ad-hoc 或本地 profile 缺少 App Group 时只能稳定读取自己的容器，优先走兼容目录。
    private static func prefersFallbackDirectoryFirst() -> Bool {
        Bundle.main.bundleIdentifier == widgetExtensionBundleIdentifier
    }

    /// 以原子方式写入缓存；macOS 不需要额外文件保护标记，避免测试和 ad-hoc 环境触发保护文件句柄。
    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    private static func defaultSharedDirectory() -> URL {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let widgetContainerSuffix = "Library/Containers/\(widgetExtensionBundleIdentifier)/Data"
        let homePath = homeURL.standardizedFileURL.path
        let dataContainerURL: URL
        if homePath.hasSuffix(widgetContainerSuffix) {
            dataContainerURL = homeURL
        } else {
            dataContainerURL = homeURL
                .appendingPathComponent(widgetContainerSuffix, isDirectory: true)
        }

        return dataContainerURL
            .appendingPathComponent("Library/Application Support/CodexUsage", isDirectory: true)
    }
}

/// 集中判断 App Group 是否真的被当前签名授权，避免 ad-hoc 或测试环境误用不可写的 Group Container。
enum AppGroupAccess {
    static func containerURL(for identifier: String) -> URL? {
        guard hasEntitlement(for: identifier) else {
            return nil
        }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// 返回无 entitlement 也能按旧约定访问的共享目录，用于 ad-hoc 本机和小范围传包测试。
    static func externalDirectory(for identifier: String) -> URL? {
        guard !identifier.isEmpty else {
            return nil
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
            .appendingPathComponent("CodexUsage", isDirectory: true)
    }

    /// 读取当前进程的 application-groups entitlement；没有授权时立即回退，不依赖 FileManager 的宽松路径返回。
    private static func hasEntitlement(for identifier: String) -> Bool {
        guard !identifier.isEmpty,
              let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                  task,
                  "com.apple.security.application-groups" as CFString,
                  nil
              )
        else {
            return false
        }
        guard let groups = value as? [String] else {
            return false
        }
        return groups.contains(identifier)
    }
}
