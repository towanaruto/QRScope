import CoreGraphics
import Foundation
import Vision

struct QRHit {
    let payload: String
    /// Vision の正規化座標(左下原点)
    let boundingBox: CGRect
}

enum QRDetector {
    /// Vision によるバーコード検出(同期)。QR以外に Aztec / DataMatrix も対象。
    static func detectSync(in image: CGImage) -> [QRHit] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr, .aztec, .dataMatrix]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            NSLog("QRScope: barcode detection failed: \(error.localizedDescription)")
            return []
        }
        var seen = Set<String>()
        return (request.results ?? []).compactMap { observation in
            guard let payload = observation.payloadStringValue,
                  !payload.isEmpty,
                  seen.insert(payload).inserted else { return nil }
            return QRHit(payload: payload, boundingBox: observation.boundingBox)
        }
    }

    /// メインスレッドを塞がないための async ラッパー
    static func detect(in image: CGImage) async -> [QRHit] {
        await Task.detached(priority: .userInitiated) {
            detectSync(in: image)
        }.value
    }
}
