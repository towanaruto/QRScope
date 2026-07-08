import SwiftUI

/// 画面収録の許可が無いときに、右クリック位置へ表示する案内チップ。
/// このパネル自体は画面キャプチャ権限を必要としないため、権限が無くても表示できる。
struct PermissionPromptView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("Screen Recording permission is required to read QR codes",
                            "QRを読むには画面収録の許可が必要です"))
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.t("After granting, restart QRScope",
                            "許可した後、QRScope を再起動してください"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(L10n.t("Open Settings", "設定を開く")) { onOpenSettings() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
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
