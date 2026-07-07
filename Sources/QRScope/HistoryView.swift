import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @State private var query = ""

    private var filtered: [HistoryItem] {
        guard !query.isEmpty else { return store.items }
        return store.items.filter { $0.payload.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("検索", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button("すべて削除", role: .destructive) {
                    store.clear()
                }
                .disabled(store.items.isEmpty)
            }
            .padding(10)
            Divider()
            if filtered.isEmpty {
                Spacer()
                Text(store.items.isEmpty ? "履歴はありません" : "該当する項目がありません")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(filtered) { item in
                    row(item)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
    }

    @ViewBuilder
    private func row(_ item: HistoryItem) -> some View {
        let url = URLUtil.openableURL(from: item.payload)
        HStack(spacing: 10) {
            Image(systemName: url != nil ? "link" : "text.alignleft")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.payload)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.payload)
                Text("\(item.date.formatted(date: .abbreviated, time: .shortened)) ・ \(item.source)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let url {
                Button("開く") {
                    NSWorkspace.shared.open(url)
                }
                .controlSize(.small)
            }
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(item.payload, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .controlSize(.small)
            .help("コピー")
            Button(role: .destructive) {
                store.remove(item)
            } label: {
                Image(systemName: "trash")
            }
            .controlSize(.small)
            .help("削除")
        }
        .padding(.vertical, 2)
    }
}
