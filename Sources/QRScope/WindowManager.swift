import AppKit
import SwiftUI

/// 履歴・生成ウィンドウの生成と再利用を管理する
@MainActor
final class WindowManager {
    private let history: HistoryStore
    private var historyWindow: NSWindow?
    private var generatorWindow: NSWindow?
    private var scannerWindow: NSWindow?
    private var scanner: CameraScanner?

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

    func showGenerator(prefill: String? = nil) {
        if generatorWindow == nil {
            generatorWindow = makeWindow(
                title: L10n.t("Generate QR Code", "QRコードを生成"),
                size: NSSize(width: 760, height: 540),
                root: GeneratorView(initialText: prefill)
            )
        } else if let prefill {
            // 既存ウィンドウでも選択リンクを反映した内容に差し替える
            generatorWindow?.contentViewController = NSHostingController(
                rootView: GeneratorView(initialText: prefill)
            )
        }
        present(generatorWindow)
    }

    func showScanner() {
        if scannerWindow == nil {
            let scanner = CameraScanner()
            self.scanner = scanner
            let window = makeWindow(
                title: L10n.t("Scan with Camera", "カメラで読み取り"),
                size: NSSize(width: 640, height: 560),
                root: ScannerView(history: history, scanner: scanner)
            )
            scannerWindow = window
            // SwiftUI の onDisappear はウィンドウクローズでは発火しないため、
            // 通知で確実にカメラを止める
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.scanner?.stop() }
            }
        }
        present(scannerWindow)
        // 再表示時はカメラを起動し直す(閉じた時に stop している)
        scanner?.start()
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
