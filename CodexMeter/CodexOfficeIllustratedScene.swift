// 像素邮局根据会话状态安排工位，用原生画布绘制人物、路径和工具事件。
import AppKit
import SwiftUI

/// 设置页以稳定的原始值保存小镇场景，菜单文案随语言切换。
enum CodexOfficeSceneStyle: String, CaseIterable {
    case company, pixelPostOffice, island

    /// 菜单文案与保存的主题标识独立，切换语言不会改变所选场景。
    var title: String {
        switch self {
        case .company: return officeText("3D 公司", "3D Office")
        case .pixelPostOffice: return officeText("像素邮局", "Pixel Post Office")
        case .island: return officeText("海风小岛", "Sea Breeze Island")
        }
    }
}

/// 每次娱乐互动只被当前画布消费一次，与会话实际状态独立。
struct OfficeIllustratedAction: Equatable {
    enum Kind: Equatable { case coffee(String), stretch }
    let kind: Kind
    private let id = UUID()

    /// 即使连续点同一动作，也给每次点击一个新的标识。
    init(_ kind: Kind) { self.kind = kind }
}

/// 邮局以 1000 点宽为原画坐标，人物的工位、茶水区和碰撞位置共用同一张地图。
struct OfficeIllustratedLayout {
    /// 一名在场同事在邮局的站位及动画起点。
    struct Actor {
        let employee: CodexOfficeEmployee
        let slot: Int
        let point: CGPoint

        var resting: Bool { employee.status == .idle }

        /// 邮局人物在原地理信或环顾，走路帧只在沿过道换位时播放。
        func pose(at seconds: TimeInterval, animated: Bool) -> OfficeIllustratedPose {
            var pose = OfficeIllustratedPose(point: point, frame: employee.status == .working ? 1 : 0, left: false)
            guard animated else { return pose }
            let clock = seconds + Double(slot) * 0.43
            switch employee.status {
            case .working:
                let sorting = clock.truncatingRemainder(dividingBy: 2.3)
                pose.frame = sorting < 0.64 ? 0 : 1
                if (1.1..<1.64).contains(sorting) { pose.point.y -= 2 }
            case .thinking:
                let glance = clock.truncatingRemainder(dividingBy: 4.6)
                pose.left = (1.5..<3.6).contains(glance)
                pose.point.y -= round(max(0, sin(glance * .pi / 2.3)) * 2)
            case .waiting, .completed, .failed, .idle:
                pose.point.y -= round(max(0, sin(clock * 2.3)) * (employee.status == .waiting ? 3 : 2))
            }
            return pose
        }
    }

    static let size = CGSize(width: 1000, height: 562.8)
    // 站位标记的是脚底。柜台旁、分拣机前和茶水间的站位留出完整人身与过道。
    private static let desks = [
        CGPoint(x: 315, y: 384), CGPoint(x: 537, y: 349), CGPoint(x: 362, y: 384),
        CGPoint(x: 694, y: 318), CGPoint(x: 645, y: 321), CGPoint(x: 601, y: 360),
        CGPoint(x: 407, y: 384), CGPoint(x: 713, y: 372)
    ]
    private static let tea = [
        CGPoint(x: 850, y: 385), CGPoint(x: 771, y: 385), CGPoint(x: 881, y: 205),
        CGPoint(x: 935, y: 230), CGPoint(x: 932, y: 385), CGPoint(x: 782, y: 289),
        CGPoint(x: 830, y: 273), CGPoint(x: 813, y: 385)
    ]
    static let capacity = desks.count
    static let postOfficeAppearanceCount = 8
    let actors: [Actor]
    let slots: [String: Int]
    let postOfficeAppearances: [String: Int]

    /// 两层用同一个等比矩形，窗口变化时背景、人物和点击区保持对齐。
    static func mapFrame(in viewport: CGRect) -> CGRect {
        let scale = min(viewport.width / size.width, viewport.height / size.height)
        return CGRect(x: viewport.midX - size.width * scale / 2, y: viewport.midY - size.height * scale / 2,
                      width: size.width * scale, height: size.height * scale)
    }

