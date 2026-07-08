import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneratorView: View {
    @State private var text = "https://example.com"
    @State private var foreground = Color.black
    @State private var background = Color.white
    @State private var transparent = false
    @State private var style: ModuleStyle = .square
    @State private var correction: CorrectionLevel = .m
    @State private var quietZone = true
    @State private var size: Double = 512
    @State private var copied = false

    init(demoPreset: Bool = false) {
        guard demoPreset else { return }
        _text = State(initialValue: "https://github.com/towanaruto/QRScope")
        _style = State(initialValue: .rounded)
        _foreground = State(initialValue: Color(red: 0.16, green: 0.29, blue: 0.75))
    }

    private var options: QRGenerationOptions {
        var options = QRGenerationOptions()
        options.foreground = NSColor(foreground)
        options.background = NSColor(background)
        options.transparentBackground = transparent
        options.style = style
        options.correction = correction
        options.quietZone = quietZone
        options.pixelSize = Int(size)
        return options
    }

    private var image: NSImage? {
        guard !text.isEmpty else { return nil }
        return QRCodeRenderer.image(text: text, options: options)
    }

    var body: some View {
        HStack(spacing: 0) {
            form
                .frame(width: 340)
            Divider()
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 480)
    }

    private var form: some View {
        Form {
            Section(L10n.t("Content", "内容")) {
                TextField(L10n.t("URL or text", "URL やテキスト"), text: $text, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section(L10n.t("Style", "スタイル")) {
                Picker(L10n.t("Modules", "モジュール"), selection: $style) {
                    ForEach(ModuleStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                ColorPicker(L10n.t("Foreground", "前景色"), selection: $foreground, supportsOpacity: true)
                ColorPicker(L10n.t("Background", "背景色"), selection: $background)
                    .disabled(transparent)
                Toggle(L10n.t("Transparent background", "背景を透明にする"), isOn: $transparent)
                Toggle(L10n.t("Quiet zone (margin)", "余白(クワイエットゾーン)"), isOn: $quietZone)
            }
            Section(L10n.t("Output", "出力")) {
                Picker(L10n.t("Error correction", "誤り訂正"), selection: $correction) {
                    ForEach(CorrectionLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                LabeledContent(L10n.t("Size", "サイズ")) {
                    HStack {
                        Slider(value: $size, in: 256...2048, step: 64)
                        Text("\(Int(size))px")
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var preview: some View {
        VStack(spacing: 16) {
            ZStack {
                if transparent {
                    Checkerboard()
                }
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                } else {
                    Text(text.isEmpty
                         ? L10n.t("Enter content to generate", "内容を入力してください")
                         : L10n.t("Cannot generate (content may be too long)", "生成できません(内容が長すぎる可能性があります)"))
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .frame(maxWidth: 360, maxHeight: 360)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            HStack {
                Button(L10n.t("Save PNG…", "PNGを保存…")) { save() }
                    .disabled(image == nil)
                Button(copied ? L10n.t("Copied ✓", "コピーしました ✓") : L10n.t("Copy", "コピー")) { copy() }
                    .disabled(image == nil)
            }
        }
        .padding(24)
    }

    private func save() {
        guard let image, let data = QRCodeRenderer.pngData(image) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "qrcode.png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }

    private func copy() {
        guard let image, let data = QRCodeRenderer.pngData(image) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}

/// 透明背景プレビュー用の市松模様
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 8
            for row in 0..<Int(ceil(size.height / cell)) {
                for col in 0..<Int(ceil(size.width / cell)) where (row + col) % 2 == 0 {
                    let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(Color(white: 0.85)))
                }
            }
        }
        .background(Color.white)
    }
}
