import AppKit
import ScreenCaptureKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController!
    private var windows: WindowManager!
    private var monitor: RightClickMonitor!
    private let history = HistoryStore()
    private let overlay = OverlayController()
    private let capturer = ScreenCapturer()

    /// 連打時に古い検出結果を破棄するための世代カウンタ
    private var clickGeneration = 0

    var detectionEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "detectionEnabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "detectionEnabled")
            if !newValue { overlay.hide() }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        windows = WindowManager(history: history)
        statusBar = StatusBarController(actions: StatusBarActions(
            isDetectionEnabled: { [weak self] in self?.detectionEnabled ?? false },
            toggleDetection: { [weak self] in self?.detectionEnabled.toggle() },
            scanFullScreen: { [weak self] in self?.scanFullScreen() },
            showHistory: { [weak self] in self?.windows.showHistory() },
            showGenerator: { [weak self] in self?.windows.showGenerator() }
        ))
        monitor = RightClickMonitor { [weak self] point in
            Task { @MainActor in self?.handleRightClick(at: point) }
        }
        monitor.start()

        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    // MARK: - 右クリック検出

    private func handleRightClick(at point: CGPoint) {
        overlay.hide()
        guard detectionEnabled, CGPreflightScreenCaptureAccess() else { return }

        clickGeneration += 1
        let generation = clickGeneration

        Task { @MainActor in
            do {
                guard let capture = try await capturer.captureAround(point: point, radius: 340),
                      generation == clickGeneration else { return }
                let hits = await QRDetector.detect(in: capture.image)
                guard generation == clickGeneration, !hits.isEmpty else { return }

                let results = Self.mapToScreen(hits: hits, captureRect: capture.rectInScreen, cursor: point)
                presentOverlay(results: results, near: point, source: "右クリック")
            } catch {
                NSLog("QRScope: capture failed: \(error.localizedDescription)")
            }
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
            presentOverlay(results: results, near: cursor, source: "全画面スキャン",
                           emptyMessage: "QRコードが見つかりませんでした")
        }
    }

    // MARK: - オーバーレイ表示

    private func presentOverlay(results: [DetectedResult], near point: CGPoint,
                                source: String, emptyMessage: String? = nil) {
        guard !results.isEmpty || emptyMessage != nil else { return }
        let view = OverlayView(
            results: results,
            emptyMessage: results.isEmpty ? emptyMessage : nil,
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
            }
        )
        overlay.show(view, near: point)
    }
}