    /// 满员时优先显示选中或待确认的人，并保留仍在画面内的人物工位和造型。
    init(employees: [CodexOfficeEmployee], selected: String?, previousSlots: [String: Int] = [:],
         previousPostOfficeAppearances: [String: Int] = [:]) {
        let ordered = employees.filter(\.isOnSite).sorted { left, right in
            if left.id == selected { return right.id != selected }
            if right.id == selected { return false }
            let a = Self.priority(left.status)
            let b = Self.priority(right.status)
            return a == b ? left.id < right.id : a < b
        }
        let visible = Array(ordered.prefix(Self.capacity))
        let ids = Set(visible.map(\.id))
        // 优先保留在场会话的造型。新会话从自己的偏好造型起依次取空位。
        var appearances = previousPostOfficeAppearances.filter { ids.contains($0.key) }
        let count = Self.postOfficeAppearanceCount
        var available = Set(0..<count).subtracting(appearances.values)
        for employee in visible where appearances[employee.id] == nil {
            let preferred = Int(CodexOfficeEmployee.stableHash(employee.id) % UInt64(count))
            let choices = (0..<count).lazy.map { (preferred + $0) % count }
            if let appearance = choices.first(where: available.contains) {
                appearances[employee.id] = appearance
                available.remove(appearance)
            }
        }
        postOfficeAppearances = appearances
        var slots = previousSlots.filter { ids.contains($0.key) }
        var free = (0..<Self.capacity).filter { !slots.values.contains($0) }
        actors = visible.compactMap { employee in
            let slot: Int
            if let assigned = slots[employee.id] {
                slot = assigned
            } else {
                guard !free.isEmpty else { return nil }
                slot = free.removeFirst()
                slots[employee.id] = slot
            }
            let resting = employee.status == .idle
            return Actor(employee: employee, slot: slot, point: resting ? Self.tea[slot] : Self.desks[slot])
        }
        self.slots = slots
    }

    /// 等待和失败是需要留意的状态，地图拥挤时比普通作业优先。
    private static func priority(_ status: CodexOfficeStatus) -> Int {
        switch status {
        case .waiting: return 0
        case .failed: return 1
        case .working, .thinking: return 2
        case .completed: return 3
        case .idle: return 4
        }
    }

    /// 邮局换位时绕开家具和其他人脚下的位置，无路可走时停在起点等候。
    static func walk(from start: CGPoint, to destination: CGPoint, avoiding occupied: [CGPoint] = []) -> OfficeIllustratedRoute {
        PostOfficeFloor.route(from: start, to: destination, avoiding: occupied)
    }

    /// 邮件沿原画上、下两段传送带出入分拣机。
    static func mail(slot: Int, returning: Bool) -> OfficeIllustratedRoute {
        let upper = slot == 0 || slot == 3 || slot == 4
        let y: CGFloat = upper ? 201 : 304
        let route = [CGPoint(x: 285, y: y), CGPoint(x: 426, y: y),
                     CGPoint(x: 442, y: y - 13), CGPoint(x: 442, y: 184), CGPoint(x: 470, y: 184)]
        return OfficeIllustratedRoute(returning ? Array(route.reversed()) : route)
    }
}

/// 邮局平面坐标和背景图共用，碰撞范围按家具在地面上的轮廓及人物脚宽计算。
private enum PostOfficeFloor {
    private static let bounds = CGRect(x: 308, y: 200, width: 645, height: 187)
    // 同排按肩宽让路，前后按透视中的身体纵深留空；规划和会车使用同一间距。
    static let pedestrianClearance = CGSize(width: 34, height: 26)
    private static let fixtures = [
        CGRect(x: 291, y: 290, width: 170, height: 44),  // 下层传送带
        CGRect(x: 426, y: 156, width: 38, height: 178),  // 竖向传送带
        CGRect(x: 461, y: 85, width: 177, height: 194),  // 分拣机
        CGRect(x: 639, y: 75, width: 103, height: 179),  // 分拣机右侧货架
        CGRect(x: 425, y: 374, width: 140, height: 19),  // 正门门框
        CGRect(x: 742, y: 32, width: 19, height: 294),   // 茶水间门洞上侧
        CGRect(x: 742, y: 366, width: 19, height: 27),   // 茶水间门洞下侧
        CGRect(x: 762, y: 156, width: 97, height: 93),   // 茶水柜
        CGRect(x: 813, y: 282, width: 53, height: 68),   // 茶几
        CGRect(x: 894, y: 244, width: 59, height: 122),  // 沙发
        CGRect(x: 915, y: 128, width: 39, height: 82)    // 窗边花盆
    ].map { $0.insetBy(dx: -7, dy: -6) }

