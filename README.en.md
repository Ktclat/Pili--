# Pili--

An independently maintained, unofficial Bilibili client derived from [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus), focused on **Android**. It retains video and community features and adds QR scanning and an independent application identity so both clients can be installed together.

Development, releases, and support are independently maintained by [Ktclat](https://github.com/Ktclat) in this repository. Pili-- is not a release of the PiliPlus, PiliPala, or PiliPalaX teams and has no affiliation, partnership, or endorsement relationship with those upstream teams. The inherited code remains attributed and licensed as recorded in [NOTICE](NOTICE) and the [source acknowledgements](docs/ACKNOWLEDGEMENTS.md).

[![Android validation build](https://github.com/Ktclat/Pili--/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/Ktclat/Pili--/actions/workflows/build.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

[简体中文](README.md) · [FAQ](docs/FAQ.md) · [Documentation](docs/README.md) · [Changes](CHANGELOG.md) · [Report an issue](https://github.com/Ktclat/Pili--/issues/new/choose)

## Status and downloads

The main branch is at **0.6.3+12** and includes playback, comment, casting and offline cache fixes from PiliPlus 2.2.1. The latest published build is **0.6.0+7**, available as the [v0.6.0-beta.1 prerelease](https://github.com/Ktclat/Pili--/releases/tag/v0.6.0-beta.1) with the floating navigation update. There is no stable release yet. Download the appropriate `test-signed.apk` and verify it against `SHA256SUMS.txt`. Most current Android phones use `arm64-v8a`; `armeabi-v7a` is for compatible 32-bit devices, and `x86_64` is typically for emulators. Minimum Android version: 7.0 (API 24). The release also includes the exact source archive and `BUILD_INFO.json`.

In **Settings → Appearance → Top-right buttons**, choose and reorder the tools for Home and Profile independently. The **⋮** menu appears only when an action is collapsed or the toolbar runs out of space.

Starting with 0.6.3+11, tapping **Download update** on Android checks the stable release metadata against the installed package ID, signing certificate, device ABI and build number. Android rejects an in-place upgrade if the certificates differ. If you choose to replace a test build, export the data you want to keep first. Future stable versions share one download link. [Stable download](https://github.com/Ktclat/Pili--/releases/latest) · [Migration guide (Chinese)](docs/INSTALL.md#旧测试签名迁移)

This prerelease uses an Actions test signing key, not a permanent release key. Test keys can differ between CI runs, so in-place upgrades are not guaranteed. Preserve your data if Android reports a signature conflict. The in-app stable update check ignores prereleases; download this version manually. Development artifacts remain available from successful [Actions runs](https://github.com/Ktclat/Pili--/actions/workflows/build.yml); those artifacts require a GitHub account and expire after 14 days. See [installation](docs/INSTALL.md) and [coexistence](docs/COEXISTENCE.md) for details (Chinese).

## Features

- Upstream video playback, danmaku, search, feeds, live streams, favorites, and offline downloads.
- The Dynamics feed shows the Live and followed creator filters in a horizontal row beneath its categories. The More menu in Mine contains Scan and Recognize links.
- Customizable navigation, showing Home, Dynamics, and Mine by default. Reordering and visibility changes apply immediately.
- A floating capsule bar enabled by default in 0.6.0, with saved opt-outs preserved. Its indicator follows a drag continuously; the page changes only after about 200 ms of stillness. Quick passes and early release cancel the pending change. The appearance switch applies immediately; ordinary taps keep direct navigation. See [floating navigation](docs/FLOATING_NAVIGATION.md) for behavior and validation boundaries.
- In the development build, Mine → More (⋮) → Scan accepts content and login QR codes from the camera or gallery. Web and TV login requests open a native confirmation screen for the current account. Additional security verification remains with the official platform.
- Since 0.6.1, Android apps using Bilibili web or TV QR login can open the confirmation screen directly. Users can also paste the official QR login link on the same phone. [Android integration](docs/INPUT_RECOGNITION.md)
- Receive Android text shares containing Bilibili links, b23.tv links or BV/av identifiers; confirm before opening.
- Optional foreground clipboard recognition, disabled by default, plus a manual paste-and-recognize page. Shared text and login challenges are not uploaded to a project server or persisted.
- Independent Android ID `io.github.ktclat.piliminus`, private data, default download directory, and explicit shortcut targets. Upstream PiliPlus uses `com.example.piliplus`.
- Download resume and completion-race fixes, strict TLS, account destination restrictions, and retries limited to read requests.

Version 0.4.0 removes the mall and creator shop. On startup, obsolete local product favorites, browsing history, and related switches are removed. This cleanup preserves video favorites, playback history, accounts, and download records.

The source snapshot starts a new Git history; the previous history and required upstream attribution remain available as explained in [repository restart](docs/REPOSITORY_RESTART.md).

## Development and validation

Use isolated **Flutter 3.47.9**, **JDK 17**, **Android SDK 37**, and **PowerShell 7**. Follow the [build guide](docs/BUILD.md) to apply the required upstream framework patches and use the committed dependency lockfile. Do not patch a shared Flutter SDK.

CI runs static analysis, regression tests, three ABI builds, and packaged identity/provider/shortcut checks. [Validation records](docs/VALIDATION.md) identify the tested commits and distinguish automated checks, live API requests, and installed APK testing. ARM64 real-device acceptance and long-running device tests remain outstanding. Other platform sources are retained without a validation claim.

Version 0.6.3+11 passed 437 Flutter tests, 31 project script tests and APK identity checks on all three Android architectures. An Android 11 emulator retained settings and customized toolbar buttons when upgrading from build 10 to build 11 with the same test certificate. [CI build](https://github.com/Ktclat/Pili--/actions/runs/45558391018) · [0.6.3+11 test APKs](https://github.com/Ktclat/Pili--/actions/runs/45558391018/artifacts/14998000754) · [Device results](docs/VALIDATION.md)

See [contributing](CONTRIBUTING.md), the [roadmap](docs/ROADMAP.md), and [security reporting](SECURITY.md). The project is not an official Bilibili product.

## License

The upstream [GPL v3 license](LICENSE), copyright notices, and required source attribution are retained. [NOTICE](NOTICE) records the source and modifications; dependencies retain their own licenses. Changes to repository history or contribution statistics do not change these attribution or licensing obligations. Distribute corresponding source and build materials as required by the license. See [acknowledgements](docs/ACKNOWLEDGEMENTS.md) for upstream sources, dependencies, and retained assets; that page is not a list of Pili-- maintainers. The inherited logo does not imply official endorsement. The project does not bypass paid-content or membership access controls.
