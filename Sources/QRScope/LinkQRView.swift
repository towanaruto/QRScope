import AppKit
import SwiftUI

/// 選択リンクから生成した QR のプレビューチップ。
/// その場でスマホ読み取り・コピー・保存・ジェネレーターでの調整ができる。
struct LinkQRView: View {
    let link: SelectedLink
    let image: NSImage
    let onSave: () -> Void
    let onEdit: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            Text(link.payload)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 200)
                .help(link.payload)
            HStack(spacing: 8) {
                Button(copied ? L10n.t("Copied ✓", "コピーしました ✓") : L10n.t("Copy", "コピー")) {
                    copy()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button(L10n.t("Save…", "保存…")) { onSave() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L10n.t("Customize in generator", "ジェネレーターでカスタマイズ"))
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

    private func copy() {
        guard let data = QRCodeRenderer.pngData(image) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}