    /// 在起终点及障碍物外角之间查找最短可走路线，再在安全范围内抹圆转角。
    static func route(from start: CGPoint, to destination: CGPoint, avoiding occupied: [CGPoint]) -> OfficeIllustratedRoute {
        guard bounds.contains(start), bounds.contains(destination) else { return OfficeIllustratedRoute([start]) }
        let gap = pedestrianClearance
        let people = occupied.map {
            CGRect(x: $0.x - gap.width, y: $0.y - gap.height, width: gap.width * 2, height: gap.height * 2)
        }
        let blockers = fixtures + people
        if clear(from: start, to: destination, avoiding: blockers) {
            return OfficeIllustratedRoute([start, destination])
        }

        let corners = blockers.flatMap { obstacle -> [CGPoint] in
            let outer = obstacle.insetBy(dx: -1, dy: -1)
            return [CGPoint(x: outer.minX, y: outer.minY), CGPoint(x: outer.maxX, y: outer.minY),
                    CGPoint(x: outer.minX, y: outer.maxY), CGPoint(x: outer.maxX, y: outer.maxY)]
        }.filter { point in bounds.contains(point) && !blockers.contains { $0.contains(point) } }
        let points = [start, destination] + corners
        var distances = Array(repeating: CGFloat.infinity, count: points.count)
        var previous = Array(repeating: -1, count: points.count)
        var visited = Array(repeating: false, count: points.count)
        distances[0] = 0
        while let current = points.indices.filter({ !visited[$0] }).min(by: { distances[$0] < distances[$1] }),
              distances[current].isFinite, current != 1 {
            visited[current] = true
            for next in points.indices where !visited[next] {
                let distance = distances[current] + hypot(points[next].x - points[current].x, points[next].y - points[current].y)
                if distance < distances[next], clear(from: points[current], to: points[next], avoiding: blockers) {
                    distances[next] = distance
                    previous[next] = current
                }
            }
        }
        guard distances[1].isFinite else { return OfficeIllustratedRoute([start]) }
        var path: [CGPoint] = []
        var index = 1
        while index >= 0 {
            path.append(points[index])
            index = previous[index]
        }
        return OfficeIllustratedRoute(roundCorners(Array(path.reversed()), avoiding: blockers))
    }

    /// 线段与矩形用参数区间求交，斜向走过窄门时也会留出脚底空间。
    private static func clear(from start: CGPoint, to end: CGPoint, avoiding blockers: [CGRect]) -> Bool {
        !blockers.contains { obstacle in
            var entry: CGFloat = 0
            var exit: CGFloat = 1
            let axes = [(start.x, end.x, obstacle.minX, obstacle.maxX), (start.y, end.y, obstacle.minY, obstacle.maxY)]
            for (origin, target, lower, upper) in axes {
                let delta = target - origin
                if abs(delta) < 0.000_001 {
                    if origin <= lower || origin >= upper { return false }
                    continue
                }
                let first = (lower - origin) / delta
                let second = (upper - origin) / delta
                entry = max(entry, min(first, second))
                exit = min(exit, max(first, second))
                if entry >= exit { return false }
            }
            return true
        }
    }

    /// 圆角曲线按短线段逐一检查，空间狭窄时保留原来可走的折线。
    private static func roundCorners(_ points: [CGPoint], avoiding blockers: [CGRect]) -> [CGPoint] {
        guard points.count > 2, let first = points.first, let last = points.last else { return points }
        var rounded = [first]
        for index in 1..<(points.count - 1) {
            let before = points[index - 1]
            let corner = points[index]
            let after = points[index + 1]
            let inbound = hypot(corner.x - before.x, corner.y - before.y)
            let outbound = hypot(after.x - corner.x, after.y - corner.y)
            let trim = min(9, min(inbound, outbound) * 0.25)
            guard trim > 1 else { rounded.append(corner); continue }
            let start = interpolate(corner, before, trim / inbound)
            let end = interpolate(corner, after, trim / outbound)
            let curve = (0...4).map { index in
                let t = CGFloat(index) / 4
                return interpolate(interpolate(start, corner, t), interpolate(corner, end, t), t)
            }
            if zip(curve, curve.dropFirst()).allSatisfy({ clear(from: $0.0, to: $0.1, avoiding: blockers) }) {
                rounded.append(contentsOf: curve)
            } else {
                rounded.append(corner)
            }
        }
        rounded.append(last)
        return rounded
    }

    /// 在已通过碰撞检查的控制点间计算转角位置。
    private static func interpolate(_ start: CGPoint, _ end: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
    }
}

/// 每帧以脚底为基准，站立和整理用前两帧，行走从第三帧开始。
struct OfficeIllustratedPose: Equatable {
    var point: CGPoint
    var frame: Int
    var left: Bool
    var walking: Bool { frame >= 2 }
}

/// 角色和邮件沿线段的实际长度插值，拐弯或换步时速度保持连续。
struct OfficeIllustratedRoute {
    private let points: [CGPoint]
    private let lengths: [CGFloat]
    let length: CGFloat

    /// 路径允许重复节点，以便门口与出发点恰好重合时仍可渲染。
    init(_ points: [CGPoint]) {
        self.points = points
        lengths = zip(points, points.dropFirst()).map { start, end in hypot(end.x - start.x, end.y - start.y) }
        length = lengths.reduce(0, +)
    }

