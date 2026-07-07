import AppKit

@main
@MainActor
enum QRScopeApp {
    static func main() {
        // `--selftest`: QR生成→Vision検出のラウンドトリップ検証(GUI不要)
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest.run() ? 0 : 1)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
