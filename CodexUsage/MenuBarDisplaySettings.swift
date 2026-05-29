import AppKit
import CodexUsageShared
import Foundation
import SwiftUI

enum MenuBarPreferenceKeys {
    static let layoutDensity = "menuBar.layoutDensity"
    static let itemSpacing = "menuBar.itemSpacing"
    static let rowSpacing = "menuBar.rowSpacing"
    static let numberFontSize = "menuBar.numberFontSize"
    static let numberFontWeight = "menuBar.numberFontWeight"
    static let goodColorHex = "menuBar.goodColorHex"
    static let warningColorHex = "menuBar.warningColorHex"
    static let dangerColorHex = "menuBar.dangerColorHex"
}

enum MenuBarNumberFontWeight: String, CaseIterable, Identifiable {
    case regular
    case medium
    case semibold

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .regular:
            return "偏细"
        case .medium:
            return "适中"
        case .semibold:
            return "偏粗"
        }
    }

    var fontWeight: Font.Weight {
        switch self {
        case .regular:
            return .regular
        case .medium:
            return .medium
        case .semibold:
            return .semibold
        }
    }
}

enum MenuBarLayoutDensity: String, CaseIterable, Identifiable {
    case compact
    case normal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .compact:
            return "紧凑"
        case .normal:
            return "正常"
        }
    }

    var statusItemWidth: CGFloat {
        switch self {
        case .compact:
            return 38
        case .normal:
            return 40
        }
    }
}

struct MenuBarDisplaySettings: Equatable {
    static let defaultLayoutDensity = MenuBarLayoutDensity.compact
    static let defaultItemSpacing = 1.0
    static let defaultRowSpacing = -2.0
    static let defaultNumberFontSize = 9.0
    static let defaultNumberFontWeight = MenuBarNumberFontWeight.medium
    static let defaultGoodColorHex = "#1AB85C"
    static let defaultWarningColorHex = "#F5931A"
    static let defaultDangerColorHex = "#F23838"

    let layoutDensity: MenuBarLayoutDensity
    let itemSpacing: Double
    let rowSpacing: Double
    let numberFontSize: Double
    let numberFontWeight: MenuBarNumberFontWeight
    let goodColorHex: String
    let warningColorHex: String
    let dangerColorHex: String

    init(
        layoutDensity: MenuBarLayoutDensity = Self.defaultLayoutDensity,
        itemSpacing: Double = Self.defaultItemSpacing,
        rowSpacing: Double = Self.defaultRowSpacing,
        numberFontSize: Double = Self.defaultNumberFontSize,
        numberFontWeight: MenuBarNumberFontWeight = Self.defaultNumberFontWeight,
        goodColorHex: String = Self.defaultGoodColorHex,
        warningColorHex: String = Self.defaultWarningColorHex,
        dangerColorHex: String = Self.defaultDangerColorHex
    ) {
        self.layoutDensity = layoutDensity
        self.itemSpacing = Self.clamp(itemSpacing, min: 0, max: 8)
        self.rowSpacing = Self.clamp(rowSpacing, min: -5, max: 6)
        self.numberFontSize = Self.clamp(numberFontSize, min: 7, max: 13)
        self.numberFontWeight = numberFontWeight
        self.goodColorHex = Self.normalizedColorHex(goodColorHex, fallback: Self.defaultGoodColorHex)
        self.warningColorHex = Self.normalizedColorHex(warningColorHex, fallback: Self.defaultWarningColorHex)
        self.dangerColorHex = Self.normalizedColorHex(dangerColorHex, fallback: Self.defaultDangerColorHex)
    }