    /// 返回当前脚下坐标和行走方向，比例在起点与终点之间截断。
    func sample(_ fraction: CGFloat) -> (point: CGPoint, left: Bool) {
        var distance = min(1, max(0, fraction)) * length
        for (index, step) in lengths.enumerated() where step > 0 {
            let start = points[index]
            let end = points[index + 1]
            if distance <= step {
                let t = distance / step
                return (CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t), end.x < start.x)
            }
            distance -= step
        }
        return (points.last ?? .zero, false)
    }
}

/// SwiftUI 将会话快照和选择交给像素邮局的原生画布，画布负责绘制与鼠标命中。
struct CodexOfficeIllustratedScene: NSViewRepresentable {
    let employees: [CodexOfficeEmployee]
    let selected: String?
    let night: Bool
    let animated: Bool
    let isDemo: Bool
    let action: OfficeIllustratedAction?
    let onSelect: (String?) -> Void

    /// 名册提供同一份人物信息的键盘及辅助功能入口。
    func makeNSView(context: Context) -> OfficeIllustratedCanvas {
        let view = OfficeIllustratedCanvas()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        let instruction = officeText("。可点击人物或使用下方名册打开会话。", ". Open a session by clicking a character or using the roster below.")
        view.setAccessibilityLabel(CodexOfficeSceneStyle.pixelPostOffice.title + instruction)
        return view
    }

    /// 接收页面快照，暂停动画时仍更新人物及状态。
    func updateNSView(_ view: OfficeIllustratedCanvas, context: Context) { view.apply(self) }

    /// 退出页面或切换风格时停止帧计时器。
    static func dismantleNSView(_ view: OfficeIllustratedCanvas, coordinator: ()) { view.stop() }
}

/// 邮局的透明画布在固定背景上绘制人物和环境动效，暂停或窗口不可见时释放动画时钟。
final class OfficeIllustratedCanvas: NSView {
    private struct Walk {
        let route: OfficeIllustratedRoute
        let start: Date
        let duration: TimeInterval
    }

    private var input: CodexOfficeIllustratedScene?
    private var layoutData = OfficeIllustratedLayout(employees: [], selected: nil)
    private var walks: [String: Walk] = [:]
    private var traffic = OfficeToolTraffic()
    private var mail: [(route: OfficeIllustratedRoute, failed: Bool, start: Date)] = []
    private var action: (kind: OfficeIllustratedAction.Kind, start: Date)?
    private var frameTimer: Timer?
    private var pressed: CGPoint?

    override var isFlipped: Bool { true }

    /// 接收会话快照。切换演示与实时数据时重置轨迹，普通状态变化从当前脚下位置续走。
    func apply(_ next: CodexOfficeIllustratedScene, now: Date = Date()) {
        let previous = input
        let changesSource = previous?.isDemo != next.isDemo
        let updated = OfficeIllustratedLayout(employees: next.employees, selected: next.selected,
                                              previousSlots: changesSource ? [:] : layoutData.slots,
                                              previousPostOfficeAppearances: changesSource ? [:] : layoutData.postOfficeAppearances)
        let oldActors = Dictionary(uniqueKeysWithValues: layoutData.actors.map { ($0.employee.id, $0) })
        if changesSource {
            traffic = OfficeToolTraffic()
        }
        if changesSource || !next.animated {
            walks.removeAll()
            mail.removeAll()
            action = nil
        } else {
            updatePostOfficeWalks(updated, oldActors: oldActors, now: now)
        }
        layoutData = updated
        input = next

        let events = traffic.observe(next.employees.filter(\.isOnSite), now: now, animated: next.animated)
        for event in events {
            guard let actor = layoutData.actors.first(where: { $0.employee.id == event.employeeID }) else { continue }
            let route = OfficeIllustratedLayout.mail(slot: actor.slot, returning: event.returning)
            mail.append((route, event.failed, now))
        }
        if mail.count > 6 { mail = Array(mail.suffix(6)) }
        if let command = next.action, let previous, command != previous.action, next.animated {
            action = (command.kind, now)
        }
        advance(now)
    }

