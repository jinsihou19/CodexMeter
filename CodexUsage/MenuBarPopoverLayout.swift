import AppKit

/// 下拉弹窗的布局约束集合；只存放跨 AppKit 宿主和 SwiftUI 内容共享的尺寸规则。
enum MenuBarPopoverLayout {
    static let width: CGFloat = 380
    static let horizontalPadding: CGFloat = 12
    static let topPadding: CGFloat = 4
    static let bottomPadding: CGFloat = 8
    static let minimumHeight: CGFloat = 220
    static let maximumHeight: CGFloat = 820
    static let maximumScrollableContentHeight: CGFloat = 720
    static let paceMarkerTooltipTopOffset: CGFloat = 112
    static let scrollOverflowHysteresis: CGFloat = 28
    static let initialSize = NSSize(width: width, height: 680)
    /// 错误文案归入滚动主体，避免长错误把底部固定操作栏挤出弹窗可见区域。
    static let errorMessageRegion = MenuBarPopoverContentRegion.scrollContent

    /// 计算内部内容宽度，保证测量副本和真实内容使用同一水平约束。
    static var contentWidth: CGFloat {
        width - horizontalPadding * 2
    }
}

/// 标记弹窗内容属于滚动主体还是固定底部区，避免错误态把底部操作按钮挤出窗口。
enum MenuBarPopoverContentRegion: Equatable {
    case scrollContent
    case footer
}
