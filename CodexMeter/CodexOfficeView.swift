// 会话小镇的设置入口、场景和会话档案。
import AppKit
import CodexMeterShared
import SwiftUI

/// 小镇默认关闭；开启后才创建会话读取器和场景，停用时恢复设置窗口布局。
struct CodexOfficeSettingsPane: View {
    @AppStorage("office.isEnabled", store: MenuBarDisplaySettings.sharedDefaults)
    private var isEnabled = false
    @Binding var isExpanded: Bool

    /// 停用页面只显示开关和用途。场景由启用分支独立持有，离开分支即结束其生命周期。
    var body: some View {
        Group {
            if isEnabled {
                CodexOfficeView(isExpanded: $isExpanded, isEnabled: $isEnabled)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(AppLocalization.string("会话小镇")).font(.system(size: 23, weight: .semibold))
                        Spacer()
                        OfficeEnableSwitch(isEnabled: $isEnabled)
                    }
                    Text(officeText("在场景中查看 Codex 会话的工作状态和活动记录。", "See Codex session statuses and activity in a town scene."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { isExpanded = false }
        }
    }
}

/// 启用前后使用同一个开关标签，方便在大屏场景中直接停用小镇。
private struct OfficeEnableSwitch: View {
    @Binding var isEnabled: Bool

    /// 使用紧凑的系统开关，保留可读标签供键盘和辅助功能定位。
    var body: some View {
        Toggle(officeText("启用小镇", "Enable town"), isOn: $isEnabled)
            .toggleStyle(.switch)
            .controlSize(.small)
            .fixedSize()
    }
}

/// 会话小镇统一管理会话档案和场景选择，三维主题分别持有镜头和布景。
private struct CodexOfficeView: View {
    @StateObject private var store = CodexOfficeStore()
    @StateObject private var director = CodexOfficeScene()
    @State private var selectedID: String?
    @State private var department = ""
    @State private var paused = false
    @State private var cameraRequest = 0
    @State private var showsDetails = false
    @State private var showsEvents = false
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var illustrationAction: OfficeIllustratedAction?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SurfaceAppearancePreferenceKeys.appearanceMode, store: MenuBarDisplaySettings.sharedDefaults)
    private var appearanceMode = SurfaceAppearanceSettings.defaultAppearanceMode.rawValue
    @AppStorage("office.sceneStyle", store: MenuBarDisplaySettings.sharedDefaults)
    private var storedSceneStyle = CodexOfficeSceneStyle.company.rawValue
    @Binding var isExpanded: Bool
    @Binding var isEnabled: Bool

    /// 场景读取 App 的共享外观偏好，自动外观交给当前系统配色。
    private var preferredScheme: ColorScheme? { SurfaceAppearanceMode(rawValue: appearanceMode)?.colorScheme }

    /// 已移除或无法识别的旧主题回退到像素邮局。
    private var sceneStyle: CodexOfficeSceneStyle { CodexOfficeSceneStyle(rawValue: storedSceneStyle) ?? .pixelPostOffice }

    private var visibleEmployees: [CodexOfficeEmployee] {
        store.employees.filter { department.isEmpty || $0.projectPath == department }.sorted {
            let order: [CodexOfficeStatus] = [.waiting, .failed, .working, .thinking, .completed, .idle]
            let left = order.firstIndex(of: $0.status) ?? 5
            let right = order.firstIndex(of: $1.status) ?? 5
            return left == right ? $0.updatedAt > $1.updatedAt : left < right
        }
    }
    private var selectedEmployee: CodexOfficeEmployee? { store.employees.first { $0.id == selectedID } }
    private var departments: [String] { Array(Set(store.employees.map(\.projectPath))).sorted() }

    /// 活动工具集中在一行，画布占用标题、工具栏与名册之间的剩余高度。
    var body: some View {
        VStack(spacing: 9) {
            header
            if !store.hookInstalled || store.installationMessage != nil { connectionNotice }
            toolbar
            scene
            roster
        }
        .padding(.horizontal, 20)
        .padding(.top, isExpanded ? 34 : 20)
        .padding(.bottom, 12)
        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { store.start() }
        .onDisappear { store.stop(); toastTask?.cancel() }
        .onChange(of: store.isDemo) { _, _ in
            selectedID = nil
            showsDetails = false
            department = ""
            cameraRequest += 1
        }
        .onChange(of: store.employees) { _, people in
            if let selectedID, !people.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
                showsDetails = false
            }
            if !department.isEmpty && !people.contains(where: { $0.projectPath == department }) { department = "" }
        }
        .popover(isPresented: $showsDetails, arrowEdge: .trailing) {
            if let person = selectedEmployee {
                OfficeEmployeeDetails(person: person, onRename: { store.rename(person.id, to: $0) }, onCoffee: { coffee(person) })
            }
        }
    }

