# Pili--

An independently maintained, unofficial Bilibili client derived from [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus), focused on **Android**. It retains video and community features and adds QR scanning and an independent application identity so both clients can be installed together.

Development, releases, and support are independently maintained by [Ktclat](https://github.com/Ktclat) in this repository. Pili-- is not a release of the PiliPlus, PiliPala, or PiliPalaX teams and has no affiliation, partnership, or endorsement relationship with those upstream teams. The inherited code remains attributed and licensed as recorded in [NOTICE](NOTICE) and the [source acknowledgements](docs/ACKNOWLEDGEMENTS.md).

[![Android validation build](https://github.com/Ktclat/Pili--/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/Ktclat/Pili--/actions/workflows/build.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

[简体中文](README.md) · [FAQ](docs/FAQ.md) · [Documentation](docs/README.md) · [Changes](CHANGELOG.md) · [Report an issue](https://github.com/Ktclat/Pili--/issues/new/choose)

## Status and downloads

The current development version is **0.5.0+6**. No formal Release has been published. Download the `Pili--Android-test-signed` artifact from a successful [Actions run](https://github.com/Ktclat/Pili--/actions/workflows/build.yml) for the desired branch and commit, then unzip it and choose the appropriate APK. Most current Android phones use `arm64-v8a`; `armeabi-v7a` is for compatible 32-bit devices, and `x86_64` is typically for emulators. Minimum Android version: 7.0 (API 24).

Artifact downloads require a GitHub account and expire after 14 days. Test signing keys can differ between CI runs, so these APKs may not support in-place upgrades. Preserve your data if Android reports a signature conflict. See [installation](docs/INSTALL.md) and [coexistence](docs/COEXISTENCE.md) for details (Chinese).

## Features

- Upstream video playback, danmaku, search, feeds, live streams, favorites, and offline downloads.
- Customizable navigation, showing Home, Dynamics, and Mine by default. Reordering and visibility changes apply immediately.
- Camera/gallery scanning and native confirmation of web/TV login authorization with the current account. Additional security verification remains with the official platform.
- Receive Android text shares containing Bilibili links, b23.tv links or BV/av identifiers; confirm before opening.
- Optional foreground clipboard recognition, disabled by default, plus a manual paste-and-recognize page. Shared text and login challenges are not uploaded to a project server or persisted.
- Independent Android ID `io.github.ktclat.piliminus`, private data, default download directory, and explicit shortcut targets. Upstream PiliPlus uses `com.example.piliplus`.
- Download resume and completion-race fixes, strict TLS, account destination restrictions, and retries limited to read requests.

Version 0.4.0 removes the mall and creator shop. On startup, obsolete local product favorites, browsing history, and related switches are removed. This cleanup preserves video favorites, playback history, accounts, and download records.

The source snapshot starts a new Git history; the previous history and required upstream attribution remain available as explained in [repository restart](docs/REPOSITORY_RESTART.md).

## Development and validation

Use isolated **Flutter 3.47.8**, **JDK 17**, **Android SDK 37**, and **PowerShell 7**. Follow the [build guide](docs/BUILD.md) to apply the required upstream framework patches and use the committed dependency lockfile. Do not patch a shared Flutter SDK.

CI runs static analysis, regression tests, three ABI builds, and packaged identity/provider/shortcut checks. [Validation records](docs/VALIDATION.md) identify the tested commits and distinguish automated checks, live API requests, and installed APK testing. ARM64 real-device acceptance and long-running device tests remain outstanding. Other platform sources are retained without a validation claim.

The 0.5.0 root snapshot passed [Actions #25](https://github.com/Ktclat/Pili--/actions/runs/40985731174), including all three ABI builds, 278 Flutter tests and 10 Python checks. [Emulator evidence](docs/validation/0.5.0.md) covers share reception, manual recognition and privacy switches. Real-account web/TV QR authorization has not been exercised.

See [contributing](CONTRIBUTING.md), the [roadmap](docs/ROADMAP.md), and [security reporting](SECURITY.md). The project is not an official Bilibili product.

## License

The upstream [GPL v3 license](LICENSE), copyright notices, and required source attribution are retained. [NOTICE](NOTICE) records the source and modifications; dependencies retain their own licenses. Changes to repository history or contribution statistics do not change these attribution or licensing obligations. Distribute corresponding source and build materials as required by the license. See [acknowledgements](docs/ACKNOWLEDGEMENTS.md) for upstream sources, dependencies, and retained assets; that page is not a list of Pili-- maintainers. The inherited logo does not imply official endorsement. The project does not bypass paid-content or membership access controls.
