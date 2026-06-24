import Foundation

// 本文件负责降智雷达快照在共享缓存目录中的读写和清理。

/// 降智雷达快照缓存；与用量快照放在同一共享目录，便于启动后立即展示最近图表。
public struct CodexRadarSnapshotStore: Sendable {
    private let appGroupIdentifier: String
    private let fallbackDirectory: URL
    private let fileName: String
    private let usesDefaultFallbackDirectory: Bool

    public init(
        appGroupIdentifier: String = UsageSnapshotStore.defaultAppGroupIdentifier,
        fallbackDirectory: URL? = nil,
        fileName: String = "latest-codex-radar-v1.json"
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.usesDefaultFallbackDirectory = fallbackDirectory == nil
        self.fallbackDirectory = fallbackDirectory ?? UsageSnapshotStore(
            appGroupIdentifier: ""
        ).snapshotURL().deletingLastPathComponent()
        self.fileName = fileName
    }

    /// 保存最近一次雷达快照；写入失败会抛给后台 Store 统一转成错误文案。
    public func save(_ snapshot: CodexRadarSnapshot) throws {
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

    /// 读取本地缓存；文件不存在表示用户尚未开启或尚未成功拉取，不算错误。
    public func load() throws -> CodexRadarSnapshot? {
        var firstError: Error?
        for url in uniqueSnapshotURLs() where FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(CodexRadarSnapshot.self, from: data)
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

    /// 删除雷达缓存；高级维护入口可复用这个方法做本地清理。
    public func deleteSnapshot() throws {
        for url in uniqueSnapshotURLs() where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// 返回雷达缓存文件位置，用于设置页或测试验证文件名。
    public func snapshotURL() -> URL {
        uniqueSnapshotURLs().first ?? fallbackSnapshotURL()
    }

    /// 返回旧版兼容缓存位置；App Group 尚无雷达文件时用于首屏读取历史快照。
    private func fallbackSnapshotURL() -> URL {
        fallbackDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// 返回去重后的雷达缓存路径；ad-hoc 下会恢复旧版 Group Containers 目录，并继续兼容 Widget 容器。
    private func uniqueSnapshotURLs() -> [URL] {
        var urls: [URL] = []
        for url in candidateSnapshotURLs() where !urls.contains(url) {
            urls.append(url)
        }
        return urls
    }

    /// 生成雷达缓存候选路径，保证没有 App Group entitlement 时仍优先写入旧版可写共享目录。
    private func candidateSnapshotURLs() -> [URL] {
        let appGroupURL = AppGroupAccess.containerURL(for: appGroupIdentifier)?
            .appendingPathComponent("CodexUsage", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        let externalGroupURL = usesDefaultFallbackDirectory ? AppGroupAccess.externalDirectory(
            for: appGroupIdentifier
        )?.appendingPathComponent(fileName, isDirectory: false) : nil
        return [appGroupURL, externalGroupURL, fallbackSnapshotURL()].compactMap { $0 }
    }

    /// 原子写入单个候选路径；调用方负责决定是否需要忽略部分路径失败。
    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }
}
