import AppKit
import ApplicationServices

/// 選択中のテキストが URL として解釈できたもの
struct SelectedLink {
    let payload: String
    let url: URL
}

/// アクセシビリティ API でリンクを読み取る。画面収録とは別に「アクセシビリティ」
/// 権限が必要で、未許可の間はこの機能だけが無効になる(QR検出は従来通り動く)。
///
/// 2通りの経路でリンクを取得する:
/// 1. 選択テキストがそのまま URL のとき(kAXSelectedText)
/// 2. リンクが埋め込まれたテキスト(表示文字と URL が異なるハイパーリンク)を
///    右クリックしたとき(クリック位置の要素の kAXURL)
enum SelectionReader {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// システムの許可ダイアログを表示して設定画面へ誘導する
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// - Parameter point: 右クリック位置(Cocoa 画面座標=左下原点)。
    ///   埋め込みリンクの検出に使う。nil の場合は選択テキストのみを見る。
    static func selectedLink(at point: CGPoint? = nil) -> SelectedLink? {
        guard isTrusted else { return nil }
        if let link = linkFromSelectedText() { return link }
        if let point, let link = linkFromElement(at: point) { return link }
        return nil
    }

    /// フォーカス中の UI 要素の選択テキストが URL ならリンクとして返す
    private static func linkFromSelectedText() -> SelectedLink? {
        // システムワイド要素のフォーカス取得は環境により kAXErrorCannotComplete に
        // なることがあるため、前面アプリの AX 要素から辿る
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let app = AXUIElementCreateApplication(front.processIdentifier)
        // 応答しないアプリを相手にしても右クリック処理全体が固まらないようにする
        AXUIElementSetMessagingTimeout(app, 0.3)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let focused = focusedRef as! AXUIElement
        AXUIElementSetMessagingTimeout(focused, 0.3)

        var textRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused, kAXSelectedTextAttribute as CFString, &textRef
        ) == .success,
              let text = textRef as? String else { return nil }
        return makeLink(from: text)
    }

    /// 右クリック位置の要素(および数階層の祖先)から kAXURL を探す。
    /// AXStaticText の親が AXLink というケースがあるため祖先も辿る。
    private static func linkFromElement(at cocoaPoint: CGPoint) -> SelectedLink? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        let p = quartzPoint(from: cocoaPoint)

        var elementRef: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &elementRef) == .success,
              var current = elementRef else { return nil }

        for _ in 0..<6 {
            AXUIElementSetMessagingTimeout(current, 0.3)
            if let link = linkFromURLAttribute(of: current) { return link }
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parentRef, CFGetTypeID(parentRef) == AXUIElementGetTypeID() else { break }
            current = parentRef as! AXUIElement
        }
        return nil
    }

    private static func linkFromURLAttribute(of element: AXUIElement) -> SelectedLink? {
        var urlRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &urlRef) == .success,
              let value = urlRef else { return nil }
        // kAXURL は通常 NSURL。まれに文字列で返るアプリもある。
        if let url = value as? URL { return makeLink(from: url.absoluteString) }
        if let string = value as? String { return makeLink(from: string) }
        return nil
    }

    /// クリップボード等、任意テキストからリンクを作る
    /// (選択テキスト・埋め込みリンクと同じ URL 判定を共有する)
    static func link(fromText text: String) -> SelectedLink? {
        makeLink(from: text)
    }

    private static func makeLink(from raw: String) -> SelectedLink? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // QR は最も容量の大きい L レベルでも約 2953 バイトが上限。
        // それを超える選択はどのみち QR 化できないので早期に捨てる
        // (日本語 URL は UTF-8 で膨らむためバイト数で判定する)。
        guard !trimmed.isEmpty, trimmed.utf8.count <= 2953,
              let url = URLUtil.openableURL(from: trimmed) else { return nil }
        return SelectedLink(payload: trimmed, url: url)
    }

    /// Cocoa(左下原点)座標を AX が用いる Quartz(左上原点)座標へ変換する。
    /// グローバル座標は主ディスプレイ(screens.first)の左下が原点なので、
    /// その高さで Y を反転する。
    private static func quartzPoint(from cocoaPoint: CGPoint) -> CGPoint {
        guard let primary = NSScreen.screens.first else { return cocoaPoint }
        return CGPoint(x: cocoaPoint.x, y: primary.frame.height - cocoaPoint.y)
    }
}
