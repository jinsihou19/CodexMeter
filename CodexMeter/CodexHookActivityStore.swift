// 读取新旧活动目录并发布菜单栏状态，兼容更名前已安装的全局 Hook。
import Combine
import CodexMeterShared
import Foundation

/// 汇总持久主会话的活动；日志生命周期兜底结束清理，不把临时任务或子代理当成独立聊天。
@MainActor
final class CodexHookActivityStore: ObservableObject {
    @Published private(set) var snapshots: [CodexHookActivitySnapshot] = []

    let activityURL: URL
    private let legacyActivityURL: URL?
    private let pollInterval: TimeInterval
    private let decoder = JSONDecoder()
    private var timer: Timer?
    private var lastLoadedData: [URL: Data] = [:]
    private var loadedSnapshots: [URL: [CodexHookActivitySnapshot]] = [:]

    /// 默认兼容旧版全局 Hook 的写入目录；测试可注入独立路径或关闭兼容读取。
    init(
        activityURL: URL = CodexHookActivityLocation.activityURL(),
        pollInterval: TimeInterval = 0.8,
        legacyActivityURL: URL? = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.jinsihou.CodexUsage/CodexUsage/codex-activity.json")
    ) {
        self.activityURL = activityURL
        self.pollInterval = pollInterval
        self.legacyActivityURL = legacyActivityURL
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

    /// 合并后核对会话身份和回合结束，再处理过期；即使结束 Hook 未执行，已完成回合也不能继续动画。
    func refresh(now: Date = Date()) {
        var latestBySession: [String: CodexHookActivitySnapshot] = [:]
        for url in [activityURL, legacyActivityURL].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url) {
                if data != lastLoadedData[url] {
                    if let document = try? decoder.decode(CodexHookActivityDocument.self, from: data) {
                        loadedSnapshots[url] = Array(document.sessions.values)
                        lastLoadedData[url] = data
                    } else if let snapshot = try? decoder.decode(CodexHookActivitySnapshot.self, from: data) {
                        loadedSnapshots[url] = [snapshot]
                        lastLoadedData[url] = data
                    }
                }
            } else {
                loadedSnapshots.removeValue(forKey: url)
                lastLoadedData.removeValue(forKey: url)
            }
            for snapshot in loadedSnapshots[url] ?? [] {
                // 旧脚本没有身份信息，不能凭较新的时间戳遮住可核对的主会话记录。
                guard snapshot.transcriptPath?.isEmpty == false else { continue }
                let key = snapshot.sessionID ?? url.path
                if let existing = latestBySession[key], existing.updatedAt >= snapshot.updatedAt { continue }
                latestBySession[key] = snapshot
            }
        }
        let visible = latestBySession.values.compactMap { snapshot -> CodexHookActivitySnapshot? in
            guard snapshot.isFresh(now: now), let path = snapshot.transcriptPath,
                  let sessionID = snapshot.sessionID,
                  CodexActivityTranscript.isPersistentRoot(path: path, sessionID: sessionID) else { return nil }
            let ending = CodexActivityTranscript.ending(for: snapshot)
            let questions = CodexActivityTranscript.unansweredQuestions(snapshot.pendingQuestionIDs ?? [], path: path)
            let waits = !questions.isEmpty || snapshot.approvalToolName != nil
            let state = ending?.state == .idle ? .idle : waits ? .waitingApproval : ending?.state
                ?? (snapshot.pendingQuestionIDs?.isEmpty == false ? .thinking : snapshot.state)
            return CodexHookActivitySnapshot(
                state: state, sessionID: sessionID, turnID: snapshot.turnID,
                eventName: state == .idle ? "Interrupt" : (state == .completed ? "Stop" : snapshot.eventName),
                toolName: state == .completed || state == .idle ? nil : snapshot.toolName,
                message: nil, updatedAt: waits ? snapshot.updatedAt : ending?.date ?? snapshot.updatedAt,
                transcriptPath: path, pendingQuestionIDs: questions.isEmpty ? nil : questions,
                approvalToolID: snapshot.approvalToolID, approvalToolName: snapshot.approvalToolName
            )
        }
        applySnapshots(visible.filter { $0.isFresh(now: now) && $0.state != .idle })
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
