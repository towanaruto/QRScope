import AppKit
import SwiftUI

/// 履歴・生成ウィンドウの生成と再利用を管理する
@MainActor
final class WindowManager {
    private let history: HistoryStore
    private var historyWindow: NSWindow?
    private var generatorWindow: NSWindow?

    init(history: HistoryStore) {
        self.history = history
    }

    func showHistory() {
        if historyWindow == nil {
            historyWindow = makeWindow(
                title: L10n.t("Scan History", "読み取り履歴"),
                size: NSSize(width: 560, height: 460),
                root: HistoryView(store: history)
            )
        }
        present(historyWindow)
    }

    func showGenerator() {
        if generatorWindow == nil {
            generatorWindow = makeWindow(
                title: L10n.t("Generate QR Code", "QRコードを生成"),
                size: NSSize(width: 760, height: 540),
                root: GeneratorView()
            )
        }
        present(generatorWindow)
    }

    private func makeWindow<Root: View>(title: String, size: NSSize, root: Root) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: root)
        window.setContentSize(size)
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
