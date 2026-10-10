# Simpanin

Simpanin is a privacy-first iOS app for keeping personal documents such as KTP, SIM, STNK and passport. Every document is encrypted on the device with AES-256-GCM under a key that only Face ID or the device passcode can release, and expiry reminders are computed and scheduled locally. Nothing leaves the phone unless you turn on the optional encrypted backup.

## Privacy

- No network calls, except the optional encrypted backup you turn on yourself.
- No analytics, no crash reporting, no third-party SDKs. The only dependency is Apple's [swift-crypto](https://github.com/apple/swift-crypto).
- Real document scans are never part of this repository; tests use synthetic data only.

## Development

Read [CONTRIBUTING.md](CONTRIBUTING.md) first. It covers setup, the privacy rules and code style.

Run the core tests on a Mac (no simulator needed):

```sh
cd Packages/VaultCore && swift test
```

Build the app:

```sh
xcodebuild -project Simpanin.xcodeproj -scheme Simpanin -destination 'generic/platform=iOS Simulator' build
```

## License

The code is licensed under the Mozilla Public License 2.0 (MPL-2.0); see [LICENSE](LICENSE).

## Trademarks

The Simpanin name and icon are not licensed under MPL-2.0 and may not be used for derived apps.
