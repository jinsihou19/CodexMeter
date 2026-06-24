import Foundation

// 本文件负责降智雷达快照在共享缓存目录中的读写和清理。

/// 降智雷达快照缓存；与用量快照放在同一共享目录，便于启动后立即展示最近图表。
public struct CodexRadarSnapshotStore: Sendable {
    private let appGroupIdentifier: String
    private let fallbackDirectory: URL
    private let fileName: String

    public init(
        appGroupIdentifier: String = UsageSnapshotStore.defaultAppGroupIdentifier,
        fallbackDirectory: URL? = nil,
        fileName: String = "latest-codex-radar-v1.json"
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.fallbackDirectory = fallbackDirectory ?? UsageSnapshotStore(
            appGroupIdentifier: ""
        ).snapshotURL().deletingLastPathComponent()
        self.fileName = fileName
    }

    /// 保存最近一次雷达快照；写入失败会抛给后台 Store 统一转成错误文案。
    public func save(_ snapshot: CodexRadarSnapshot) throws {
        let url = snapshotURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: [.atomic, .noFileProtection])
    }

    /// 读取本地缓存；文件不存在表示用户尚未开启或尚未成功拉取，不算错误。
    public func load() throws -> CodexRadarSnapshot? {
        let url = snapshotURL()
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CodexRadarSnapshot.self, from: data)
        }

        let fallbackURL = fallbackSnapshotURL()
        guard fallbackURL != url, FileManager.default.fileExists(atPath: fallbackURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fallbackURL)
        return try JSONDecoder().decode(CodexRadarSnapshot.self, from: data)
    }

    /// 删除雷达缓存；高级维护入口可复用这个方法做本地清理。
    public func deleteSnapshot() throws {
        let urls = [snapshotURL(), fallbackSnapshotURL()]
        for url in Set(urls) where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// 返回雷达缓存文件位置，用于设置页或测试验证文件名。
    public func snapshotURL() -> URL {
        directoryURL().appendingPathComponent(fileName, isDirectory: false)
    }

    /// 返回旧版兼容缓存位置；App Group 尚无雷达文件时用于首屏读取历史快照。
    private func fallbackSnapshotURL() -> URL {
        fallbackDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// 解析最终目录；优先使用 App Group，签名或测试环境不可用时再回落到用量快照的兼容目录。
    private func directoryURL() -> URL {
        if !appGroupIdentifier.isEmpty,
           let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return appGroupURL.appendingPathComponent("CodexUsage", isDirectory: true)
        }
        return fallbackDirectory
    }
}
