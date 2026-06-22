import Foundation

public struct UsageSnapshotStore: Sendable {
    public static let defaultAppGroupIdentifier = "group.com.jinsihou.CodexUsage"
    private static let widgetExtensionBundleIdentifier = "com.jinsihou.CodexUsage.WidgetExtension"

    private let appGroupIdentifier: String
    private let fallbackDirectory: URL
    private let fileName: String

    public init(
        appGroupIdentifier: String = "",
        fallbackDirectory: URL? = nil,
        fileName: String = "latest-snapshot-v3.json"
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.fallbackDirectory = fallbackDirectory ?? Self.defaultSharedDirectory()
        self.fileName = fileName
    }

    public func save(_ snapshot: UsageSnapshot) throws {
        let url = snapshotURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: [.atomic, .noFileProtection])
    }

    public func load() throws -> UsageSnapshot? {
        let url = snapshotURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    /// 删除最近一次成功同步的快照；文件不存在时视为已经清理完成，方便设置页重复触发。
    public func deleteSnapshot() throws {
        let url = snapshotURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    public func snapshotURL() -> URL {
        directoryURL().appendingPathComponent(fileName, isDirectory: false)
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
