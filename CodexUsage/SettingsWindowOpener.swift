import AppKit

@MainActor
final class SettingsWindowOpener {
    private let delayNanoseconds: UInt64
    private let activateApplication: @MainActor () -> Void
    private let showSettingsWindow: @MainActor () -> Void

    init(
        delayNanoseconds: UInt64 = 250_000_000,
        activateApplication: @escaping @MainActor () -> Void = {
            NSApp.activate(ignoringOtherApps: true)
        },
        showSettingsWindow: @escaping @MainActor () -> Void = {
            SettingsWindowPresenter.shared.show()
        }
    ) {
        self.delayNanoseconds = delayNanoseconds
        self.activateApplication = activateApplication
        self.showSettingsWindow = showSettingsWindow
    }

    func open() {
        let delay = DispatchTimeInterval.nanoseconds(Int(delayNanoseconds))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                self?.showNow()
            }
        }
    }

    func openForApplicationReopen() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.showNow()
            }
        }
    }

    func openAfterDelay() async {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        showNow()
    }

    func handleApplicationReopen() async -> Bool {
        showNow()
        return true
    }

    private func showNow() {
        activateApplication()
        showSettingsWindow()
    }
}
