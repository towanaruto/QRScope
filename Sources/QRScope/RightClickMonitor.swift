import AppKit

/// 他アプリ上での右クリックをグローバル監視する。
/// マウスイベントの global monitor はアクセシビリティ権限なしで動作する。
final class RightClickMonitor {
    private var monitor: Any?
    private let handler: (CGPoint) -> Void

    init(handler: @escaping (CGPoint) -> Void) {
        self.handler = handler
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown]) { [handler] _ in
            handler(NSEvent.mouseLocation)
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit { stop() }
}
