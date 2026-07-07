import AppKit
import ServiceManagement

struct StatusBarActions {
    var isDetectionEnabled: () -> Bool
    var toggleDetection: () -> Void
    var scanFullScreen: () -> Void
    var showHistory: () -> Void
    var showGenerator: () -> Void
}

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let actions: StatusBarActions

    init(actions: StatusBarActions) {
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.image = NSImage(
            systemSymbolName: "qrcode.viewfinder",
            accessibilityDescription: "QRScope"
        )
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggle = menuItem("右クリックでQRを検出", #selector(toggleDetection))
        toggle.state = actions.isDetectionEnabled() ? .on : .off
        menu.addItem(toggle)
        menu.addItem(menuItem("画面全体をスキャン", #selector(scanFullScreen), key: "s"))
        menu.addItem(.separator())

        menu.addItem(menuItem("読み取り履歴…", #selector(showHistory), key: "h"))
        menu.addItem(menuItem("QRコードを生成…", #selector(showGenerator), key: "g"))
        menu.addItem(.separator())

        let login = menuItem("ログイン時に自動起動", #selector(toggleLoginItem))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        if CGPreflightScreenCaptureAccess() {
            let granted = menuItem("画面収録: 許可済み", #selector(openScreenCaptureSettings))
            menu.addItem(granted)
        } else {
            menu.addItem(menuItem("⚠️ 画面収録を許可…", #selector(openScreenCaptureSettings)))
        }
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "QRScopeを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleDetection() { actions.toggleDetection() }
    @objc private func scanFullScreen() { actions.scanFullScreen() }
    @objc private func showHistory() { actions.showHistory() }
    @objc private func showGenerator() { actions.showGenerator() }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "ログイン項目の設定に失敗しました"
            alert.informativeText = "アプリバンドル(QRScope.app)として実行している場合のみ利用できます。\n\(error.localizedDescription)"
            alert.runModal()
        }
    }

    @objc private func openScreenCaptureSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
