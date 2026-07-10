import SwiftUI

/// 设置窗口版本文案；从运行 Bundle 读取版本，避免界面和工程配置脱节。
enum AppVersionDisplay {
    /// 组合用户版本和构建号；缺失构建号时只显示可用的用户版本。
    static func text(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> String {
        let version = infoDictionary["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = infoDictionary["CFBundleVersion"] as? String, !build.isEmpty else {
            return "版本 \(version)"
        }
        return "版本 \(version) (\(build))"
    }
}

enum SettingsPanelLayout {
    static let sidebarWidth: CGFloat = 148
    static let contentMaxWidth: CGFloat = 720
    static let usesSingleContentColumn = true
    static let usesTrailingFooterAction = false
    static let previewAppearanceColumns = 3
    static let displayPresetColumns = 3
    static let colorPresetColumns = 3
    static let sectionSpacing: CGFloat = 10
    static let sectionHeaderSpacing: CGFloat = 5
    static let sectionContentSpacing: CGFloat = 6
    static let sectionContentPadding: CGFloat = 10
    static let preferenceControlWidth: CGFloat = 260
    static let cardSpacing: CGFloat = 8
    static let previewUsesContentFrame = false
    static let previewChipSpacing: CGFloat = 6
    static let previewChipVerticalPadding: CGFloat = 9
    static let previewSampleVerticalPadding: CGFloat = 5
    static let presetCardMinimumHeight: CGFloat = 32
    static let presetCardVerticalPadding: CGFloat = 6
}
