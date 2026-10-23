# 1.0.13 free / RootHide validation

- Activation screen, license client, signed receipts, renewal/expiry checks and daemon/widget/SpringBoard entitlement gates removed.
- No protected UniqueDeviceID entitlement remains. App, daemon and widgets no longer collect a device ID for purchase activation.
- Separate local Rootless (`iphoneos-arm64`, `/var/jb` archive prefix) and RootHide (`iphoneos-arm64e`, no `/var/jb` archive prefix) builds completed. RootHide binaries link the RootHide runtime and use its bootstrap path API.
- All five binaries per variant passed arm64e metadata and code-signature verification. Package structure, plist versions and maintainer permissions passed.
- Packaged data contains no VXLicense, LicenseStore, LicenseWidgetGate, activation endpoint, UniqueDeviceID, license expiry or old feature-entitlement markers.
- Nine release tests and installer migration fixture passed. German/English translations regenerated.
- Git history and release assets were checked for credentials/private data. Personal commit emails were replaced with GitHub noreply addresses; a private local backup was retained outside the repository.

Device testing of 1.0.13 remains pending, including RootHide installation, widgets, respring and cold jailbreak entry. This is not evidence of full iOS 16–26 compatibility. The previously unsuccessful XR charging-pause/bypass tests remain a known limitation.
