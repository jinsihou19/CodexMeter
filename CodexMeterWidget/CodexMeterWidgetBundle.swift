import WidgetKit
import SwiftUI

@main
struct CodexMeterWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodexMeterWidget()
        LocalCodexUsageWidget()
    }
}
