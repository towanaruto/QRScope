import AppKit

/// GitHub Releases を確認して自己更新する。
/// 起動10秒後と以降24時間ごとに自動チェックし、新版があれば
/// ダウンロード→バンドル差し替え→再起動を行う。
/// ad-hoc 署名のため、更新後は画面収録などの権限の再許可が必要になる。
@MainActor
final class UpdateChecker {
    struct Release {
        let version: String
        let zipURL: URL
    }

    static let repo = "towanaruto/QRScope"
    static let releasesPage = URL(string: "https://github.com/towanaruto/QRScope/releases")!
    private static let skippedVersionKey = "skippedUpdateVersion"

    private(set) var availableVersion: String?
    private var timer: Timer?
    private var installing = false

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// 自己更新はアプリバンドル実行時のみ可能(開発中の裸バイナリでは無効)
    private var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    // MARK: - チェック

    func startPeriodicChecks() {
        guard isBundled else { return }
        Task { [weak self] in
            // 起動直後の権限ダイアログ等と重ならないよう少し待つ
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            await self?.autoCheck()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.autoCheck() }
        }
    }

    /// 自動チェック: 新版があれば更新ダイアログを出す(スキップ済みバージョンは黙る)
    private func autoCheck() async {
        guard !installing,
              let release = try? await fetchLatest(),
              Self.isVersion(release.version, newerThan: currentVersion),
              UserDefaults.standard.string(forKey: Self.skippedVersionKey) != release.version
        else { return }
        availableVersion = release.version
        promptAndInstall(release, allowSkip: true)
    }

    /// メニューからの手動チェック: 結果を必ず表示する
    func userInitiatedCheck() {
        guard !installing else { return }
        guard isBundled else {
            runInfoAlert(L10n.t("Updates require the app bundle (QRScope.app)",
                                "アップデートはアプリバンドル(QRScope.app)からの実行時のみ利用できます"), info: "")
            return
        }
        Task {
            do {
                guard let release = try await fetchLatest() else {
                    runInfoAlert(L10n.t("No release information found", "リリース情報が見つかりませんでした"), info: "")
                    return
                }
                if Self.isVersion(release.version, newerThan: currentVersion) {
                    availableVersion = release.version
                    promptAndInstall(release, allowSkip: false)
                } else {
                    runInfoAlert(L10n.t("You're up to date", "最新バージョンです"),
                                 info: "QRScope \(currentVersion)")
                }
            } catch {
                runInfoAlert(L10n.t("Update check failed", "アップデートの確認に失敗しました"),
                             info: error.localizedDescription)
            }
        }
    }

    func fetchLatest() async throws -> Release? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let zip = assets.compactMap({ $0["browser_download_url"] as? String })
                .first(where: { $0.hasSuffix(".zip") }),
              let zipURL = URL(string: zip) else { return nil }
        return Release(version: version, zipURL: zipURL)
    }

    /// "1.2.10" 形式の数値比較("v" は除去済み前提)
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - インストール

    private func promptAndInstall(_ release: Release, allowSkip: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.t("QRScope \(release.version) is available",
                                   "QRScope \(release.version) が利用可能です")
        alert.informativeText = L10n.t(
            "Current version: \(currentVersion)\nAfter updating, you'll need to re-grant Screen Recording and other permissions (the app is ad-hoc signed).",
            "現在のバージョン: \(currentVersion)\n更新後は ad-hoc 署名のため、画面収録などの権限を再度許可する必要があります。")
        alert.addButton(withTitle: L10n.t("Update Now", "今すぐ更新"))
        alert.addButton(withTitle: L10n.t("Later", "あとで"))
        if allowSkip {
            alert.addButton(withTitle: L10n.t("Skip This Version", "このバージョンをスキップ"))
        }
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { await install(release) }
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.version, forKey: Self.skippedVersionKey)
        default:
            break
        }
    }

    private func install(_ release: Release) async {
        installing = true
        defer { installing = false }
        do {
            let (tmpZip, _) = try await URLSession.shared.download(from: release.zipURL)
            let newApp = try await Task.detached {
                try Self.extractApp(from: tmpZip)
            }.value
            let dest = Bundle.main.bundleURL
            try Self.swapBundle(newApp: newApp, dest: dest)
            NSLog("QRScope: updated to \(release.version), relaunching")
            relaunch(dest)
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = L10n.t("Update failed", "アップデートに失敗しました")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: L10n.t("Open Releases Page", "リリースページを開く"))
            alert.addButton(withTitle: L10n.t("Close", "閉じる"))
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(Self.releasesPage)
            }
        }
    }

    nonisolated static func extractApp(from zip: URL) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QRScopeUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", zip.path, dir.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "QRScope", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not extract the update archive"])
        }
        guard let app = try FileManager.default
                .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else {
            throw NSError(domain: "QRScope", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "No app bundle in the update archive"])
        }
        return app
    }

    /// 現行バンドルを退避してから新バンドルを配置する(失敗時は元に戻す)
    nonisolated static func swapBundle(newApp: URL, dest: URL) throws {
        let fm = FileManager.default
        let backup = fm.temporaryDirectory
            .appendingPathComponent("QRScope-backup-\(UUID().uuidString).app")
        try fm.moveItem(at: dest, to: backup)
        do {
            try fm.moveItem(at: newApp, to: dest)
            try? fm.removeItem(at: backup)
        } catch {
            try? fm.moveItem(at: backup, to: dest)
            throw error
        }
    }

    private func relaunch(_ appURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", appURL.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    private func runInfoAlert(_ message: String, info: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.runModal()
    }
}
