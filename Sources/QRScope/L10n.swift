import Foundation

/// システム言語に応じて英語/日本語を切り替える最小ローカライズヘルパー。
/// アプリバンドルを手組みしている(SPM リソースバンドルを同梱しない)ため、
/// .lproj ではなくコード内辞書方式を採用している。
enum L10n {
    static let isJapanese: Bool =
        Locale.preferredLanguages.first?.hasPrefix("ja") ?? false

    /// 英語と日本語のペアから現在の言語の文字列を返す
    static func t(_ en: String, _ ja: String) -> String {
        isJapanese ? ja : en
    }
}
