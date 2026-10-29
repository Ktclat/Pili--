# Pili--

An independently maintained, unofficial Bilibili client derived from [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus), focused on **Android**. It retains video and community features and adds QR scanning and an independent application identity so both clients can be installed together.

[![Android validation build](https://github.com/Ktclat/Pili--/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/Ktclat/Pili--/actions/workflows/build.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

[简体中文](README.md) · [FAQ](docs/FAQ.md) · [Documentation](docs/README.md) · [Changes](CHANGELOG.md) · [Report an issue](https://github.com/Ktclat/Pili--/issues/new/choose)

## Status and downloads

The current development version is **0.4.0+5**. No formal Release has been published. Download the `Pili--Android-test-signed` artifact from a successful [Actions run](https://github.com/Ktclat/Pili--/actions/workflows/build.yml) for the desired branch and commit, then unzip it and choose the appropriate APK. Most current Android phones use `arm64-v8a`; `armeabi-v7a` is for compatible 32-bit devices, and `x86_64` is typically for emulators. Minimum Android version: 7.0 (API 24).

Artifact downloads require a GitHub account and expire after 14 days. Test signing keys can differ between CI runs, so these APKs may not support in-place upgrades. Preserve your data if Android reports a signature conflict. See [installation](docs/INSTALL.md) and [coexistence](docs/COEXISTENCE.md) for details (Chinese).

## Features

- Upstream video playback, danmaku, search, feeds, live streams, favorites, and offline downloads.
- Customizable navigation, showing Home, Dynamics, and Mine by default. Reordering and visibility changes apply immediately.
- Camera/gallery QR scanning with a result confirmation step, support for BV/av identifiers, and camera lifecycle handling.
- Independent Android ID `io.github.ktclat.piliminus`, private data, default download directory, and explicit shortcut targets. Upstream PiliPlus uses `com.example.piliplus`.
- Download resume and completion-race fixes, strict TLS, account destination restrictions, and retries limited to read requests.

Version 0.4.0 removes the mall and creator shop. On startup, obsolete local product favorites, browsing history, and related switches are removed. This cleanup preserves video favorites, playback history, accounts, and download records.

## Development and validation

Use isolated **Flutter 3.47.8**, **JDK 17**, **Android SDK 37**, and **PowerShell 7**. Follow the [build guide](docs/BUILD.md) to apply the required upstream framework patches and use the committed dependency lockfile. Do not patch a shared Flutter SDK.

CI runs static analysis, regression tests, three ABI builds, and packaged identity/provider/shortcut checks. [Validation records](docs/VALIDATION.md) identify the tested commits and distinguish automated checks, live API requests, and installed APK testing. ARM64 real-device acceptance and long-running device tests remain outstanding. Other platform sources are retained without a validation claim.

See [contributing](CONTRIBUTING.md), the [roadmap](docs/ROADMAP.md), and [security reporting](SECURITY.md). The project is not an official Bilibili product.

## License

The upstream [GPL v3 license](LICENSE), copyright notices, and Git history are retained. [NOTICE](NOTICE) records the source and modifications; dependencies retain their own licenses. Distribute corresponding source and build materials as required by the license. See [acknowledgements](docs/ACKNOWLEDGEMENTS.md) for upstream projects, contributors, dependencies, and retained assets. The inherited logo does not imply official endorsement. The project does not bypass paid-content or membership access controls.
