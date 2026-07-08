import AppKit
import CoreImage

enum ModuleStyle: String, CaseIterable, Identifiable {
    case square
    case rounded
    case dots

    var id: String { rawValue }

    var label: String {
        switch self {
        case .square: return L10n.t("Square", "スクエア")
        case .rounded: return L10n.t("Rounded", "角丸")
        case .dots: return L10n.t("Dots", "ドット")
        }
    }
}

enum CorrectionLevel: String, CaseIterable, Identifiable {
    case l = "L"
    case m = "M"
    case q = "Q"
    case h = "H"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .l: return "L (7%)"
        case .m: return "M (15%)"
        case .q: return "Q (25%)"
        case .h: return "H (30%)"
        }
    }
}

struct QRGenerationOptions {
    var foreground: NSColor = .black
    var background: NSColor = .white
    var transparentBackground = false
    var style: ModuleStyle = .square
    var correction: CorrectionLevel = .m
    var quietZone = true
    var pixelSize = 512
}

enum QRCodeRenderer {
    /// CIQRCodeGenerator でモジュール行列を取得する(row 0 = 上端)
    static func matrix(text: String, correction: CorrectionLevel) -> [[Bool]]? {
        let data = Data(text.utf8)
        guard !data.isEmpty, let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(correction.rawValue, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }

        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var buffer = [UInt8](repeating: 255, count: width * height)
        guard let bitmap = CGContext(
            data: &buffer, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        bitmap.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // CGContext のバッファは row 0 が画像上端
        func isDark(_ x: Int, _ y: Int) -> Bool { buffer[y * width + x] < 128 }

        // 余白を除いた実モジュール領域(ファインダーパターンが角にあるので暗部の外接矩形と一致)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where isDark(x, y) {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let count = maxX - minX + 1
        guard maxY - minY + 1 == count else { return nil }

        var result = [[Bool]](repeating: [Bool](repeating: false, count: count), count: count)
        for row in 0..<count {
            for col in 0..<count {
                result[row][col] = isDark(minX + col, minY + row)
            }
        }
        return result
    }

    static func image(text: String, options: QRGenerationOptions) -> NSImage? {
        guard let matrix = matrix(text: text, correction: options.correction) else { return nil }
        let moduleCount = matrix.count
        let quiet = options.quietZone ? 4 : 0
        let total = moduleCount + quiet * 2
        let size = max(64, options.pixelSize)
        let cell = CGFloat(size) / CGFloat(total)

        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // 左上原点に変換して行列と描画座標を一致させる
        ctx.translateBy(x: 0, y: CGFloat(size))
        ctx.scaleBy(x: 1, y: -1)

        if !options.transparentBackground {
            let bg = options.background.usingColorSpace(.sRGB) ?? options.background
            ctx.setFillColor(bg.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)))
        }

        let fg = options.foreground.usingColorSpace(.sRGB) ?? options.foreground
        ctx.setFillColor(fg.cgColor)

        func moduleRect(_ row: Int, _ col: Int) -> CGRect {
            CGRect(
                x: CGFloat(col + quiet) * cell,
                y: CGFloat(row + quiet) * cell,
                width: cell, height: cell
            )
        }

        func isFinderArea(_ row: Int, _ col: Int) -> Bool {
            (row < 7 && col < 7)
                || (row < 7 && col >= moduleCount - 7)
                || (row >= moduleCount - 7 && col < 7)
        }

        // データモジュール
        for row in 0..<moduleCount {
            for col in 0..<moduleCount where matrix[row][col] && !isFinderArea(row, col) {
                let rect = moduleRect(row, col)
                switch options.style {
                case .square:
                    // 隣接モジュール間のヘアラインを防ぐためわずかに拡大
                    ctx.fill(rect.insetBy(dx: -0.25, dy: -0.25))
                case .dots:
                    ctx.fillEllipse(in: rect.insetBy(dx: cell * 0.08, dy: cell * 0.08))
                case .rounded:
                    let inset = rect.insetBy(dx: cell * 0.06, dy: cell * 0.06)
                    ctx.addPath(CGPath(
                        roundedRect: inset,
                        cornerWidth: cell * 0.3, cornerHeight: cell * 0.3,
                        transform: nil
                    ))
                    ctx.fillPath()
                }
            }
        }

        // ファインダーパターン(3隅)はスタイルに合わせた一体形状で描画する
        // (ドットスタイルでバラバラに描くと読み取り精度が落ちるため)
        for (row, col) in [(0, 0), (0, moduleCount - 7), (moduleCount - 7, 0)] {
            drawFinder(
                in: ctx,
                origin: CGPoint(x: CGFloat(col + quiet) * cell, y: CGFloat(row + quiet) * cell),
                cell: cell,
                style: options.style
            )
        }

        guard let cgImage = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }

    private static func drawFinder(in ctx: CGContext, origin: CGPoint, cell: CGFloat, style: ModuleStyle) {
        let radiusFactor: CGFloat
        switch style {
        case .square: radiusFactor = 0
        case .rounded: radiusFactor = 0.3
        case .dots: radiusFactor = 0.5
        }

        let outer = CGRect(origin: origin, size: CGSize(width: cell * 7, height: cell * 7))
        let inner = outer.insetBy(dx: cell, dy: cell)
        let center = outer.insetBy(dx: cell * 2, dy: cell * 2)

        // 外周リング(偶奇塗りで中を抜く)
        let ring = CGMutablePath()
        addRoundedRect(ring, rect: outer, radius: outer.width * radiusFactor)
        addRoundedRect(ring, rect: inner, radius: inner.width * radiusFactor)
        ctx.addPath(ring)
        ctx.fillPath(using: .evenOdd)

        // 中心の 3x3
        let centerPath = CGMutablePath()
        addRoundedRect(centerPath, rect: center, radius: center.width * radiusFactor)
        ctx.addPath(centerPath)
        ctx.fillPath()
    }

    private static func addRoundedRect(_ path: CGMutablePath, rect: CGRect, radius: CGFloat) {
        if radius < 0.01 {
            path.addRect(rect)
        } else {
            let clamped = min(radius, rect.width / 2)
            path.addRoundedRect(in: rect, cornerWidth: clamped, cornerHeight: clamped)
        }
    }

    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