    /// 邮局按实际脚底重新规划，目标位附近的人绕开，经过同一过道的人按到达时刻让行。
    private func updatePostOfficeWalks(_ layout: OfficeIllustratedLayout,
                                       oldActors: [String: OfficeIllustratedLayout.Actor], now: Date) {
        walks = walks.filter { layout.slots[$0.key] != nil }
        let changing = layout.actors.filter { actor in
            guard let old = oldActors[actor.employee.id] else { return false }
            return old.point != actor.point || walks[actor.employee.id]?.duration == 0
        }
        guard !changing.isEmpty else { return }
        let origins = Dictionary(uniqueKeysWithValues: layout.actors.map { actor in
            let from = oldActors[actor.employee.id].map { pose(for: $0, now: now).point } ?? actor.point
            return (actor.employee.id, from)
        })
        for actor in changing {
            let id = actor.employee.id
            let from = origins[id] ?? actor.point
            guard hypot(from.x - actor.point.x, from.y - actor.point.y) > 0.5 else {
                walks.removeValue(forKey: id)
                continue
            }
            let peers = layout.actors.filter { $0.employee.id != id }
            let moving = peers.compactMap { peer -> Walk? in
                guard let walk = walks[peer.employee.id], walk.duration > 0 else { return nil }
                return walk
            }
            let occupied = peers.map { peer -> CGPoint in
                if let walk = walks[peer.employee.id] { return walk.route.sample(1).point }
                return oldActors[peer.employee.id]?.point ?? peer.point
            }
            let route = OfficeIllustratedLayout.walk(from: from, to: actor.point, avoiding: occupied)
            if route.length > 0.5 {
                let duration = max(0.36, route.length / 145)
                if let start = postOfficeDeparture(route: route, duration: duration, moving: moving, now: now) {
                    walks[id] = Walk(route: route, start: start, duration: duration)
                    continue
                }
            }
            // 走到一半遇到新状态时优先走完原先已让开的路线，到达后再重试。
            if (walks[id]?.duration ?? 0) <= 0 {
                walks[id] = Walk(route: OfficeIllustratedRoute([from]), start: .distantFuture, duration: 0)
            }
        }
    }

    /// 先尝试立即或稍后出发，窄道持续被占用时等已经排好的行走结束。
    private func postOfficeDeparture(route: OfficeIllustratedRoute, duration: TimeInterval,
                                     moving: [Walk], now: Date) -> Date? {
        guard !moving.isEmpty else { return now }
        let latest = moving.map { max(0, $0.start.addingTimeInterval($0.duration).timeIntervalSince(now)) }.max() ?? 0
        let delays = Array(stride(from: 0.0, through: min(1.4, latest), by: 0.14)) + [latest]
        let gap = PostOfficeFloor.pedestrianClearance
        for delay in delays {
            let candidate = Walk(route: route, start: now.addingTimeInterval(delay), duration: duration)
            let steps = Int(ceil(max(latest, delay + duration) * 60))
            let clear = (0...steps).allSatisfy { step in
                let time = now.addingTimeInterval(Double(step) / 60)
                let point = route.sample(postOfficeProgress(candidate, at: time)).point
                return moving.allSatisfy { peer in
                    let other = peer.route.sample(postOfficeProgress(peer, at: time)).point
                    return abs(other.x - point.x) >= gap.width || abs(other.y - point.y) >= gap.height
                }
            }
            if clear { return candidate.start }
        }
        return nil
    }

    /// 起步与停步渐进加减速。绘制和会车检查共用同一个距离比例。
    private func postOfficeProgress(_ walk: Walk, at now: Date) -> CGFloat {
        guard walk.duration > 0 else { return 0 }
        let t = min(1, max(0, now.timeIntervalSince(walk.start) / walk.duration))
        return t * t * (3 - 2 * t)
    }

