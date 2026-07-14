import Combine
import CodexMeterShared
import Foundation

/// 轮询 Codex hook 活动文件并发布给菜单栏 UI；状态文件是单向输入，不反向控制 Codex 执行。
@MainActor
final class CodexHookActivityStore: ObservableObject {
    @Published private(set) var snapshots: [CodexHookActivitySnapshot] = []

    let activityURL: URL
    private let pollInterval: TimeInterval
    private let decoder = JSONDecoder()
    private var timer: Timer?
    private var lastLoadedData: Data?

    init(
        activityURL: URL = CodexHookActivityLocation.activityURL(),
        pollInterval: TimeInterval = 0.8
    ) {
        self.activityURL = activityURL
        self.pollInterval = pollInterval
    }

    var display: CodexHookActivityDisplay {
        CodexHookActivityDisplay(snapshots: snapshots)
    }

    /// 启动轻量轮询；Timer 放在 common mode，避免打开菜单时状态不刷新。
    func start() {
        refresh()
        guard timer == nil else {
            return
        }
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 停止轮询，主要用于测试或未来显式关闭活动指示时释放资源。
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 读取最新状态并处理过期回落；解码失败时保留上一帧，避免半写入文件造成闪烁。
    func refresh(now: Date = Date()) {
        guard let data = try? Data(contentsOf: activityURL) else {
            applySnapshots([])
            lastLoadedData = nil
            return
        }

        if data != lastLoadedData {
            lastLoadedData = data

            if let decodedDocument = try? decoder.decode(CodexHookActivityDocument.self, from: data) {
                applySnapshots(decodedDocument.activeSnapshots(now: now))
                return
            }

            if let decodedSnapshot = try? decoder.decode(CodexHookActivitySnapshot.self, from: data) {
                applySnapshots(decodedSnapshot.isFresh(now: now) ? [decodedSnapshot] : [])
                return
            }
        }

        let freshSnapshots = snapshots.filter { $0.isFresh(now: now) && $0.state != .idle }
        if freshSnapshots.count != snapshots.count {
            applySnapshots(freshSnapshots)
            return
        }
    }

    /// 只有真实变化时才发布，避免菜单栏宽度和弹窗内容被轮询频率反复刷新。
    private func applySnapshots(_ newSnapshots: [CodexHookActivitySnapshot]) {
        let sortedSnapshots = newSnapshots.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
        guard snapshots != sortedSnapshots else {
            return
        }
        snapshots = sortedSnapshots
    }
}
