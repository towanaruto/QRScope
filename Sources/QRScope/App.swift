import AppKit

@main
@MainActor
enum QRScopeApp {
    static func main() {
        // `--selftest`: QR生成→Vision検出のラウンドトリップ検証(GUI不要)
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest.run() ? 0 : 1)
        }

        // `--render-docs <outdir>`: README用画像をオフスクリーンレンダリング
        if let index = CommandLine.arguments.firstIndex(of: "--render-docs"),
           index + 1 < CommandLine.arguments.count {
            _ = NSApplication.shared
            exit(DocsRenderer.run(outputDir: CommandLine.arguments[index + 1]) ? 0 : 1)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
