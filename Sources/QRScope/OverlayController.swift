import AppKit
import SwiftUI

/// カーソル近くに表示するフローティングパネル。
/// 非アクティブ化パネルなので、作業中のアプリのフォーカスを奪わずにボタン操作できる。
@MainActor
final class OverlayController {
    private var panel: NSPanel?
    private var clickMonitor: Any?
    private var hideTimer: Timer?

    func show<Content: View>(_ content: Content, near point: CGPoint, autoHideAfter: TimeInterval = 12) {
        hide()

        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.contentView = hosting

        // 重要: isFloatingPanel = true はレベルを floating(3) に戻してしまうため、
        // レベル設定は必ずパネル構成の最後に行う。screenSaver(1000)は
        // コンテキストメニュー(popUpMenu=101)より上なので、これでメニューに
        // 隠れなくなる。
        panel.level = .screenSaver

        // コンテキストメニューはカーソルの右側(画面右端付近では左側)に開く。
        // 以前はチップをカーソルの上に出して縦方向にメニューを避けていたが、
        // 画面下端ではメニューが上向きに反転するため、上に出したチップが
        // メニューを隠してしまう。メニューの高さは分からず縦方向では確実に
        // 避けられないので、メニューが開く側と反対の「横」にチップを出す。
        // こうすれば上下どちらに反転してもメニューの横幅に重ならない。
        let gap: CGFloat = 12
        var origin = CGPoint(x: point.x - gap - size.width, y: point.y - size.height / 2)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            // カーソルが右端に近いとメニューは左へ開くので、チップは右に出す
            let menuOpensLeft = point.x + 220 > visible.maxX
            origin.x = menuOpensLeft ? point.x + gap : point.x - gap - size.width
            origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - size.width - 8))
            origin.y = max(visible.minY + 8, min(origin.y, visible.maxY - size.height - 8))
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        self.panel = panel

        // パネル外のクリックで閉じる(自アプリ内のクリックには発火しない)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        hideTimer = Timer.scheduledTimer(withTimeInterval: autoHideAfter, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }
}
