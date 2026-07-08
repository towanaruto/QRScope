import Foundation

struct HistoryItem: Identifiable, Codable, Equatable {
    var id: UUID
    var payload: String
    var date: Date
    var source: String
    var openedURL: String?

    /// source は言語非依存のキーで保存し、表示時にローカライズする
    static let sourceRightClick = "right-click"
    static let sourceFullScan = "full-scan"

    var sourceLabel: String {
        switch source {
        case Self.sourceRightClick: return L10n.t("Right-click", "右クリック")
        case Self.sourceFullScan: return L10n.t("Full-screen scan", "全画面スキャン")
        default: return source
        }
    }
}

/// 読み取り履歴。Application Support 配下の JSON に永続化する。
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [HistoryItem] = []

    private static let maxItems = 500

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QRScope", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    init() {
        load()
    }

    /// ドキュメント用スクリーンショットのためのサンプルデータ(ディスクに触れない)
    init(demo: Bool) {
        guard demo else { load(); return }
        let now = Date()
        items = [
            HistoryItem(id: UUID(), payload: "https://github.com/towanaruto/QRScope",
                        date: now.addingTimeInterval(-120), source: HistoryItem.sourceRightClick,
                        openedURL: "https://github.com/towanaruto/QRScope"),
            HistoryItem(id: UUID(), payload: "https://developer.apple.com/documentation/vision",
                        date: now.addingTimeInterval(-4000), source: HistoryItem.sourceRightClick,
                        openedURL: "https://developer.apple.com/documentation/vision"),
            HistoryItem(id: UUID(), payload: "WIFI:S:CafeGuest;T:WPA;P:espresso;;",
                        date: now.addingTimeInterval(-90000), source: HistoryItem.sourceFullScan,
                        openedURL: nil),
        ]
    }

    func add(payload: String, source: String, openedURL: URL?) {
        // 同じQRを続けて操作したときの重複を防ぐ
        if let latest = items.first, latest.payload == payload,
           Date().timeIntervalSince(latest.date) < 60 {
            return
        }
        let item = HistoryItem(
            id: UUID(),
            payload: payload,
            date: Date(),
            source: source,
            openedURL: openedURL?.absoluteString
        )
        items.insert(item, at: 0)
        if items.count > Self.maxItems {
            items.removeLast(items.count - Self.maxItems)
        }
        save()
    }

    func remove(_ item: HistoryItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([HistoryItem].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
