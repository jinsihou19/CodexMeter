import CodexMeterShared
import SwiftUI

/// 设置窗口版本文案；从运行 Bundle 读取版本，避免界面和工程配置脱节。
enum AppVersionDisplay {
    /// 组合用户版本和构建号；缺失构建号时只显示可用的用户版本。
    static func text(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
        language: AppLanguage? = nil
    ) -> String {
        let version = infoDictionary["CFBundleShortVersionString"] as? String ?? "—"
        let versionLabel = AppLocalization.string("版本", language: language)
        guard let build = infoDictionary["CFBundleVersion"] as? String, !build.isEmpty else {
            return "\(versionLabel) \(version)"
        }
        return "\(versionLabel) \(version) (\(build))"
    }
}

/// 设置窗口的稳定尺寸与少量共享间距，避免各页面重新声明布局常量。
enum SettingsPanelLayout {
    static let windowWidth: CGFloat = 880
    static let windowHeight: CGFloat = 620
    static let sidebarWidth: CGFloat = 190
    static let preferenceControlWidth: CGFloat = 260
    static let cardSpacing: CGFloat = 8
    static let previewChipSpacing: CGFloat = 6
    static let previewChipVerticalPadding: CGFloat = 9
    static let previewSampleVerticalPadding: CGFloat = 5
}
