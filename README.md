# QRScope

画面上のQRコードを**右クリック+ボタンひとつ**で開ける macOS メニューバーアプリ。

Webページ・PDF・写真アプリなど、**画面に映っているものすべて**が対象です。QRコードの上で右クリックすると、カーソルのすぐ横に「開く」ボタン付きのチップが表示されます。

## 特徴

- ⚡ **高速**: Swift + Apple Vision フレームワーク(ハードウェア支援)による検出。右クリックからチップ表示まで数十ミリ秒
- 🔋 **省電力**: 常時ポーリングではなく右クリックの瞬間だけカーソル周辺(680pt四方)をキャプチャして検出するため、バックグラウンド負荷ほぼゼロ
- 🖱️ **直感的**: アプリを起動して読み取り操作をする必要なし。QRの上で右クリック → 「開く」を押すだけ
- 📜 **履歴**: 開いた/コピーしたQRの内容を自動保存(検索・削除対応)
- 🎨 **QR生成**: 前景色・背景色・透明背景・スタイル(スクエア/角丸/ドット)・誤り訂正レベル・サイズを指定してPNG保存/コピー
- 🔍 QRのほか Aztec / DataMatrix コードにも対応

## ビルドと起動

```bash
./Scripts/build-app.sh
open build/QRScope.app
```

初回起動時に**画面収録の許可**を求められます(検出に必須)。
「システム設定 → プライバシーとセキュリティ → 画面収録とシステムオーディオ録音」で QRScope を有効にし、アプリを再起動してください。

> **Note**: ad-hoc 署名のため、再ビルドすると画面収録の許可の再付与が必要になる場合があります。

## 使い方

| 操作 | 動作 |
|------|------|
| QRコードの上で右クリック | カーソル横にチップ表示 → 「開く」でブラウザ起動、📋 でコピー |
| メニューバー → 画面全体をスキャン | 表示中の全ディスプレイからQRを一括検出 |
| メニューバー → 読み取り履歴… | 過去に開いた/コピーした内容の一覧(検索可) |
| メニューバー → QRコードを生成… | スタイル指定つきQR生成・PNG書き出し |
| メニューバー → ログイン時に自動起動 | ログイン項目に登録 |

チップは他の場所をクリックするか12秒経つと自動で消えます。

安全のため「開く」が有効になるのは `http(s)` `mailto` `tel` `sms` `facetime` `maps` スキームのみです。それ以外の内容(Wi-Fi設定・連絡先など)はコピーで取得できます。

## 開発

```bash
swift build            # デバッグビルド
.build/debug/QRScope --selftest   # 生成→検出のラウンドトリップ検証
```

### アーキテクチャ

```
右クリック(NSEventグローバル監視 ※権限不要)
  → カーソル周辺をキャプチャ(ScreenCaptureKit / SCScreenshotManager)
  → QR検出(Vision / VNDetectBarcodesRequest ※バックグラウンドスレッド)
  → カーソル横にチップ表示(非アクティブ化NSPanel ※フォーカスを奪わない)
  → 開く/コピー → 履歴保存(~/Library/Application Support/QRScope/history.json)
```

| ファイル | 役割 |
|---------|------|
| `AppDelegate.swift` | 全体の配線・検出フロー |
| `RightClickMonitor.swift` | 右クリックのグローバル監視 |
| `ScreenCapturer.swift` | ScreenCaptureKit によるキャプチャ(自アプリ除外・ディスプレイ構成キャッシュ) |
| `QRDetector.swift` | Vision によるバーコード検出 |
| `OverlayController/View.swift` | カーソル横のフローティングチップ |
| `HistoryStore/View.swift` | 履歴の永続化とUI |
| `QRCodeRenderer.swift` | スタイル対応QRレンダラー(CoreImage で行列取得→CoreGraphics で描画) |
| `GeneratorView.swift` | QR生成UI |
| `SelfTest.swift` | 全スタイルの生成→検出検証 |
