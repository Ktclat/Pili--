# Pili--

An independently maintained, unofficial Bilibili client derived from [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus), focused on **Android**. It adds a native mall, QR scanning, and an independent application identity so both clients can be installed together.

[![Android validation build](https://github.com/Ktclat/Pili--/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/Ktclat/Pili--/actions/workflows/build.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

[简体中文](README.md) · [FAQ](docs/FAQ.md) · [Documentation](docs/README.md) · [Changes](CHANGELOG.md) · [Report an issue](https://github.com/Ktclat/Pili--/issues/new/choose)

## Status and downloads

The current development version is **0.3.0+4**. No formal Release has been published. Download the `Pili--Android-test-signed` artifact from a successful [Actions run](https://github.com/Ktclat/Pili--/actions/workflows/build.yml) for the desired branch and commit, then unzip it and choose the appropriate APK. Most current Android phones use `arm64-v8a`; `armeabi-v7a` is for compatible 32-bit devices, and `x86_64` is typically for emulators. Minimum Android version: 7.0 (API 24).

Artifact downloads require a GitHub account and expire after 14 days. Test signing keys can differ between CI runs, so these APKs may not support in-place upgrades. Preserve your data if Android reports a signature conflict. See [installation](docs/INSTALL.md) and [coexistence](docs/COEXISTENCE.md) for details (Chinese).

## Features

- Upstream video playback, danmaku, search, feeds, live streams, favorites, and offline downloads.
- A built-in Flutter mall: recommendations, categories, search, product details, zoomable galleries, ordered text/images, and further product search from the detail page. Search supports relevance, sales, newest, ascending/descending price, and optional price bounds.
- Local product favorites and browsing history with persistent snapshots, individual removal, clear actions, and a pause switch for history. They stay on this device and do not sync with a Bilibili account. Opening an item fetches fresh details; stored prices may be outdated.
- Share or copy a product’s official link from its native detail page, preserving special-product destinations.
- The mall appears in navigation by default. Toggle **Settings → Appearance → Show mall in navigation** (`在导航栏显示会员购`); changes apply immediately. The entry under “Mine” remains available.
- Camera/gallery QR scanning with a result confirmation step, support for BV/av identifiers, and camera lifecycle handling.
- Independent Android ID `io.github.ktclat.piliminus`, private data, default download directory, and explicit shortcut targets. Upstream PiliPlus uses `com.example.piliplus`.
- Download resume and completion-race fixes, strict TLS, account destination restrictions, and retries limited to read requests.

Mall browsing uses public official APIs without account cookies. Product prices and preorder deposits are distinguished. **Product options, checkout, orders, and payments remain on the official platform.** Public APIs may change; final stock and prices are determined there. See the [native mall scope and research](docs/NATIVE_MALL.md).

## Preview

Flutter test previews rendered from captured official responses, including sample local favorites. See [sources and validation scope](docs/images/README.md). Deposits and discounted display prices can differ from the product-price filter.

<p>
  <img src="docs/images/mall-search.png" width="280" alt="Native mall sorting and price filter">
  <img src="docs/images/mall-library.png" width="280" alt="Local product favorites and browsing history">
</p>

## Development and validation

Use isolated **Flutter 3.47.8**, **JDK 17**, **Android SDK 37**, and **PowerShell 7**. Follow the [build guide](docs/BUILD.md) to apply the required upstream framework patches and use the committed dependency lockfile. Do not patch a shared Flutter SDK.

CI runs static analysis, regression tests, three ABI builds, and packaged identity/provider/shortcut checks. [Validation records](docs/VALIDATION.md) identify the tested commits and distinguish automated checks, live API requests, and installed APK testing. Installed-APK live mall browsing and ARM64 real-device acceptance remain outstanding. Other platform sources are retained without a validation claim.

See [contributing](CONTRIBUTING.md), the [roadmap](docs/ROADMAP.md), and [security reporting](SECURITY.md). The project is not an official Bilibili product.

## License

The upstream [GPL v3 license](LICENSE), copyright notices, and Git history are retained. [NOTICE](NOTICE) records the source and modifications; dependencies retain their own licenses. Distribute corresponding source and build materials as required by the license. See [acknowledgements](docs/ACKNOWLEDGEMENTS.md) for upstream projects, contributors, dependencies, and retained assets. The inherited logo does not imply official endorsement. The project does not bypass paid-content or membership access controls.