    /// 环境和人物循环只在可见窗口且允许动画时刷新，轮询数据与帧时钟彼此独立。
    private func advance(_ now: Date) {
        let finished = walks.filter { now.timeIntervalSince($0.value.start) >= $0.value.duration }
        if !finished.isEmpty {
            let actors = Dictionary(uniqueKeysWithValues: layoutData.actors.map { ($0.employee.id, $0) })
            for (id, walk) in finished {
                walks.removeValue(forKey: id)
                let point = walk.route.sample(1).point
                if let actor = actors[id], hypot(actor.point.x - point.x, actor.point.y - point.y) > 0.5 {
                    walks[id] = Walk(route: OfficeIllustratedRoute([point]), start: .distantFuture, duration: 0)
                }
            }
            updatePostOfficeWalks(layoutData, oldActors: actors, now: now)
        }
        mail.removeAll { now.timeIntervalSince($0.start) >= 1.05 }
        if let action, now.timeIntervalSince(action.start) >= 1.2 { self.action = nil }
        needsDisplay = true
        guard input?.animated == true, let window, window.occlusionState.contains(.visible) else { stop(); return }
        guard frameTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 24, target: self, selector: #selector(tick(_:)), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    /// 公共 RunLoop 使邮局在滚动设置页时仍能更新。
    @objc private func tick(_ timer: Timer) { advance(Date()) }

    /// 停止画布刷新并解除定时器对视图的持有。
    func stop() {
        frameTimer?.invalidate()
        frameTimer = nil
    }

    /// 监听遮挡状态，使窗口重新可见时自动恢复循环。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let notifications = NotificationCenter.default
        notifications.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        if let window {
            notifications.addObserver(self, selector: #selector(visibilityChanged(_:)),
                                      name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        advance(Date())
    }

    /// 最小化、遮挡和重新显示共用同一帧时钟判定。
    @objc private func visibilityChanged(_ notification: Notification) { advance(Date()) }

    /// 尺寸变化时重新适配整幅地图。
    override func layout() {
        super.layout()
        needsDisplay = true
    }

    /// 状态过渡优先沿走廊移动，其余时间使用工位动作，点击区与实际姿势同步。
    func pose(for actor: OfficeIllustratedLayout.Actor, now: Date) -> OfficeIllustratedPose {
        var pose: OfficeIllustratedPose
        if let walk = walks[actor.employee.id] {
            let elapsed = now.timeIntervalSince(walk.start)
            let progress = postOfficeProgress(walk, at: now)
            let point = walk.route.sample(progress).point
            let distance = progress * walk.route.length
            let before = walk.route.sample(progress - 0.015).point
            let after = walk.route.sample(progress + 0.015).point
            let left = abs(after.x - before.x) > 0.5 ? after.x < before.x
                : walk.route.sample(1).point.x < walk.route.sample(0).point.x
            let frame = elapsed > 0 && elapsed < walk.duration ? 2 + Int(distance / 12) % 4 : 0
            pose = OfficeIllustratedPose(point: point, frame: frame, left: left)
        } else {
            pose = actor.pose(at: now.timeIntervalSinceReferenceDate, animated: input?.animated == true)
        }
        if let action, action.kind == .stretch {
            pose.point.y -= sin(.pi * min(1, max(0, now.timeIntervalSince(action.start) / 1.2))) * 9
        }
        return pose
    }

    /// 在固定布景上按原画坐标绘制，人物按脚底的纵向位置排序，保留像素边缘。
    override func draw(_ dirtyRect: NSRect) {
        guard let input, let context = NSGraphicsContext.current?.cgContext else { return }
        let frame = OfficeIllustratedLayout.mapFrame(in: bounds)
        guard frame.width > 0, frame.height > 0 else { return }
        let size = OfficeIllustratedLayout.size
        let now = Date()
        context.saveGState()
        context.translateBy(x: frame.minX, y: frame.minY)
        context.scaleBy(x: frame.width / size.width, y: frame.height / size.height)
        context.interpolationQuality = .none
        if input.animated {
            drawAmbience(at: now.timeIntervalSinceReferenceDate, night: input.night, in: context)
        }
        for message in mail {
            let progress = now.timeIntervalSince(message.start) / 1.05
            let point = message.route.sample(progress).point
            drawLetter(at: point, failed: message.failed, in: context)
        }
        let actors = layoutData.actors.map { ($0, pose(for: $0, now: now)) }.sorted { $0.1.point.y < $1.1.point.y }
        for (actor, pose) in actors {
            drawActor(actor, pose: pose, now: now, in: context)
        }
        context.restoreGState()
    }

    /// 从同一造型读取动作帧，完整绘制人物并用脚底阴影贴合地面。
    private func drawActor(_ actor: OfficeIllustratedLayout.Actor, pose: OfficeIllustratedPose, now: Date, in context: CGContext) {
        let employee = actor.employee
        let feet = pose.point
        let original = employee.appearance % 2
        let appearance = layoutData.postOfficeAppearances[employee.id] ?? original
        let sprites = OfficeIllustratedSprites.postOffice
        let frameIndex = pose.walking ? 2 + (pose.frame - 2) / 2 : pose.frame
        let walking = pose.walking ? OfficeIllustratedSprites.postOfficeWalk[appearance * 4 + pose.frame - 2] : nil
        let sprite = walking ?? sprites[appearance * 4 + frameIndex] ?? sprites[original * 4 + frameIndex]
        let frame = CGRect(x: feet.x - 21, y: feet.y - 59, width: 42, height: 59)
        context.setFillColor(NSColor(officeHex: 0x282823).withAlphaComponent(0.22).cgColor)
        context.fillEllipse(in: CGRect(x: feet.x - 13, y: feet.y - 6, width: 26, height: 7))
        if input?.selected == employee.id {
            context.setStrokeColor(NSColor(officeHex: 0xFFE1A0).cgColor)
            context.setLineWidth(1.6)
            context.strokeEllipse(in: CGRect(x: feet.x - 19, y: feet.y - 6, width: 38, height: 11))
        }
        context.saveGState()
        if pose.left {
            context.translateBy(x: feet.x * 2, y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        sprite?.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        context.restoreGState()
        let badge = CGPoint(x: feet.x, y: feet.y - 70)
        let animated = input?.animated == true
        let clock = now.timeIntervalSinceReferenceDate + Double(actor.slot) * 0.29
        if action?.kind == .coffee(employee.id) || (actor.resting && !pose.walking) {
            drawGlyph(["####.", "#..##", "#..##", ".###.", "#####"], at: badge, tint: 0xF8DBAE, in: context)
            if animated && clock.truncatingRemainder(dividingBy: 1.65) < 0.95 {
                drawGlyph([".#", "#."], at: CGPoint(x: badge.x, y: badge.y - 12), tint: 0xF0CDA5, in: context)
            }
        } else {
            switch employee.status {
            case .waiting:
                let ring = clock.truncatingRemainder(dividingBy: 2.05)
                let wiggle = animated && ring < 0.52 ? round(sin(ring * 23) * 3) : 0
                drawGlyph(["...#...", "..###..", ".#####.", ".#####.", "#######", "...#..."],
                          at: CGPoint(x: badge.x + wiggle, y: badge.y), tint: 0xF6C061, in: context)
                if animated && ring < 0.52 {
                    drawGlyph(["#.......#", ".#.....#."], at: CGPoint(x: badge.x, y: badge.y - 10), tint: 0xF9D683, in: context)
                }
            case .failed: drawGlyph(["##", "##", "##", "..", "##"], at: badge, tint: 0xF18F79, in: context)
            case .completed: drawGlyph([".....#", "....#.", "#..#..", ".##..."], at: badge, tint: 0xA7D78B, in: context)
            case .thinking:
                let count = animated ? 1 + Int(clock * 2.6) % 3 : 3
                let dots = Array(repeating: "##", count: count).joined(separator: ".")
                drawGlyph([dots, dots], at: badge, tint: 0xEFDBAF, in: context)
            default: break
            }
        }
    }

    /// 用原画的茶壶、机器、窗户和湿路面作锚点，空邮局也有轻微环境动效。
    private func drawAmbience(at clock: TimeInterval, night: Bool, in context: CGContext) {
        for index in 0..<3 {
            let phase = (clock / 2.5 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            let x = 810 + round(sin(phase * 5 + Double(index)) * 4)
            let y = 169 - round(phase * 25)
            context.setFillColor(NSColor(officeHex: 0xFFF0CD).withAlphaComponent(sin(.pi * phase) * 0.60).cgColor)
            context.fill(CGRect(x: x - 3, y: y, width: 7, height: 2))
            context.fill(CGRect(x: x, y: y + 2, width: 5, height: 2))
        }
        let glow = 0.21 + max(0, sin(clock * 2.4)) * 0.29
        context.setFillColor(NSColor(officeHex: 0xCAFF79).withAlphaComponent(glow).cgColor)
        context.fill(CGRect(x: 586, y: 162, width: 15, height: 5))
        if night {
            context.saveGState()
            context.clip(to: CGRect(x: 873, y: 66, width: 62, height: 68))
            context.setStrokeColor(NSColor(officeHex: 0xA7D6F3).withAlphaComponent(0.56).cgColor)
            context.setLineWidth(1.5)
            for index in 0..<7 {
                let phase = (clock * (0.66 + Double(index % 3) * 0.09) + Double(index) * 0.23)
                    .truncatingRemainder(dividingBy: 1)
                let x = 875 + Double(index) * 9 - phase * 6
                let y = 62 + phase * 78
                context.move(to: CGPoint(x: x, y: y))
                context.addLine(to: CGPoint(x: x - 4, y: y + 8))
            }
            context.strokePath()
            context.restoreGState()
            context.setFillColor(NSColor(officeHex: 0xF2B774).withAlphaComponent(glow * 0.52).cgColor)
            for index in 0..<4 {
                let offset = round(sin(clock * 3 + Double(index)) * 5)
                context.fill(CGRect(x: 769 + offset + Double(index % 2) * 8, y: 521 + Double(index) * 7, width: 14, height: 2))
            }
        } else {
            for index in 0..<5 {
                let phase = (clock / 5 + Double(index) * 0.22).truncatingRemainder(dividingBy: 1)
                context.setFillColor(NSColor(officeHex: 0xFFF5BC).withAlphaComponent(sin(.pi * phase) * 0.57).cgColor)
                context.fill(CGRect(x: 864 + Double(index) * 10 - phase * 12,
                                    y: 188 + Double(index) * 8 - phase * 19, width: 2.5, height: 2.5))
            }
        }
    }

    /// 给实际发出的工具事件绘制像素信封，明确失败才使用红色封蜡。
    private func drawLetter(at point: CGPoint, failed: Bool, in context: CGContext) {
        let x = round(point.x)
        let y = round(point.y)
        context.setFillColor(NSColor(officeHex: 0x513833).cgColor)
        context.fill(CGRect(x: x - 12, y: y - 7, width: 24, height: 15))
        context.setFillColor(NSColor(officeHex: 0xF8E2B6).cgColor)
        context.fill(CGRect(x: x - 10, y: y - 6, width: 20, height: 12))
        context.setStrokeColor(NSColor(officeHex: 0xA96F54).cgColor)
        context.setLineWidth(1.5)
        context.beginPath()
        context.addLines(between: [CGPoint(x: x - 10, y: y - 5), CGPoint(x: x, y: y + 1), CGPoint(x: x + 10, y: y - 5)])
        context.strokePath()
        context.setFillColor(NSColor(officeHex: failed ? 0xC34E43 : 0x9A693D).cgColor)
        context.fill(CGRect(x: x - 2, y: y - 1, width: 4, height: 4))
    }

    /// 图标使用固定的像素格和深色投影，在亮暗画面上都清楚。
    private func drawGlyph(_ rows: [String], at point: CGPoint, tint: Int, in context: CGContext) {
        let cell: CGFloat = 3
        let left = round(point.x - CGFloat(rows.first?.count ?? 0) * cell / 2)
        let top = round(point.y - CGFloat(rows.count) * cell / 2)
        var pixels: [CGRect] = []
        for (row, tiles) in rows.enumerated() {
            for (column, tile) in tiles.enumerated() where tile == "#" {
                pixels.append(CGRect(x: left + CGFloat(column) * cell, y: top + CGFloat(row) * cell, width: cell, height: cell))
            }
        }
        context.setFillColor(NSColor(officeHex: 0x392A2C).cgColor)
        for pixel in pixels { context.fill(pixel.offsetBy(dx: 1, dy: 2)) }
        context.setFillColor(NSColor(officeHex: tint).cgColor)
        for pixel in pixels { context.fill(pixel) }
    }

    /// 只记短按起点，拖动不触发人物选择。
    override func mouseDown(with event: NSEvent) { pressed = convert(event.locationInWindow, from: nil) }

    /// 将短按位置映射到原画坐标，优先命中前排人物，点击空地清除选择。
    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        defer { pressed = nil }
        let frame = OfficeIllustratedLayout.mapFrame(in: bounds)
        guard let pressed, hypot(location.x - pressed.x, location.y - pressed.y) < 4, frame.contains(location) else { return }
        let size = OfficeIllustratedLayout.size
        let point = CGPoint(x: (location.x - frame.minX) * size.width / frame.width,
                            y: (location.y - frame.minY) * size.height / frame.height)
        let now = Date()
        let actors = layoutData.actors
            .map { ($0, pose(for: $0, now: now).point) }.sorted { $0.1.y > $1.1.y }
        let hit = actors.first { _, feet in
            CGRect(x: feet.x - 24, y: feet.y - 80, width: 48, height: 86).contains(point)
        }
        input?.onSelect(hit?.0.employee.id)
    }
}

/// 缓存邮局人物图集。每位邮差的步态单独占四帧，保留帽檐、发尾和脚底余量。
@MainActor
enum OfficeIllustratedSprites {
    static let postOffice: [NSImage?] = {
        let standardCrop = CGRect(x: 0.25, y: 0.115, width: 0.52, height: 0.79)
        // 第三张图集的卷发和帽檐更宽，保留透明余量以免切掉轮廓。
        let wideCrop = CGRect(x: 0.23, y: 0.115, width: 0.54, height: 0.79)
        return frames(in: "PixelPostOfficeClerks", crop: standardCrop)
            + frames(in: "PixelPostOfficeClerks2", crop: standardCrop)
            + frames(in: "PixelPostOfficeClerks3", crop: wideCrop)
            + frames(in: "PixelPostOfficeClerks4", crop: standardCrop)
    }()
    static let postOfficeWalk = (1...4).flatMap { index in
        let crop = CGRect(x: index == 3 ? 0.23 : 0.25, y: 0.115, width: index == 3 ? 0.54 : 0.52, height: 0.79)
        return frames(in: "PixelPostOfficeWalk\(index)", crop: crop)
    }

    /// 按图集单元格的归一化边界裁出八帧，图集缺失时保留会话命中区域。
    private static func frames(in asset: String, crop: CGRect) -> [NSImage?] {
        let sheet = NSImage(named: asset)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        return (0..<8).map { index in
            guard let sheet else { return nil }
            let width = CGFloat(sheet.width) / 4
            let height = CGFloat(sheet.height) / 2
            let column = CGFloat(index % 4)
            let row = CGFloat(index / 4)
            let frame = CGRect(x: (column + crop.minX) * width, y: (row + crop.minY) * height,
                               width: width * crop.width, height: height * crop.height).integral
            guard let sprite = sheet.cropping(to: frame) else { return nil }
            return NSImage(cgImage: sprite, size: NSSize(width: sprite.width, height: sprite.height))
        }
    }
}
