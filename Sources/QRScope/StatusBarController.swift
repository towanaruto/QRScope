import AppKit
import ServiceManagement

struct StatusBarActions {
    var isDetectionEnabled: () -> Bool
    var toggleDetection: () -> Void
    var scanFullScreen: () -> Void
    var showScanner: () -> Void
    var showHistory: () -> Void
    var showGenerator: () -> Void
    var availableUpdateVersion: () -> String?
    var checkForUpdates: () -> Void
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

        let toggle = menuItem(L10n.t("Detect QR on Right-Click", "右クリックでQRを検出"), #selector(toggleDetection))
        toggle.state = actions.isDetectionEnabled() ? .on : .off
        menu.addItem(toggle)
        menu.addItem(menuItem(L10n.t("Scan Entire Screen", "画面全体をスキャン"), #selector(scanFullScreen), key: "s"))
        menu.addItem(menuItem(L10n.t("Scan with iPhone Camera…", "iPhoneカメラで読み取り…"), #selector(showScanner), key: "c"))
        menu.addItem(.separator())

        menu.addItem(menuItem(L10n.t("Scan History…", "読み取り履歴…"), #selector(showHistory), key: "h"))
        menu.addItem(menuItem(L10n.t("Generate QR Code…", "QRコードを生成…"), #selector(showGenerator), key: "g"))
        menu.addItem(.separator())

        let login = menuItem(L10n.t("Launch at Login", "ログイン時に自動起動"), #selector(toggleLoginItem))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        if CGPreflightScreenCaptureAccess() {
            let granted = menuItem(L10n.t("Screen Recording: Granted", "画面収録: 許可済み"), #selector(openScreenCaptureSettings))
            menu.addItem(granted)
        } else {
            menu.addItem(menuItem(L10n.t("⚠️ Allow Screen Recording…", "⚠️ 画面収録を許可…"), #selector(openScreenCaptureSettings)))
        }

        // 選択リンクからのQR作成に必要(未許可でもQR検出は動く)
        if SelectionReader.isTrusted {
            menu.addItem(menuItem(L10n.t("Accessibility: Granted", "アクセシビリティ: 許可済み"), #selector(openAccessibilitySettings)))
        } else {
            menu.addItem(menuItem(
                L10n.t("⚠️ Allow Accessibility (QR from selected link)…", "⚠️ アクセシビリティを許可(選択リンクからQR作成)…"),
                #selector(requestAccessibility)
            ))
        }
        if let version = actions.availableUpdateVersion() {
            menu.addItem(menuItem("⬆️ " + L10n.t("Update to \(version)…", "\(version) に更新…"), #selector(checkForUpdates)))
        } else {
            menu.addItem(menuItem(L10n.t("Check for Updates…", "アップデートを確認…"), #selector(checkForUpdates)))
        }
        menu.addItem(.separator())

        let quit = NSMenuItem(title: L10n.t("Quit QRScope", "QRScopeを終了"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleDetection() { actions.toggleDetection() }
    @objc private func scanFullScreen() { actions.scanFullScreen() }
    @objc private func showScanner() { actions.showScanner() }
    @objc private func checkForUpdates() { actions.checkForUpdates() }
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
            alert.messageText = L10n.t("Failed to update login item", "ログイン項目の設定に失敗しました")
            alert.informativeText = L10n.t(
                "This is only available when running as an app bundle (QRScope.app).\n",
                "アプリバンドル(QRScope.app)として実行している場合のみ利用できます。\n"
            ) + error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func openScreenCaptureSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    @objc private func requestAccessibility() {
        SelectionReader.requestPermission()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
