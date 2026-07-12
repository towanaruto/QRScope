import AppKit
import ApplicationServices

/// 選択中のテキストが URL として解釈できたもの
struct SelectedLink {
    let payload: String
    let url: URL
}

/// アクセシビリティ API で前面アプリの選択テキストを読み取る。
/// 画面収録とは別に「アクセシビリティ」権限が必要で、
/// 未許可の間はこの機能だけが無効になる(QR検出は従来通り動く)。
enum SelectionReader {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// システムの許可ダイアログを表示して設定画面へ誘導する
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// フォーカス中の UI 要素の選択テキストが URL ならリンクとして返す
    static func selectedLink() -> SelectedLink? {
        guard isTrusted else { return nil }

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

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // QR は最も容量の大きい L レベルでも約 2953 バイトが上限。
        // それを超える選択はどのみち QR 化できないので早期に捨てる
        // (日本語 URL は UTF-8 で膨らむためバイト数で判定する)。
        guard !trimmed.isEmpty, trimmed.utf8.count <= 2953,
              let url = URLUtil.openableURL(from: trimmed) else { return nil }
        return SelectedLink(payload: trimmed, url: url)
    }
}
