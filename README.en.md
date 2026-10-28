# Pili--

An Android-focused, unofficial Bilibili client derived from [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus). See the [Chinese README](README.md) for build instructions.

Changes include camera/gallery QR scanning with confirmation, a built-in native mall, strict TLS, account destination restrictions, removal of private-storage export and hidden URL entry, WebView cache reuse, and retries limited to read requests.

The mall uses Flutter widgets for browsing, categories, search, and product details backed by public official APIs. Its navigation entry is visible by default and can be hidden in appearance settings without uninstalling the feature. Checkout opens the official platform; this client does not submit orders or payments. See the [native mall scope](docs/NATIVE_MALL.md). Other platform sources are retained without a validation claim.

Use isolated Flutter 3.47.8 and `scripts/prepare_android.ps1`. APKs built without a release keystore use a test signature. See [validation](docs/VALIDATION.md), [security scope](SECURITY.md), [source notices](NOTICE), and the unchanged upstream [GPL v3 license](LICENSE). Original notices and dependency licenses are retained.