    init(defaults: UserDefaults = .standard) {
        self.init(
            layoutDensity: MenuBarLayoutDensity(
                rawValue: defaults.string(forKey: MenuBarPreferenceKeys.layoutDensity) ?? ""
            ) ?? Self.defaultLayoutDensity,
            itemSpacing: defaults.object(forKey: MenuBarPreferenceKeys.itemSpacing) as? Double
                ?? Self.defaultItemSpacing,
            rowSpacing: defaults.object(forKey: MenuBarPreferenceKeys.rowSpacing) as? Double
                ?? Self.defaultRowSpacing,
            numberFontSize: defaults.object(forKey: MenuBarPreferenceKeys.numberFontSize) as? Double
                ?? Self.defaultNumberFontSize,
            numberFontWeight: MenuBarNumberFontWeight(
                rawValue: defaults.string(forKey: MenuBarPreferenceKeys.numberFontWeight) ?? ""
            ) ?? Self.defaultNumberFontWeight,
            goodColorHex: defaults.string(forKey: MenuBarPreferenceKeys.goodColorHex)
                ?? Self.defaultGoodColorHex,
            warningColorHex: defaults.string(forKey: MenuBarPreferenceKeys.warningColorHex)
                ?? Self.defaultWarningColorHex,
            dangerColorHex: defaults.string(forKey: MenuBarPreferenceKeys.dangerColorHex)
                ?? Self.defaultDangerColorHex
        )
    }

    var statusItemWidth: CGFloat {
        layoutDensity.statusItemWidth
    }

    var statusLabelHeight: CGFloat {
        22
    }

    func color(for tone: UsageRemainingTone) -> Color {
        switch tone {
        case .unavailable:
            return Color(nsColor: .secondaryLabelColor)
        case .good:
            return Color(hexRGB: goodColorHex)
        case .warning:
            return Color(hexRGB: warningColorHex)
        case .danger:
            return Color(hexRGB: dangerColorHex)
        }
    }

    static func normalizedColorHex(_ value: String, fallback: String) -> String {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let prefixed = candidate.hasPrefix("#") ? candidate : "#\(candidate)"
        let pattern = /^#[0-9A-F]{6}$/
        if prefixed.wholeMatch(of: pattern) != nil {
            return prefixed
        }
        return fallback
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}

enum MenuBarPopoverPositioning {
    static let defaultVerticalGap: CGFloat = 4

    static func alignedFrame(
        popoverFrame: NSRect,
        anchorScreenRect: NSRect,
        verticalGap: CGFloat = defaultVerticalGap
    ) -> NSRect {
        var alignedFrame = popoverFrame
        alignedFrame.origin.y += anchorScreenRect.minY - verticalGap - popoverFrame.maxY
        return alignedFrame
    }
}

extension UsageRemainingTone {
    func statusBarColor(settings: MenuBarDisplaySettings) -> Color {
        settings.color(for: self)
    }
}

struct CodexConfigurationInfo: Equatable {
    struct Row: Equatable, Identifiable {
        let title: String
        let value: String

        var id: String {
            title
        }
    }

    let dataSource: String
    let endpoint: String
    let codexHomePath: String
    let authFileExists: Bool

    var displayRows: [Row] {
        [
            Row(title: "数据来源", value: dataSource),
            Row(title: "接口", value: endpoint),
            Row(title: "CODEX_HOME", value: codexHomePath),
            Row(title: "登录信息", value: authFileExists ? "已找到" : "未找到")
        ]
    }

    static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        store: UsageSnapshotStore = UsageSnapshotStore()
    ) -> CodexConfigurationInfo {
        let authFileURL = DirectCodexUsageClient.defaultAuthFileURL(environment: environment)

        return CodexConfigurationInfo(
            dataSource: "ChatGPT Codex usage",
            endpoint: DirectCodexUsageClient.defaultEndpointURL.absoluteString,
            codexHomePath: authFileURL.deletingLastPathComponent().path,
            authFileExists: FileManager.default.fileExists(atPath: authFileURL.path)
        )
    }
}

extension Color {
    init(hexRGB: String) {
        let normalized = MenuBarDisplaySettings.normalizedColorHex(
            hexRGB,
            fallback: MenuBarDisplaySettings.defaultGoodColorHex
        )
        let value = String(normalized.dropFirst())
        let scanner = Scanner(string: value)
        var hexNumber: UInt64 = 0
        scanner.scanHexInt64(&hexNumber)
        self.init(
            red: Double((hexNumber & 0xFF0000) >> 16) / 255,
            green: Double((hexNumber & 0x00FF00) >> 8) / 255,
            blue: Double(hexNumber & 0x0000FF) / 255
        )
    }

    var hexRGB: String? {
        guard let color = NSColor(self).usingColorSpace(.deviceRGB) else {
            return nil
        }
        return String(
            format: "#%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
    }
}
