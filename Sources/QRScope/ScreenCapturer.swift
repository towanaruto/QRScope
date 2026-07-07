import AppKit
import ScreenCaptureKit

struct CaptureResult {
    let image: CGImage
    /// キャプチャした範囲(グローバル座標・左下原点・ポイント単位)
    let rectInScreen: CGRect
}

/// ScreenCaptureKit による画面キャプチャ。
/// SCShareableContent の取得は数十msかかるためキャッシュし、
/// ディスプレイ構成が変わったときだけ無効化する。
@MainActor
final class ScreenCapturer {
    private var cachedContent: SCShareableContent?

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.cachedContent = nil }
        }
    }

    private func shareableContent() async throws -> SCShareableContent {
        if let cachedContent { return cachedContent }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        cachedContent = content
        return content
    }

    /// カーソル周辺の矩形をキャプチャする
    func captureAround(point: CGPoint, radius: CGFloat) async throws -> CaptureResult? {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
                ?? NSScreen.main else { return nil }
        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                          width: radius * 2, height: radius * 2)
            .intersection(screen.frame)
        guard !rect.isEmpty else { return nil }
        return try await capture(rect: rect, on: screen)
    }

    /// グローバル座標の矩形(指定スクリーン内)をキャプチャする
    func capture(rect: CGRect, on screen: NSScreen) async throws -> CaptureResult? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            cachedContent = nil
            return nil
        }

        // 自アプリ(オーバーレイ等)はキャプチャ対象から除外
        let pid = pid_t(ProcessInfo.processInfo.processIdentifier)
        let filter: SCContentFilter
        if let ownApp = content.applications.first(where: { $0.processID == pid }) {
            filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        // グローバル座標(左下原点)→ ディスプレイローカル座標(左上原点)
        let localRect = CGRect(
            x: rect.minX - screen.frame.minX,
            y: screen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )

        let config = SCStreamConfiguration()
        config.sourceRect = localRect
        let scale = screen.backingScaleFactor
        config.width = max(1, Int(rect.width * scale))
        config.height = max(1, Int(rect.height * scale))
        config.showsCursor = false
        config.captureResolution = .best

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return CaptureResult(image: image, rectInScreen: rect)
    }
}
