import Foundation

public struct UsageSnapshotStore: Sendable {
    public static let defaultAppGroupIdentifier = "group.com.jinsihou.CodexUsage"
    private static let widgetExtensionBundleIdentifier = "com.jinsihou.CodexUsage.WidgetExtension"

    private let appGroupIdentifier: String
    private let fallbackDirectory: URL
    private let fileName: String

    public init(
        appGroupIdentifier: String = Self.defaultAppGroupIdentifier,
        fallbackDirectory: URL? = nil,
        fileName: String = "latest-snapshot-v3.json"
    ) {
        self.appGroupIdentifier = appGroupIdentifier
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
        let urls = [snapshotURL(), fallbackSnapshotURL()]
        for url in Set(urls) where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func snapshotURL() -> URL {
        directoryURL().appendingPathComponent(fileName, isDirectory: false)
    }

    /// 返回兼容缓存文件位置；App Group 新路径无数据时会读取这里，保证旧版本升级后首屏仍有缓存。
    private func fallbackSnapshotURL() -> URL {
        fallbackDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// 返回去重后的主缓存和兼容缓存路径；Widget 沙箱无法读取 App Group 时会继续使用兼容路径。
    private func uniqueSnapshotURLs() -> [URL] {
        var urls: [URL] = []
        let orderedURLs = Self.prefersFallbackDirectoryFirst() ? [fallbackSnapshotURL(), snapshotURL()] : [snapshotURL(), fallbackSnapshotURL()]
        for url in orderedURLs where !urls.contains(url) {
            urls.append(url)
        }
        return urls
    }

    /// Widget extension 在 ad-hoc 或本地 profile 缺少 App Group 时只能稳定读取自己的容器，优先走兼容目录。
    private static func prefersFallbackDirectoryFirst() -> Bool {
        Bundle.main.bundleIdentifier == widgetExtensionBundleIdentifier
    }

    /// 以原子方式写入缓存，并确保 WidgetKit 可以读取生成后的文件。
    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .noFileProtection])
    }

    private func directoryURL() -> URL {
        if !appGroupIdentifier.isEmpty,
           let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return appGroupURL.appendingPathComponent("CodexUsage", isDirectory: true)
        }
        return fallbackDirectory
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
