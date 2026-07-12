@preconcurrency import AVFoundation
import AppKit
import SwiftUI

/// Continuity Camera(iPhone)や内蔵カメラの映像から QR を読み取る。
/// iPhone が近く(同じ Apple ID・Wi-Fi/Bluetooth オン)にあれば入力デバイスに
/// 選ぶだけでカメラが自動起動する。
@MainActor
final class CameraScanner: ObservableObject {
    enum ScanState {
        case idle          // セッション停止中
        case unauthorized  // カメラ権限なし
        case noCamera      // 使えるカメラが1台もない
        case scanning
        case found
    }

    let session = AVCaptureSession()
    @Published private(set) var state: ScanState = .idle
    @Published private(set) var devices: [AVCaptureDevice] = []
    @Published private(set) var selectedDeviceID: String = ""
    @Published private(set) var hits: [QRHit] = []

    private let sessionQueue = DispatchQueue(label: "com.qrscope.camera")
    private let output = AVCaptureVideoDataOutput()
    private let frameDelegate = FrameDelegate()
    private var observers: [NSObjectProtocol] = []

    func start() {
        // ウィンドウを表示するたびに呼ばれるため冪等にする。
        // スキャン中・結果表示中の再呼び出し(メニュー再クリック等)では何もしない。
        guard state == .idle || state == .unauthorized || state == .noCamera else { return }
        hits = []
        frameDelegate.onDetect = { [weak self] hits in
            Task { @MainActor in self?.handleDetection(hits) }
        }
        // iPhone の接近/離脱でデバイス一覧を追従させる
        if observers.isEmpty {
            for name in [AVCaptureDevice.wasConnectedNotification,
                         AVCaptureDevice.wasDisconnectedNotification] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.refreshDevices() }
                })
            }
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            beginSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.beginSession()
                    } else {
                        self?.state = .unauthorized
                    }
                }
            }
        default:
            state = .unauthorized
        }
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
                NSLog("QRScope: camera session stopped")
            }
        }
        state = .idle
        hits = []
    }

    func rescan() {
        hits = []
        state = .scanning
        sessionQueue.async { [session] in
            if !session.isRunning {
                session.startRunning()
                NSLog("QRScope: camera session started (rescan)")
            }
        }
    }

    func selectDevice(id: String) {
        guard id != selectedDeviceID,
              let device = devices.first(where: { $0.uniqueID == id }) else { return }
        selectedDeviceID = id
        attach(device)
        if state == .found { rescan() }
    }

    private func beginSession() {
        refreshDevices()
        guard let device = devices.first(where: { $0.uniqueID == selectedDeviceID }) ?? devices.first else {
            state = .noCamera
            return
        }
        selectedDeviceID = device.uniqueID
        state = .scanning
        attach(device)
    }

    private func refreshDevices() {
        // Continuity Camera(iPhone)を優先して先頭に並べる
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.continuityCamera, .builtInWideAngleCamera, .external],
            mediaType: .video, position: .unspecified
        )
        devices = discovery.devices.sorted {
            ($0.deviceType == .continuityCamera ? 0 : 1) < ($1.deviceType == .continuityCamera ? 0 : 1)
        }
        if state == .noCamera, !devices.isEmpty {
            beginSession()
        } else if state == .scanning || state == .found,
                  !devices.contains(where: { $0.uniqueID == selectedDeviceID }) {
            // 使用中のカメラが切断された
            if let fallback = devices.first {
                selectedDeviceID = fallback.uniqueID
                attach(fallback)
            } else {
                state = .noCamera
            }
        }
    }

    private func attach(_ device: AVCaptureDevice) {
        sessionQueue.async { [session, output, frameDelegate, sessionQueue] in
            session.beginConfiguration()
            for input in session.inputs {
                session.removeInput(input)
            }
            if let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }
            if session.outputs.isEmpty, session.canAddOutput(output) {
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(frameDelegate, queue: sessionQueue)
                session.addOutput(output)
            }
            session.commitConfiguration()
            if !session.isRunning {
                session.startRunning()
                NSLog("QRScope: camera session started (\(device.localizedName))")
            }
        }
    }

    private func handleDetection(_ hits: [QRHit]) {
        guard state == .scanning else { return }
        self.hits = Array(hits.prefix(3))
        state = .found
        sessionQueue.async { [session] in
            session.stopRunning()
            NSLog("QRScope: camera session stopped (QR found)")
        }
    }
}

