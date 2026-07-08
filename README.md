# QRScope

**Right-click any QR code on your screen and open it with one click.**

QRScope is a macOS menu bar app. Right-click on a QR code — in a web page, PDF, photo, video call, anything visible on screen — and a small chip appears next to your cursor with an **Open** button.

[日本語のREADMEはこちら](README.ja.md)

![Demo](docs/demo.gif)

## Features

- ⚡ **Fast** — Swift + Apple Vision framework (hardware-accelerated). Detection completes in tens of milliseconds after a right-click
- 🔋 **Efficient** — no constant polling. It captures only a small region around the cursor at the moment you right-click, so background load is essentially zero
- 🖱️ **Intuitive** — no need to open an app or take screenshots. Just right-click on a QR code
- 📜 **History** — everything you open or copy is saved (searchable, deletable)
- 🎨 **QR generator** — foreground/background colors, transparent background, module styles (square / rounded / dots), error correction level, size; export as PNG or copy
- 🌐 **Localized** — English and Japanese, following your system language
- 🔍 Also detects Aztec and DataMatrix codes

## Screenshots

| QR Generator | Scan History |
|:---:|:---:|
| ![Generator](docs/generator.png) | ![History](docs/history.png) |

## Installation

Requirements: macOS 14 (Sonoma) or later.

### Homebrew (recommended)

```bash
brew tap towanaruto/tap
brew trust towanaruto/tap   # Homebrew 6+
brew install --cask qrscope
xattr -d com.apple.quarantine /Applications/QRScope.app
```

The `xattr` step is needed because the app is ad-hoc signed (not notarized) and Gatekeeper would block it otherwise. Then launch QRScope from Applications.

### Build from source

Requires Xcode Command Line Tools.

```bash
git clone https://github.com/towanaruto/QRScope.git
cd QRScope
./Scripts/build-app.sh
open build/QRScope.app
```

### Grant permission

On first launch, macOS asks for **Screen Recording** permission (required for detection):

1. Open **System Settings → Privacy & Security → Screen Recording**
2. Enable **QRScope**
3. Restart QRScope

> **Note**: The build is ad-hoc signed, so rebuilding invalidates the permission — re-grant it after each rebuild (remove and re-add the entry if the toggle doesn't stick).

## Usage

| Action | Result |
|--------|--------|
| Right-click on a QR code | A chip appears next to the cursor → **Open** launches the link, 📋 copies the content |
| Menu bar → Scan Entire Screen | Detects all QR codes on every display at once |
| Menu bar → Scan History… | Searchable list of everything you've opened or copied |
| Menu bar → Generate QR Code… | Styled QR generation with PNG export |
| Menu bar → Launch at Login | Registers as a login item |

The chip dismisses automatically when you click elsewhere or after 12 seconds.

For safety, **Open** is enabled only for `http(s)`, `mailto`, `tel`, `sms`, `facetime`, and `maps` schemes. Other payloads (Wi-Fi credentials, contacts, etc.) can be retrieved via copy.

## How it works

```
Right-click (global NSEvent monitor — no accessibility permission needed)
  → Capture region around cursor (ScreenCaptureKit / SCScreenshotManager)
  → Detect barcodes (Vision / VNDetectBarcodesRequest, off the main thread)
  → Show a chip next to the cursor (non-activating NSPanel — never steals focus)
  → Open / Copy → saved to history (~/Library/Application Support/QRScope/history.json)
```

| File | Role |
|------|------|
| `AppDelegate.swift` | Wiring and the detection flow |
| `RightClickMonitor.swift` | Global right-click monitoring |
| `ScreenCapturer.swift` | ScreenCaptureKit capture (excludes own windows, caches display info) |
| `QRDetector.swift` | Vision barcode detection |
| `OverlayController/View.swift` | Floating chip next to the cursor |
| `HistoryStore/View.swift` | History persistence and UI |
| `QRCodeRenderer.swift` | Styled QR renderer (CoreImage matrix → CoreGraphics drawing) |
| `GeneratorView.swift` | QR generator UI |
| `L10n.swift` | English/Japanese localization |
| `SelfTest.swift` | Generate→detect roundtrip verification |

## Development

```bash
swift build                        # debug build
.build/debug/QRScope --selftest    # verify generate→detect roundtrip for all styles
```

## License

[MIT](LICENSE)
