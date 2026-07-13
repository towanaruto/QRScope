import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController!
    private var windows: WindowManager!
    private var monitor: RightClickMonitor!
    private let history = HistoryStore()
    private let overlay = OverlayController()
    private let capturer = ScreenCapturer()
    private let updater = UpdateChecker()

    /// 連打時に古い検出結果を破棄するための世代カウンタ
    private var clickGeneration = 0

    /// 権限案内チップを出しすぎないためのスロットル
    private var lastPermissionPromptAt: Date = .distantPast

    var detectionEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "detectionEnabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "detectionEnabled")
            if !newValue { overlay.hide() }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement(アクセサリ)アプリはメインメニューを持たないため、
        // 標準の Edit メニューが無いと Cmd+V などがテキスト欄に届かない。
        // ペースト等を効かせるために最小限のメニューを用意する。
        installMainMenu()

        windows = WindowManager(history: history)
        statusBar = StatusBarController(actions: StatusBarActions(
            isDetectionEnabled: { [weak self] in self?.detectionEnabled ?? false },
            toggleDetection: { [weak self] in self?.detectionEnabled.toggle() },
            scanFullScreen: { [weak self] in self?.scanFullScreen() },
            showScanner: { [weak self] in self?.windows.showScanner() },
            showHistory: { [weak self] in self?.windows.showHistory() },
            showGenerator: { [weak self] in self?.windows.showGenerator() },
            availableUpdateVersion: { [weak self] in self?.updater.availableVersion },
            checkForUpdates: { [weak self] in self?.updater.userInitiatedCheck() }
        ))
        monitor = RightClickMonitor { [weak self] point in
            Task { @MainActor in self?.handleRightClick(at: point) }
        }
        monitor.start()
        updater.startPeriodicChecks()

        let hasAccess = CGPreflightScreenCaptureAccess()
        NSLog("QRScope: screen capture access = \(hasAccess)")
        writeDiagnostics(hasAccess: hasAccess)
        if !hasAccess {
            CGRequestScreenCaptureAccess()
        }
    }

    /// Cmd+X/C/V/A・取り消しを responder chain へ流すための最小メニュー。
    /// アクセサリアプリなので普段は表示されないが、ウィンドウがキーのとき
    /// キー装飾がここを経由してフィールドエディタに届く。
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.t("Quit QRScope", "QRScopeを終了"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: L10n.t("Edit", "編集"))
        editMenu.addItem(withTitle: L10n.t("Undo", "取り消す"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: L10n.t("Redo", "やり直す"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.t("Cut", "カット"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.t("Copy", "コピー"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.t("Paste", "ペースト"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.t("Select All", "すべてを選択"),
                         action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    /// 起動時の権限状態を Application Support に記録する(トラブルシュート用)
    private func writeDiagnostics(hasAccess: Bool) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QRScope", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let text = "launchedAt=\(Date())\nscreenCaptureAccess=\(hasAccess)\n"
        try? text.write(to: dir.appendingPathComponent("diagnostics.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: - 右クリック検出

    private func handleRightClick(at point: CGPoint) {
        overlay.hide()
        guard detectionEnabled else { return }

        // 選択テキストが URL、または埋め込みリンクを右クリックしたときは、
        // QR検出とは独立に「QRを作成」チップを出す
        let link = SelectionReader.selectedLink(at: point)

        guard CGPreflightScreenCaptureAccess() else {
            if let link {
                // 選択リンクの読み取りに画面収録は不要なので、チップだけ出す
                presentOverlay(results: [], link: link, near: point, source: HistoryItem.sourceRightClick)
            } else {
                // 権限が無いと検出できない。黙って無反応だと原因が分からないので案内する。
                presentPermissionPromptIfNeeded(near: point)
            }
            return
        }

        clickGeneration += 1
        let generation = clickGeneration

        Task { @MainActor in
            var results: [DetectedResult] = []
            do {
                if let capture = try await capturer.captureAround(point: point, radius: 340) {
                    guard generation == clickGeneration else { return }
                    let hits = await QRDetector.detect(in: capture.image)
                    results = Self.mapToScreen(hits: hits, captureRect: capture.rectInScreen, cursor: point)
                }
            } catch {
                NSLog("QRScope: capture failed: \(error.localizedDescription)")
            }
            guard generation == clickGeneration else { return }
            presentOverlay(results: results, link: link, near: point, source: HistoryItem.sourceRightClick)
        }
    }

    /// Vision の正規化座標をグローバル座標へ変換し、カーソルに近い順に並べる
    private static func mapToScreen(hits: [QRHit], captureRect: CGRect, cursor: CGPoint) -> [DetectedResult] {
        let mapped = hits.map { hit -> DetectedResult in
            let b = hit.boundingBox
            let rect = CGRect(
                x: captureRect.minX + b.minX * captureRect.width,
                y: captureRect.minY + b.minY * captureRect.height,
                width: b.width * captureRect.width,
                height: b.height * captureRect.height
            )
            return DetectedResult(payload: hit.payload, screenRect: rect)
        }
        return mapped.sorted {
            distance(from: cursor, to: $0.screenRect) < distance(from: cursor, to: $1.screenRect)
        }.prefix(4).map { $0 }
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = point.x - rect.midX
        let dy = point.y - rect.midY
        return dx * dx + dy * dy
    }

    // MARK: - 全画面スキャン

    func scanFullScreen() {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            return
        }
        let cursor = NSEvent.mouseLocation
        Task { @MainActor in
            var results: [DetectedResult] = []
            var seen = Set<String>()
            for screen in NSScreen.screens {
                guard let capture = try? await capturer.capture(rect: screen.frame, on: screen) else { continue }
                let hits = await QRDetector.detect(in: capture.image)
                for result in Self.mapToScreen(hits: hits, captureRect: capture.rectInScreen, cursor: cursor)
                where seen.insert(result.payload).inserted {
                    results.append(result)
                }
            }
            presentOverlay(results: results, near: cursor, source: HistoryItem.sourceFullScan,
                           emptyMessage: L10n.t("No QR codes found", "QRコードが見つかりませんでした"))
        }
    }

    // MARK: - オーバーレイ表示

    private func presentOverlay(results: [DetectedResult], link: SelectedLink? = nil, near point: CGPoint,
                                source: String, emptyMessage: String? = nil) {
        guard !results.isEmpty || link != nil || emptyMessage != nil else { return }
        let view = OverlayView(
            results: results,
            emptyMessage: (results.isEmpty && link == nil) ? emptyMessage : nil,
            onOpen: { [weak self] result in
                guard let self, let url = result.url else { return }
                NSWorkspace.shared.open(url)
                self.history.add(payload: result.payload, source: source, openedURL: url)
                self.overlay.hide()
            },
            onCopy: { [weak self] result in
                guard let self else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(result.payload, forType: .string)
                self.history.add(payload: result.payload, source: source, openedURL: nil)
                self.overlay.hide()
            },
            link: link,
            onLinkCreate: { [weak self] link in self?.showLinkQR(link, near: point) },
            onLinkCopy: { [weak self] link in self?.copyLinkQR(link) },
            onLinkSave: { [weak self] link in self?.saveLinkQR(link) }
        )
        overlay.show(view, near: point)
    }

    // MARK: - 選択リンクからのQR作成

    private static func linkQRImage(for link: SelectedLink) -> NSImage? {
        // 長いURLは低い誤り訂正レベルでしか収まらないので自動選択する
        QRCodeRenderer.bestImage(text: link.payload, pixelSize: 512)
    }

    private func showLinkQR(_ link: SelectedLink, near point: CGPoint) {
        guard let image = Self.linkQRImage(for: link) else {
            presentLinkError(near: point)
            return
        }
        let view = LinkQRView(
            link: link,
            image: image,
            onSave: { [weak self] in self?.saveLinkQR(link) },
            onEdit: { [weak self] in
                self?.overlay.hide()
                self?.windows.showGenerator(prefill: link.payload)
            }
        )
        // その場でスマホをかざして読み取れるよう、通常より長く表示する
        overlay.show(view, near: point, autoHideAfter: 60)
    }

    private func copyLinkQR(_ link: SelectedLink) {
        guard let image = Self.linkQRImage(for: link),
              let data = QRCodeRenderer.pngData(image) else {
            presentLinkError(near: NSEvent.mouseLocation)
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
        overlay.hide()
    }

    private func saveLinkQR(_ link: SelectedLink) {
        guard let image = Self.linkQRImage(for: link),
              let data = QRCodeRenderer.pngData(image) else {
            presentLinkError(near: NSEvent.mouseLocation)
            return
        }
        overlay.hide()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = Self.suggestedFileName(for: link)
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }

    /// QR化できないほど長いURLのとき、黙って消えると原因が分からないので理由を出す
    private func presentLinkError(near point: CGPoint) {
        let view = OverlayView(
            results: [],
            emptyMessage: L10n.t("URL is too long to make a QR code",
                                 "URLが長すぎてQRコードを作成できません"),
            onOpen: { _ in }, onCopy: { _ in }
        )
        overlay.show(view, near: point)
    }

    private static func suggestedFileName(for link: SelectedLink) -> String {
        guard let host = link.url.host, !host.isEmpty else { return "qrcode.png" }
        return "qr-\(host).png"
    }

    private func presentPermissionPromptIfNeeded(near point: CGPoint) {
        guard Date().timeIntervalSince(lastPermissionPromptAt) > 8 else { return }
        lastPermissionPromptAt = Date()
        let view = PermissionPromptView(onOpenSettings: {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
        })
        overlay.show(view, near: point)
    }
}
