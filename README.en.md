# Pili--

An independently maintained, unofficial Bilibili client derived from [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus), focused on **Android**. It retains video and community features and adds QR scanning and an independent application identity so both clients can be installed together.

[Ktclat](https://github.com/Ktclat) handles development, releases, and support independently of the PiliPlus, PiliPala, and PiliPalaX teams. Upstream licenses and attribution are recorded in [NOTICE](NOTICE) and the [source acknowledgements](docs/ACKNOWLEDGEMENTS.md).

[![Android validation build](https://github.com/Ktclat/Pili--/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/Ktclat/Pili--/actions/workflows/build.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

[简体中文](README.md) · [FAQ](docs/FAQ.md) · [Documentation](docs/README.md) · [Changes](CHANGELOG.md) · [Report an issue](https://github.com/Ktclat/Pili--/issues/new/choose)

## Status and downloads

The main branch is at **0.6.3+13** and includes playback, comment, casting and offline cache fixes from PiliPlus 2.2.1. The latest published build, **0.6.0+7**, is an Android prerelease with the floating navigation update. It requires Android 7.0 (API 24) or later. Most phones use the `arm64-v8a` APK. The release also provides 32-bit ARM and x86_64 APKs, checksums, the corresponding source archive, and build information. [Prerelease downloads](https://github.com/Ktclat/Pili--/releases/tag/v0.6.0-beta.1)

In **Settings → Appearance → Top-right buttons**, choose and reorder the tools for Home and Mine separately. Only checked tools appear in the toolbar. The Home search field adapts to the space available.

Starting with 0.6.3+11, tapping **Download update** on Android checks the stable release metadata against the installed package ID, signing certificate, device ABI and build number. Android rejects an in-place upgrade if the certificates differ. If you choose to replace a test build, export the data you want to keep first. Future stable versions share one download link. [Stable download](https://github.com/Ktclat/Pili--/releases/latest) · [Migration guide (Chinese)](docs/INSTALL.md#旧测试签名迁移)

Download prereleases manually. Test builds from different runs may use different signing keys. Development APKs are available for 14 days and require a GitHub account to download. [Actions builds](https://github.com/Ktclat/Pili--/actions/workflows/build.yml) · [Installation](docs/INSTALL.md) · [Coexistence](docs/COEXISTENCE.md)

## Features

- Upstream video playback, danmaku, search, feeds, live streams, favorites, and offline downloads.
- The Dynamics feed shows the Live and followed creator filters in a horizontal row beneath its categories.
- Customizable navigation, showing Home, Dynamics, and Mine by default. Reordering and visibility changes apply immediately.
- A floating capsule bar enabled by default in 0.6.0, with saved opt-outs preserved. Its indicator follows a drag continuously; the page changes only after about 200 ms of stillness. Quick passes and early release cancel the pending change. The appearance switch applies immediately; ordinary taps keep direct navigation. See [floating navigation](docs/FLOATING_NAVIGATION.md) for behavior and validation boundaries.
- Home and Mine show **Scan** by default. Use the camera or gallery to scan content and login QR codes. For web and TV logins, review the account and request before confirming.
- Since 0.6.1, Android apps using Bilibili web or TV QR login can open the confirmation screen directly. Users can also paste the official QR login link on the same phone. [Android integration](docs/INPUT_RECOGNITION.md)
- Tap the link icon at the top right of **Scan** to recognize Bilibili links, b23.tv links or BV/av identifiers. You can also send text to Pili-- from the Android share sheet.
- Optional foreground clipboard recognition, disabled by default, plus a manual paste-and-recognize page. Shared text and login challenges are not uploaded to a project server or persisted.
- Independent Android ID `io.github.ktclat.piliminus`, private data, default download directory, and explicit shortcut targets. Upstream PiliPlus uses `com.example.piliplus`.
- Download resume and completion-race fixes, strict TLS, account destination restrictions, and retries limited to read requests.

Version 0.4.0 removes the mall and creator shop. On startup, obsolete local product favorites, browsing history, and related switches are removed. This cleanup preserves video favorites, playback history, accounts, and download records.

The source snapshot starts a new Git history; the previous history and required upstream attribution remain available as explained in [repository restart](docs/REPOSITORY_RESTART.md).

## Development and validation

Use isolated **Flutter 3.47.9**, **JDK 17**, **Android SDK 37**, and **PowerShell 7**. Follow the [build guide](docs/BUILD.md) to apply the required upstream framework patches and use the committed dependency lockfile. Do not patch a shared Flutter SDK.

CI runs static analysis, regression tests and builds for three Android architectures. It checks the application ID, providers and launcher shortcuts in the compiled APKs. Device results are recorded by version. [Validation records](docs/VALIDATION.md)

Version 0.6.3+12 passed 439 Flutter tests, 31 project script tests and APK identity checks on all three Android architectures. An Android 11 emulator retained the customized toolbar layout when upgrading from build 11 to build 12 with the same test certificate. [0.6.3+12 test APKs](https://github.com/Ktclat/Pili--/actions/runs/45592612772/artifacts/15011943766) · [CI build](https://github.com/Ktclat/Pili--/actions/runs/45592612772) · [Device results](docs/VALIDATION.md)

See [contributing](CONTRIBUTING.md), the [roadmap](docs/ROADMAP.md), and [security reporting](SECURITY.md).

## License

Pili-- retains the upstream GPL v3 license, copyright notices and attribution. When distributing modified builds, include the corresponding source and build materials as required by the license. Dependencies retain their own licenses. [License](LICENSE) · [Source and modifications](NOTICE) · [Dependencies and assets](docs/ACKNOWLEDGEMENTS.md)
