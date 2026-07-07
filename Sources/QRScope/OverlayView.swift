import SwiftUI

struct OverlayView: View {
    let results: [DetectedResult]
    let emptyMessage: String?
    let onOpen: (DetectedResult) -> Void
    let onCopy: (DetectedResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let emptyMessage {
                Label(emptyMessage, systemImage: "qrcode.viewfinder")
                    .foregroundStyle(.secondary)
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
                        Button("開く") { onOpen(result) }
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
                    .help("コピー")
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
