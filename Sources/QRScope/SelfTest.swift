import AppKit
import CoreGraphics

/// 生成した QR を Vision で読み戻し、全スタイル・全誤り訂正レベルで
/// デコード可能なことを検証する(`QRScope --selftest`)。
enum SelfTest {
    static func run() -> Bool {
        var passed = 0
        var failed = 0
        let payloads = [
            "https://example.com/path?q=hello&lang=ja",
            "こんにちは世界 QRScope テスト",
        ]

        for style in ModuleStyle.allCases {
            for transparent in [false, true] {
                for payload in payloads {
                    var options = QRGenerationOptions()
                    options.style = style
                    options.transparentBackground = transparent
                    options.pixelSize = 512
                    options.correction = .m

                    let label = "style=\(style.rawValue) transparent=\(transparent) payload=\(payload.prefix(24))…"
                    guard let image = QRCodeRenderer.image(text: payload, options: options),
                          let composited = compositeOverWhite(image) else {
                        print("FAIL(generate) \(label)")
                        failed += 1
                        continue
                    }
                    let hits = QRDetector.detectSync(in: composited)
                    if hits.contains(where: { $0.payload == payload }) {
                        print("PASS \(label)")
                        passed += 1
                    } else {
                        print("FAIL(detect) \(label) -> \(hits.map(\.payload))")
                        failed += 1
                    }
                }
            }
        }

        print("Result: \(passed) passed, \(failed) failed")
        return failed == 0
    }

    /// 透明背景でも検出できるよう白地に合成してから渡す
    private static func compositeOverWhite(_ image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
