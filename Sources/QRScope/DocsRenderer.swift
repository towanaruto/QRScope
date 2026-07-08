import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// README 用のスクリーンショット/GIF を実際の UI コンポーネントから
/// オフスクリーンレンダリングする(`QRScope --render-docs <outdir>`)。
/// 画面収録権限が不要で、誰でも同じ画像を再生成できる。
@MainActor
enum DocsRenderer {
    static func run(outputDir: String) -> Bool {
        L10n.forceEnglish = true  // ドキュメントは英語で統一
        let dir = URL(fileURLWithPath: outputDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var ok = true

        // 右クリック→チップ表示のヒーローショット
        ok = writePNG(snapshot(DemoPosterView(cursorOnQR: true, showChip: true)),
                      to: dir.appendingPathComponent("overlay.png")) && ok

        // デモGIF: カーソル移動 → 右クリック → チップ表示
        let frames: [(NSImage?, Double)] = [
            (snapshot(DemoPosterView(cursorOnQR: false, showChip: false)), 1.0),
            (snapshot(DemoPosterView(cursorOnQR: true, showChip: false)), 0.9),
            (snapshot(DemoPosterView(cursorOnQR: true, showChip: true)), 3.0),
        ]
        ok = writeGIF(frames, to: dir.appendingPathComponent("demo.gif")) && ok

        // 生成ウィンドウ
        ok = writePNG(snapshot(GeneratorView(demoPreset: true), size: CGSize(width: 780, height: 560)),
                      to: dir.appendingPathComponent("generator.png")) && ok

        // 履歴ウィンドウ(サンプルデータ)
        ok = writePNG(snapshot(HistoryView(store: HistoryStore(demo: true)), size: CGSize(width: 560, height: 380)),
                      to: dir.appendingPathComponent("history.png")) && ok

        print(ok ? "docs rendered to \(dir.path)" : "docs rendering FAILED")
        return ok
    }

    // MARK: - レンダリング

    private static func snapshot<V: View>(_ view: V, size: CGSize? = nil) -> NSImage? {
        let hosting = NSHostingView(rootView: AnyView(view))
        let renderSize = size ?? hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: renderSize)

        // マテリアル等が正しく描画されるよう、オフスクリーンのウィンドウに載せる
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: renderSize),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // List などの遅延レイアウトを反映させる
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = NSImage(size: renderSize)
        image.addRepresentation(rep)
        return image
    }

    private static func writePNG(_ image: NSImage?, to url: URL) -> Bool {
        guard let image, let data = QRCodeRenderer.pngData(image) else { return false }
        return (try? data.write(to: url)) != nil
    }

    private static func writeGIF(_ frames: [(NSImage?, Double)], to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil
        ) else { return false }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        for (image, delay) in frames {
            var rect = CGRect(origin: .zero, size: image?.size ?? .zero)
            guard let cgImage = image?.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
                return false
            }
            CGImageDestinationAddImage(destination, cgImage, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay,
                ]
            ] as CFDictionary)
        }
        return CGImageDestinationFinalize(destination)
    }
}

// MARK: - デモシーン

/// PDF を開いているウィンドウ+QR+チップを模したヒーローショット。
/// チップは実際の OverlayView をそのまま使用する。
private struct DemoPosterView: View {
    let cursorOnQR: Bool
    let showChip: Bool

    private let canvas = CGSize(width: 880, height: 460)
    private let qrCursor = CGPoint(x: 228, y: 292)
    private let awayCursor = CGPoint(x: 640, y: 420)
    private static let payload = "https://github.com/towanaruto/QRScope"

    private var qrImage: NSImage? {
        var options = QRGenerationOptions()
        options.style = .rounded
        options.pixelSize = 512
        return QRCodeRenderer.image(text: Self.payload, options: options)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(red: 0.42, green: 0.52, blue: 0.72), Color(red: 0.56, green: 0.46, blue: 0.66)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            fakeWindow
                .frame(width: 760, height: 360)
                .offset(x: 60, y: 50)

            if showChip {
                OverlayView(
                    results: [DetectedResult(payload: Self.payload, screenRect: .zero)],
                    emptyMessage: nil,
                    onOpen: { _ in }, onCopy: { _ in }
                )
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                .offset(x: qrCursor.x + 16, y: qrCursor.y - 62)
            }

            let cursor = cursorOnQR ? qrCursor : awayCursor
            Image(nsImage: NSCursor.arrow.image)
                .offset(x: cursor.x - 5, y: cursor.y - 5)
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    private var fakeWindow: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle().fill(Color(white: 0.93))
                HStack(spacing: 7) {
                    Circle().fill(Color(red: 1.0, green: 0.38, blue: 0.35)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.26)).frame(width: 12, height: 12)
                    Spacer()
                }
                .padding(.leading, 14)
                Text("event-poster.pdf")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 36)

            HStack(spacing: 32) {
                VStack(spacing: 10) {
                    if let qrImage {
                        Image(nsImage: qrImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 170, height: 170)
                    }
                    Text("Scan for details")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Spring Tech Meetup 2026")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(white: 0.2))
                    fakeTextLines
                }
                Spacer()
            }
            .padding(28)
            .frame(maxHeight: .infinity)
            .background(Color(white: 0.98))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
    }

    private var fakeTextLines: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach([320, 280, 300, 180], id: \.self) { width in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(white: 0.82))
                    .frame(width: CGFloat(width), height: 12)
            }
        }
    }
}