    /// 标题行保留名册和启用开关，场景操作归入下方工具栏。
    private var header: some View {
        HStack(spacing: 8) {
            Text(AppLocalization.string("会话小镇")).font(.system(size: 23, weight: .semibold))
            Spacer(minLength: 8)
            let overflow = store.employees.filter(\.isOnSite).count - OfficeIllustratedLayout.capacity
            if sceneStyle == .pixelPostOffice && overflow > 0 {
                Text(officeText("另有 \(overflow) 位在场", "\(overflow) more on site"))
                    .help(officeText("在下方名册点击会话，可在画面中显示该人物。", "Select a session in the roster to show its character."))
                    .font(.caption).foregroundStyle(.secondary)
            } else if let toast, sceneStyle == .pixelPostOffice {
                Text(toast).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(officeText("名册 · \(store.employees.count) 位同事", "Roster · \(store.employees.count) people"))
                .font(.caption).foregroundStyle(.secondary).fixedSize()
            OfficeEnableSwitch(isEnabled: $isEnabled)
        }
    }

    /// 窄窗使用图标版，数据来源、场景和窗口按钮仍在同一条横线上。
    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            toolbarRow(compact: false)
            toolbarRow(compact: true)
        }
        .popover(isPresented: $showsEvents, arrowEdge: .bottom) { eventWall }
    }

    /// 大屏切换交由同一个设置窗口处理，立体视图额外提供全景按钮。
    private func toolbarRow(compact: Bool) -> some View {
        HStack(spacing: compact ? 5 : 8) {
            metrics(compact: compact)
            Spacer(minLength: 4)
            sceneStyleMenu
            Picker(officeText("数据来源", "Data source"), selection: Binding(get: { store.isDemo }, set: { store.setDemo($0) })) {
                Text(officeText("实时", "Live")).tag(false)
                Text(officeText("演示", "Demo")).tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: compact ? 108 : 122)
            HStack(spacing: 2) {
                pauseButton
                if sceneStyle != .pixelPostOffice {
                    sceneButton("viewfinder", help: officeText("查看公司全景", "Frame the whole office")) {
                        select(nil)
                        cameraRequest += 1
                    }
                }
                stretchButton
                eventButton(compact: compact)
                sceneButton(
                    isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    help: isExpanded ? officeText("退出大屏", "Exit large view") : officeText("大屏观看", "Expand activity monitor")
                ) {
                    isExpanded.toggle()
                }
            }
            .padding(.horizontal, 3)
            .background(.regularMaterial, in: Capsule())
        }
    }

    /// 未安装与未信任分开说明，安装绝不替用户绕过 Codex 的信任审核。
    private var connectionNotice: some View {
        HStack(spacing: 9) {
            Image(systemName: "cable.connector").foregroundStyle(.secondary)
            Text(store.installationMessage ?? officeText("接入 Codex 活动，让同事开始上班。", "Connect Codex activity to bring your office to life."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !store.hookInstalled {
                Button(officeText("安装 / 更新 Hook", "Install / update hooks")) { store.installHook() }
                    .controlSize(.small)
            }
        }
        .padding(10).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    /// 概况始终按当前数据模式统计，窄窗使用相同含义的图标保留横向空间。
    private func metrics(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 14) {
            let present = store.employees.filter(\.isOnSite)
            metric(present.count, title: officeText("在场", "on site"), symbol: "person.2", color: .primary, compact: compact)
            metric(present.filter { $0.status == .working || $0.status == .thinking }.count,
                   title: officeText("在忙", "focused"), symbol: "keyboard",
                   color: Color(nsColor: CodexOfficeStatus.working.officeColor), compact: compact)
            metric(present.filter { $0.status == .waiting }.count, title: officeText("等你", "need you"), symbol: "hand.raised",
                   color: Color(nsColor: CodexOfficeStatus.waiting.officeColor), compact: compact)
        }
        .fixedSize()
    }

    /// 数字颜色和状态文本共同提示重点，紧凑图标也有文字帮助。
    private func metric(_ count: Int, title: String, symbol: String, color: Color, compact: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: compact ? 3 : 4) {
            Text("\(count)").font(.system(size: compact ? 15 : 19, weight: .medium, design: .rounded))
                .monospacedDigit().foregroundStyle(color)
            if compact {
                Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
        .help(title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(title)")
    }

    /// 共用当前会话选择与数据来源，平面画布始终完整适配窗口。
    @ViewBuilder private var scene: some View {
        if sceneStyle == .pixelPostOffice {
            illustratedScene
        } else {
            companyScene
        }
    }

    /// 切换三维主题时重新绑定原生画布；没有在场会话时也直接展示场景。
    private var companyScene: some View {
        ZStack(alignment: .bottomLeading) {
            CodexOfficeSceneView(director: director, employees: store.employees, selected: selectedID,
                                 night: (preferredScheme ?? colorScheme) == .dark, paused: paused,
                                 cameraRequest: cameraRequest, reduceMotion: reduceMotion, isDemo: store.isDemo, onSelect: select)
                .id(sceneStyle.rawValue)
                .accessibilityLabel(sceneStyle.title + officeText("。使用下方同事列表查看状态。", ". Use the people list below to check statuses."))
            Text(toast ?? officeText("左拖平移 · 右拖旋转 · 滚轮或捏合缩放 · 点击同事",
                                     "Left drag to pan · Right drag to orbit · Scroll or pinch to zoom · Click a colleague"))
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(10)
                .allowsHitTesting(false)
        }
        .frame(minHeight: 230, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.06)).allowsHitTesting(false))
    }

    /// 让邮局原画与透明动画层共用同一个等比视口，确保人物站位与背景对齐。
    private var illustratedScene: some View {
        let night = (preferredScheme ?? colorScheme) == .dark
        return GeometryReader { geometry in
            let frame = OfficeIllustratedLayout.mapFrame(in: CGRect(origin: .zero, size: geometry.size))
            ZStack {
                Image(night ? "PixelPostOfficeNight" : "PixelPostOfficeDay")
                    .resizable()
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                CodexOfficeIllustratedScene(employees: store.employees, selected: selectedID,
                                            night: night, animated: !paused && !reduceMotion, isDemo: store.isDemo,
                                            action: illustrationAction, onSelect: select)
            }
            .frame(width: frame.width, height: frame.height)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .position(x: frame.midX, y: frame.midY)
        }
        .frame(minHeight: 210, maxHeight: .infinity)
    }

    /// 只有点菜单项才改写偏好，打开详情或切换大屏时继续使用同一场景风格。
    private var sceneStyleMenu: some View {
        Menu {
            ForEach(CodexOfficeSceneStyle.allCases, id: \.rawValue) { style in
                Button {
                    storedSceneStyle = style.rawValue
                } label: {
                    if style == sceneStyle {
                        Label(style.title, systemImage: "checkmark")
                    } else {
                        Text(style.title)
                    }
                }
            }
        } label: {
            Label(sceneStyle.title, systemImage: "square.on.square")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9).padding(.vertical, 6)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .background(.regularMaterial, in: Capsule())
        .help(officeText("切换场景风格", "Switch scene style"))
        .accessibilityLabel(officeText("场景风格，", "Scene style, ") + sceneStyle.title)
    }

    /// 动画开关作用于当前画布，数据轮询照常进行。
    private var pauseButton: some View {
        sceneButton(paused ? "play" : "pause",
                    help: paused ? officeText("继续动画", "Resume animations") :
                        officeText("暂停动画，数据继续更新", "Pause animations, keep data live")) {
            paused.toggle()
        }
    }

    /// 同一互动只发给当前场景，平面人物用短暂的跃起动作响应。
    private var stretchButton: some View {
        sceneButton("figure.flexibility", help: officeText("全员伸个懒腰", "Stretch break")) {
            if sceneStyle == .pixelPostOffice {
                illustrationAction = OfficeIllustratedAction(.stretch)
            } else {
                director.stretch()
            }
            announce(officeText("伸个懒腰，灵感马上就来。", "A little stretch, a fresh idea."))
        }
    }

    /// 活动记录在窄窗折成图标，始终能通过提示和无障碍标签辨认。
    private func eventButton(compact: Bool) -> some View {
        let title = officeText("活动记录", "Activity")
        return Button { showsEvents.toggle() } label: {
            Group {
                if compact {
                    Image(systemName: "list.bullet.rectangle")
                } else {
                    Label(title, systemImage: "list.bullet.rectangle")
                }
            }
            .font(.system(size: 11, weight: .medium))
            .frame(height: 27)
            .padding(.horizontal, compact ? 7 : 8)
        }
        .buttonStyle(.plain).fixedSize().help(title).accessibilityLabel(title)
    }

    /// 场景按钮都提供文字帮助与无障碍名称，图形控件不依赖悬停才能辨认。
    private func sceneButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11, weight: .medium)).frame(width: 27, height: 27) }
            .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    /// 可访问的二维名册与场景共用选择，窄窗口中也能准确找到同一个项目的多段会话。
    private var roster: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(officeText("公司同事", "People")).font(.system(size: 12, weight: .semibold))
                Text(officeText("点击查看工作档案", "Click for work details")).font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Menu {
                    Button(officeText("所有部门", "All departments")) {
                        department = ""
                        cameraRequest += 1
                    }
                    ForEach(departments, id: \.self) { path in
                        Button(departmentTitle(path)) {
                            department = path
                            selectedID = store.employees.first(where: { $0.projectPath == path })?.id
                        }
                    }
                } label: {
                    Label(department.isEmpty ? officeText("所有部门", "All departments") : visibleEmployees.first?.project ?? "", systemImage: "line.3.horizontal.decrease")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(visibleEmployees) { person in
                        employeeCard(person)
                    }
                    if visibleEmployees.isEmpty { Text(officeText("工位已准备好，等你开工。", "The desks are ready when you are.")).font(.caption).foregroundStyle(.secondary).frame(height: 71) }
                }
            }
        }
    }

    /// 同名项目使用上级目录区分，部门身份仍以完整目录为准。
    private func departmentTitle(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let duplicates = departments.filter { URL(fileURLWithPath: $0).lastPathComponent == url.lastPathComponent }.count
        return duplicates > 1 ? url.deletingLastPathComponent().lastPathComponent + " / " + url.lastPathComponent : store.employees.first(where: { $0.projectPath == path })?.project ?? url.lastPathComponent
    }

    /// 单个同事按钮独立构建，名册的可访问文本包含项目、状态与会话标题。
    private func employeeCard(_ person: CodexOfficeEmployee) -> some View {
        let tint = Color(nsColor: person.status.officeColor)
        let isSelected = selectedID == person.id
        return Button { select(person.id) } label: {
            HStack(spacing: 9) {
                Text(String(person.name.prefix(1))).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tint).frame(width: 33, height: 36)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(person.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Image(systemName: person.status.symbol).font(.system(size: 9)).foregroundStyle(tint)
                    }
                    Text(person.statusTitle)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(person.task).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(9).frame(width: 182, height: 71)
            .background(Color.primary.opacity(isSelected ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(isSelected ? 0.18 : 0)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(person.name + "，" + person.project + "，" + person.statusTitle + "，" + person.task)
    }

    /// 活动墙读取 Hook 内的有界事件历史，快速开始又结束的工具不会被轮询吞掉。
    private var eventWall: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(officeText("小镇活动记录", "Town activity log")).font(.headline)
                Spacer()
                Text(store.isDemo ? "DEMO" : "LIVE").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if store.events.isEmpty {
                Text(officeText("收到新活动后，记录会出现在这里。", "New activity will appear here.")).font(.caption).foregroundStyle(.secondary).padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(store.events) { event in
                            Button {
                                showsEvents = false
                                selectedID = event.employeeID
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: event.status.symbol).foregroundStyle(Color(nsColor: event.status.officeColor)).frame(width: 18)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.name).font(.system(size: 11, weight: .semibold))
                                        Text(event.operation).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer(minLength: 6)
                                    Text(event.date, style: .time).font(.system(size: 9).monospacedDigit()).foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }.frame(maxHeight: 360)
            }
            Text(officeText("每个会话保存最近 64 个事件；此处显示最近 60 条。", "Each session retains 64 events; the latest 60 are shown here."))
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(18).frame(width: 360)
    }

    /// 选择同时驱动场景取景与档案浮层，点击空地只清除选择。
    private func select(_ id: String?) {
        selectedID = id
        showsDetails = id != nil
    }

    /// 咖啡是明确的娱乐互动，不影响审批、任务、工具结果或真实状态。
    private func coffee(_ person: CodexOfficeEmployee) {
        if sceneStyle == .pixelPostOffice {
            illustrationAction = OfficeIllustratedAction(.coffee(person.id))
        } else {
            director.sendCoffee(to: person.id)
        }
        announce(officeText("给 \(person.name) 送了一杯咖啡。", "Coffee delivered to \(person.name)."))
    }

    /// 短提示替换上一个提示并可取消，避免连续互动产生多条延迟回调。
    private func announce(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { toast = nil }
        }
    }
}

