# MyLittleEnergy

Free battery insights, charging tools and custom displays for compatible jailbroken devices. No Havoc account, purchase activation, device-identifier collection for licensing or license server is required.

Source and downloads: https://github.com/xsxs18-dev/mylittleenergy

Version 1.0.13 provides separate **rootless** (`iphoneos-arm64`) and **RootHide** (`iphoneos-arm64e`) packages. Install the variant matching your jailbreak. RootHide uses its own Theos scheme and randomized bootstrap paths; it is not a renamed rootless DEB. Both variants require device testing. The intended range is iOS 16–26, not a claim of verified support on every version.

**Known limitation:** charging pause and charger bypass both reported unsuccessful tests on the user's iPhone XR / iOS 18.4 setup. These controls depend on battery-driver support. A successful build does not fix or validate them.

## Features

**App**
- Overview with an animated ring, live power, time to full/empty, charger name and watts
- Cards for health, temperature, power, cycles, capacity, charge, voltage and current with live sparklines
- Every battery value in detail: capacity (current, full, nominal, design, lost), electrical values, charger details, cell voltages and Qmax, lifetime extremes, power telemetry
- Raw registry browser with search and copy as JSON
- History graphs for 24 hours, 7, 30 and 90 days: level (with charging periods), temperature, power, health over time
- Drain per hour, how long a full battery lasts, average temperature, time plugged in
- Charging sessions with energy, average and peak power, highest temperature, charger and time held by the limit
- CSV export, configurable sample interval and history length
- English and German, accent colors, °C/°F, Liquid Glass on iOS 26

**Charge limit**
- Stop charging at any level from 50 to 100 %, start again at a lower level
- Two modes: pause charging (charger powers the device) or run on battery (charger bypassed)
- Heat protection: pauses charging above a temperature
- Full charge schedule: lifts the limit before you get up
- Charge to 100 % once, until you unplug
- Self test that checks both ways of stopping the charger

**Look**
- Status bar: power, temperature, percentage, time remaining, charger watts or health under, next to or instead of the time, in every app, live
- Battery icon colors: custom color, color by level, custom charging color, red threshold
- Live HUD: draggable floating readout above every app, compact or large
- Lock screen charging animation in three styles (ring, wave, pulse), can hide the iOS one

**React**
- Level alerts (drops to / charges to), fully charged, charge limit reached, battery hot
- Banners, any system sound, spoken alerts, sounds when plugging in and unplugging
- Automation rules: battery level, charger connected or disconnected, temperature, fully charged → Low Power Mode, Wi-Fi, Bluetooth, brightness, Dark Mode, Airplane Mode, Location Services
- Keep Low Power Mode on above 80 %

**Everywhere**
- Home Screen widgets (battery, 24 hour chart, health) and Lock Screen widgets
- Control Center toggle for the charge limit (needs CCSupport)
- `mylittleenergy://full`, `mylittleenergy://limit/on`, `mylittleenergy://limit/off` for Shortcuts

## Parts

| Part | Where | What |
| --- | --- | --- |
| `Daemon/` | `/var/jb/usr/libexec/mylittleenergyd` (launchd, root) | Samples the battery, holds the limit, writes history, sends events |
| `Tweak/` | every app + SpringBoard | Status bar, battery icon; in SpringBoard banners, sounds, HUD, animation, automation |
| `App/` | `/var/jb/Applications/MyLittleEnergy.app` | SwiftUI app |
| `Widgets/` | `MyLittleEnergy.app/PlugIns/MyLittleEnergyWidgets.appex` | WidgetKit extension |
| `CCModule/` | `/var/jb/Library/ControlCenter/Bundles` | CCSupport toggle |

Data lives in `/var/mobile/Library/MyLittleEnergy`.

## Build

