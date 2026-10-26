# Pili--

An Android-focused, unofficial Bilibili client derived from [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus). See the [Chinese README](README.md) for build instructions.

Changes include camera/gallery QR scanning with confirmation, an opt-in official mall H5 page, strict TLS, account destination restrictions, removal of private-storage export and hidden URL entry, WebView cache reuse, and retries limited to read requests.

The mall downloads official web resources on first activation; it is not a native plugin. Payment and account-specific flows require real-device validation. Other platform sources are retained without a validation claim.

Use isolated Flutter 3.47.8 and `scripts/prepare_android.ps1`. APKs built without a release keystore use a test signature. See [validation](docs/VALIDATION.md), [security scope](SECURITY.md), [source notices](NOTICE), and the unchanged upstream [GPL v3 license](LICENSE). Original notices and dependency licenses are retained.