/// 会话档案区分可观测事实与缺失数据，详细工具、计时和事件来源都能在同一处核对。
private struct OfficeEmployeeDetails: View {
    let person: CodexOfficeEmployee
    let onRename: (String) -> Void
    let onCoffee: () -> Void
    @State private var nickname = ""
    @State private var showsAllTools = false

    /// 档案采用滚动浮层，避免详细数据挤占公司的场景面积。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Image(systemName: person.status.symbol).font(.title2).foregroundStyle(Color(nsColor: person.status.officeColor))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(person.name).font(.headline)
                        Text(person.project + " · " + person.statusTitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: onCoffee) { Image(systemName: "cup.and.saucer") }
                        .help(officeText("送杯咖啡", "Send coffee")).disabled(!person.isOnSite)
                }
                Text(person.task).font(.system(size: 13, weight: .medium)).textSelection(.enabled)
                if person.isDemo {
                    note(officeText("这是演示同事，与真实 Codex 会话无关。", "This is a demo colleague, separate from real Codex sessions."))
                } else if person.details == nil {
                    note(officeText("这条旧记录只有状态。更新活动 Hook 并开始新回合后，将补齐详细信息。", "This older record only has a status. Update activity hooks and start a new turn for full details."))
                } else if person.details?.turnStartedAt == nil {
                    note(officeText("详细采集在本轮中途接入，计数仅包含已观察到的活动。下一轮开始后可记录完整耗时。", "Detailed tracking joined mid-turn. Counts cover observed activity only. Full timing starts with the next turn."))
                }
                if person.signalExpired {
                    note(officeText("暂未收到新的活动信号，已停止工作动画；这不代表会话已结束。", "No recent activity signal. Work animation has stopped; this does not mean the session has ended."))
                }
                Divider()
                detail(person.isOnSite ? officeText("当前操作", "Current activity") : officeText("最后活动", "Last activity"), person.operation)
                detail(officeText("模型", "Model"), person.details?.model ?? officeText("尚未收到", "Not received"))
                HStack {
                    detail(officeText("本轮工具", "Tools this turn"), person.details.map { "\($0.toolCalls)" } ?? "—")
                    Spacer()
                    detail(officeText("已知工具失败", "Known tool failures"), person.details.map { "\($0.failedTools)" } ?? "—")
                    Spacer()
                    detail(officeText("已观察请求", "Observed requests"), person.details.map { "\($0.modelRequests)" } ?? "—")
                }
                if let details = person.details {
                    if details.tools.contains(where: { $0.outcome == "returned" }) {
                        note(officeText("部分工具未提供执行结果，目前只确认已返回；这类调用不计入已知失败。", "Some tools did not provide an execution result. Only their return is confirmed; they are not counted as known failures."))
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let end = details.turnFinishedAt ?? (person.signalExpired ? person.updatedAt.timeIntervalSince1970 : context.date.timeIntervalSince1970)
                        detail(officeText("本轮耗时", "Turn duration"), details.turnStartedAt.map { officeDuration(max(0, end - $0)) + (person.signalExpired && details.turnFinishedAt == nil ? "+" : "") } ?? "—")
                    }
                    detail(officeText("已完成回合（本次采集）", "Completed turns observed"), "\(details.completedTurns)")
                    if let tokens = details.latestTokenUsage {
                        DisclosureGroup(officeText("最近模型请求 Token", "Latest model request tokens")) {
                            ForEach(tokens.keys.sorted(), id: \.self) { key in
                                HStack { Text(key); Spacer(); Text(tokens[key, default: 0].formatted()) }.font(.caption).foregroundStyle(.secondary)
                            }
                        }.font(.caption)
                    }
                    if !details.tools.isEmpty {
                        Divider()
                        HStack {
                            Text(officeText("本轮工具明细", "Tools this turn")).font(.system(size: 12, weight: .semibold))
                            Spacer()
                            if details.tools.count > 5 {
                                Button(showsAllTools ? officeText("收起", "Less") : officeText("全部", "All")) { showsAllTools.toggle() }.font(.caption)
                            }
                        }
                        ForEach(Array((showsAllTools ? details.tools : Array(details.tools.suffix(5))).reversed())) { tool in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: toolSymbol(tool))
                                    .foregroundStyle(tool.outcome == "failed" ? Color.orange : Color.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tool.operation).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                                    Text(tool.name).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 4)
                                Text(toolResult(tool))
                                    .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        Text(officeText("保留最近 32 项已结束工具及仍在进行的调用。", "Retains 32 finished tools plus calls still in progress."))
                            .font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
                Divider()
                HStack(spacing: 6) {
                    TextField(officeText("给同事起个昵称", "Give them a nickname"), text: $nickname).textFieldStyle(.roundedBorder)
                        .onSubmit { onRename(nickname) }
                    Button(officeText("保存", "Save")) { onRename(nickname) }.controlSize(.small)
                }
                if !person.isDemo {
                    detail(officeText("会话编号", "Session"), person.id)
                    if let turn = person.turnID { detail(officeText("回合编号", "Turn"), turn) }
                    detail(officeText("工作目录", "Workspace"), person.projectPath)
                    HStack {
                        Button(officeText("复制会话编号", "Copy session ID")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(person.id, forType: .string) }
                        Spacer()
                        Button(officeText("在访达中打开", "Show in Finder")) { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: person.projectPath) }
                    }.controlSize(.small)
                }
                HStack {
                    Text(officeText("最近活动", "Last activity"))
                    Spacer()
                    Text(person.updatedAt, style: .relative)
                }.font(.caption).foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .frame(width: 355, height: 490)
        .onAppear { nickname = person.name }
    }

    /// 字段缺失时使用明确占位，长标识与路径允许选择复制。
    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 返回已确认的结果与计时，日志校正的调用只标记已返回，不能显示为成功。
    private func toolResult(_ tool: CodexOfficeToolActivity) -> String {
        if tool.outcome == "failed", let code = tool.exitCode {
            return officeText("退出码 ", "Exit ") + String(code) + (tool.duration.map { " · " + officeDuration($0) } ?? "")
        }
        if tool.outcome == "returned" {
            return officeText("已返回", "Returned") + (tool.duration.map { " · " + officeDuration($0) } ?? "")
        }
        return tool.duration.map(officeDuration) ?? (tool.outcome == "unknown" ? officeText("结果未知", "No result") : tool.finishedAt == nil ? officeText("进行中", "Running") : "—")
    }

    /// 用不同图标区分成功、失败、已返回和结果未知，避免把校正记录画成运行中的工具。
    private func toolSymbol(_ tool: CodexOfficeToolActivity) -> String {
        switch tool.outcome {
        case "succeeded": return "checkmark.circle"
        case "failed": return "exclamationmark.circle"
        case "interrupted": return "pause.circle"
        case "returned": return "arrow.turn.down.left"
        case "unknown": return "questionmark.circle"
        default: return "circle.dotted"
        }
    }

    /// 采集边界作为档案说明呈现，不把未知状态包装成真实工作事实。
    private func note(_ message: String) -> some View {
        Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            .padding(9).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// 活动计时按秒、分钟或小时显示，缺失起止时间由调用者保留为未知。
private func officeDuration(_ seconds: TimeInterval) -> String {
    if seconds < 60 { return String(format: "%.1f s", seconds) }
    if seconds < 3600 { return "\(Int(seconds) / 60) m \(Int(seconds) % 60) s" }
    return "\(Int(seconds) / 3600) h \(Int(seconds) % 3600 / 60) m"
}