- **GitHub Actions** (`.github/workflows/build.yml`): newest Xcode on macOS, Theos, `make package`. Builds run locally by default. CI runs only when manually started; a successful manual build publishes a prerelease. Built with the iOS 26 SDK, so the app gets Liquid Glass on iOS 26.
- **Local on Linux** (`scripts/build-local.sh`): the arm64e parts (tweak, CC module) are compiled with the official LLVM 21+ (`~/llvm-23`) and linked with `~/theos`, the Swift parts use `~/theos-swift` (Theos + kabiroberai's swift-5.8 Linux toolchain + iOS 16.5 SDK), the daemon is arm64 only. Writes `packages/com.xsxs18.mylittleenergy_<version>_iphoneos-arm64.deb`. iOS 16.5 SDK means no Liquid Glass look on iOS 26.
  - iOS 18 kills every arm64e process that loads Objective-C classes without signed metadata (`EXC_BREAKPOINT` in `readClass`). clang older than 21 (e.g. the L1ghtmann Linux toolchain) can't sign them. The script refuses to package such binaries (`scripts/check_arm64e.py`), sets the `SignedClassRO` image flag like Xcode does (`scripts/mark_signed_class_ro.py`) and checks every code signature page (`scripts/verify_signature.py`).

`python3 scripts/strings.py .` regenerates the translations (fails if German is missing),
`python3 scripts/make_icon.py App/Resources` redraws the app icon.

## SpringBoard recovery and validation

Integration now starts four seconds after SpringBoard announces launch. A fuse at
`/var/mobile/Library/MyLittleEnergy/springboard-launch` remains armed until another 30 seconds
of main-queue progress. If initialization is interrupted, later starts skip MyLittleEnergy's
SpringBoard hooks until you explicitly retry in **Settings → Diagnostics**. This
protects the initialization window; it cannot prevent later crashes or failures in
other tweaks. MyLittleEnergy never kills SpringBoard itself.

If the old package prevents a usable jailbroken session, use your jailbreak's option
to start with tweak injection disabled, then remove the old MyLittleEnergy package before
installing the candidate. The exact recovery steps depend on the jailbreak.

Before retrying a failed initialization, install the fixed package. Keep the fuse
armed until you are ready, then use Diagnostics and respring manually. An interrupted
or intentional respring during the initialization window can also arm this protection.
The daemon and app remain separate from this SpringBoard fuse.

Validation needed before a Havoc submission:
- Physical device cold jailbreak entry, respring, lock/unlock and charge/unplug.
- Each supported device/iOS/jailbreak combination, with crash/watchdog logs.
- Status-bar modes and icon colors, including disabling them and conflicts with other tweaks.
- Charge limit, resume, heat pause, daemon restart/removal and charging restoration.
- Widgets, CCSupport module, automation, alerts and accessibility.

No iOS device validation has been completed in this checkout. Successful compilation
alone does not establish that the reported freeze or bootloop is resolved.

### Build verification for 1.0.3

The full Linux build completed successfully (daemon, tweak and CC module: arm64 +
arm64e; app and widgets: arm64). Property-list, localization, shell-syntax and package
checks passed. Packaged Mach-O executables contain code-signature load commands;
this is not a device signature acceptance test. The Linux app was built against the
iOS 16.5 SDK. GitHub's macOS build was blocked before starting by account billing or
spending-limit settings. The iOS 26 SDK build and physical-device tests remain pending.

`python3 scripts/check_package.py packages/<package>.deb` checks required binaries,
rootless paths, plist/version consistency and maintainer-script permissions.

## Automatic build releases

Every successful `scripts/build-local.sh` run first builds and validates locally,
then pushes the committed source to the repository configured as `origin`
and publishes a new prerelease there. For this project, `origin` is the original
`xsxs18-dev/mylittleenergy` repository. GitHub Actions is manual-only and also publishes
a release after a successful manual build.
There is no separate publish checkbox. Unique tags prevent overwriting old builds.

Each release includes:
- An installable rootless `.deb`.
- A ZIP containing the **unpacked package files** (`DEBIAN/` and `var/jb/`), not another copy of the `.deb`.
- `BUILD_MANIFEST.json` with the source revision and build time, plus `SHA256SUMS`.

Executable permissions and symbolic links are preserved inside the ZIP. It is
for inspection; use the `.deb` in a package manager for installation. Generated
assets also remain under `dist/<release-tag>/`.

Local builds require `gh` authentication with release access. Commit the
source revision locally before building; the script pushes it after validation. Local uncommitted changes are noted
in the release metadata. The release helper verifies the destination and uses the configured origin for source pushes. A
publication failure is reported as an error; rerun `python3 scripts/release_build.py
packages/<package>.deb` after fixing access rather than silently losing a release.

GitHub Actions billing limits still apply. Failed builds do not produce releases.

### RootHide local build

Use the official [RootHide Theos fork](https://github.com/roothide/Developer):

```sh
THEOS_PACKAGE_SCHEME=roothide scripts/build-local.sh
```

The default RootHide Theos location is `~/theos-roothide`; override with `THEOS_ROOTHIDE`. The Swift toolchain still comes from `THEOS_SWIFT`. Both builds retain signed arm64e metadata and code-signature checks. See [migration](docs/RENAME_MIGRATION.md).
