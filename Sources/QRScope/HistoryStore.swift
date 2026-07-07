import Foundation

struct HistoryItem: Identifiable, Codable, Equatable {
    var id: UUID
    var payload: String
    var date: Date
    var source: String
    var openedURL: String?
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
