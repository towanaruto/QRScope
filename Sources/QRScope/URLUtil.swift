import Foundation

struct DetectedResult: Identifiable {
    let id = UUID()
    let payload: String
    let screenRect: CGRect
    let url: URL?

    init(payload: String, screenRect: CGRect) {
        self.payload = payload
        self.screenRect = screenRect
        self.url = URLUtil.openableURL(from: payload)
    }

    var displayText: String {
        payload.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum URLUtil {
    /// 任意スキームを開くと危険なため、一般的なスキームのみ「開く」を許可する
    private static let openableSchemes: Set<String> = [
        "http", "https", "mailto", "tel", "sms", "facetime", "maps",
    ]

    static func openableURL(from payload: String) -> URL? {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }

        if let url = URL(string: text), let scheme = url.scheme?.lowercased() {
            return openableSchemes.contains(scheme) ? url : nil
        }
        // スキームなしでもドメインらしき文字列は https:// を補完
        if text.range(of: #"^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}(:\d+)?(/\S*)?$"#,
                      options: .regularExpression) != nil {
            return URL(string: "https://" + text)
        }
        return nil
    }
}
