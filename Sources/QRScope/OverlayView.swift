import SwiftUI

struct OverlayView: View {
    let results: [DetectedResult]
    let emptyMessage: String?
    let onOpen: (DetectedResult) -> Void
    let onCopy: (DetectedResult) -> Void
    var link: SelectedLink?
    var onLinkCreate: (SelectedLink) -> Void = { _ in }
    var onLinkCopy: (SelectedLink) -> Void = { _ in }
    var onLinkSave: (SelectedLink) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let emptyMessage {
                Label(emptyMessage, systemImage: "qrcode.viewfinder")
                    .foregroundStyle(.secondary)
            }
            if let link {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .foregroundStyle(.secondary)
                    Text(link.payload)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 280, alignment: .leading)
                        .help(link.payload)
                    Button(L10n.t("Make QR", "QRを作成")) { onLinkCreate(link) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button {
                        onLinkCopy(link)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(L10n.t("Copy QR image", "QR画像をコピー"))
                    Button {
                        onLinkSave(link)
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(L10n.t("Save QR image", "QR画像を保存"))
                }
                if !results.isEmpty {
                    Divider()
                }
            }
            ForEach(results) { result in
                HStack(spacing: 8) {
                    Image(systemName: result.url != nil ? "link" : "text.alignleft")
                        .foregroundStyle(.secondary)
                    Text(result.displayText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 280, alignment: .leading)
                        .help(result.payload)
                    if result.url != nil {
                        Button(L10n.t("Open", "開く")) { onOpen(result) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    Button {
                        onCopy(result)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(L10n.t("Copy", "コピー"))
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .fixedSize()
    }
}