/// フレーム毎の検出コールバック(sessionQueue 上で呼ばれる)。
/// onDetect はセッション開始前に一度だけ設定するため実質不変。
private final class FrameDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onDetect: (([QRHit]) -> Void)?
    private var lastScan = Date.distantPast

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // 毎フレーム検出すると CPU を食うので間引く
        guard Date().timeIntervalSince(lastScan) > 0.25,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastScan = Date()
        let hits = QRDetector.detectSync(in: buffer)
        if !hits.isEmpty {
            onDetect?(hits)
        }
    }
}

// MARK: - UI

struct ScannerView: View {
    let history: HistoryStore
    /// ライフサイクルは WindowManager が管理する(表示で start、クローズで stop)
    @ObservedObject var scanner: CameraScanner
    @State private var copiedPayload: String?

    var body: some View {
        VStack(spacing: 12) {
            if scanner.devices.count > 1 {
                Picker(L10n.t("Camera", "カメラ"), selection: Binding(
                    get: { scanner.selectedDeviceID },
                    set: { scanner.selectDevice(id: $0) }
                )) {
                    ForEach(scanner.devices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID)
                    }
                }
                .frame(maxWidth: 360)
            }

            ZStack {
                CameraPreview(session: scanner.session)
                overlayMessage
            }
            .frame(minWidth: 480, minHeight: 320)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            resultArea
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 480)
    }

    @ViewBuilder
    private var overlayMessage: some View {
        switch scanner.state {
        case .unauthorized:
            messagePanel(
                L10n.t("Camera access is required", "カメラへのアクセス許可が必要です"),
                systemImage: "video.slash"
            ) {
                Button(L10n.t("Open System Settings…", "システム設定を開く…")) {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
                    NSWorkspace.shared.open(url)
                }
            }
        case .noCamera:
            messagePanel(
                L10n.t("No camera found. Keep your iPhone nearby and unlocked (same Apple ID, Wi-Fi and Bluetooth on).",
                       "カメラが見つかりません。iPhoneを近くに置いてロックを解除してください(同じApple ID・Wi-Fi/Bluetoothオン)。"),
                systemImage: "iphone.slash"
            ) { EmptyView() }
        case .scanning:
            VStack {
                Spacer()
                Label(L10n.t("Point the camera at a QR code", "QRコードをカメラにかざしてください"),
                      systemImage: "qrcode.viewfinder")
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 12)
            }
        default:
            EmptyView()
        }
    }

    private func messagePanel<Actions: View>(
        _ text: String, systemImage: String, @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(text)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            actions()
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var resultArea: some View {
        if scanner.state == .found {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(scanner.hits, id: \.payload) { hit in
                    resultRow(hit)
                }
                HStack {
                    Spacer()
                    Button(L10n.t("Scan Again", "再スキャン")) { scanner.rescan() }
                }
            }
        } else {
            // found 時とおおよそ高さを揃えてレイアウトの跳ねを抑える
            Color.clear.frame(height: 28)
        }
    }

    private func resultRow(_ hit: QRHit) -> some View {
        let url = URLUtil.openableURL(from: hit.payload)
        return HStack(spacing: 8) {
            Image(systemName: url != nil ? "link" : "text.alignleft")
                .foregroundStyle(.secondary)
            Text(hit.payload.trimmingCharacters(in: .whitespacesAndNewlines))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(hit.payload)
            if let url {
                Button(L10n.t("Open", "開く")) {
                    NSWorkspace.shared.open(url)
                    history.add(payload: hit.payload, source: HistoryItem.sourceCamera, openedURL: url)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(hit.payload, forType: .string)
                history.add(payload: hit.payload, source: HistoryItem.sourceCamera, openedURL: nil)
                copiedPayload = hit.payload
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copiedPayload = nil
                }
            } label: {
                Image(systemName: copiedPayload == hit.payload ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n.t("Copy", "コピー"))
        }
    }
}

/// AVCaptureVideoPreviewLayer を SwiftUI に載せる
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
