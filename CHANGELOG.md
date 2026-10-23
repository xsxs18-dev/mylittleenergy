## 1.0.13

- Make MyLittleEnergy free to use without a Havoc account or activation.
- Remove the activation screen, purchase checks, signed receipts, renewal/expiry checks and widget/daemon feature gates.
- Remove the license client, device-identity collection for activation, Worker source and DRM build configuration.
- Add a separately compiled RootHide variant with bootstrap-aware paths and package layout.
- Keep battery history, settings and SpringBoard startup safeguards.

## 1.0.12

- Rename the product to MyLittleEnergy, including the app, widgets, daemon, package identity, URL scheme, build artifacts and license-service configuration.
- Use com.xsxs18.mylittleenergy and a separate Havoc package/license identity.
- Replace the old Voltix package on installation and copy existing settings and battery history into the new data directory without copying the old package-bound license or transient state.
- Keep iOS 16.0 as the deployment minimum. The intended iOS 16–26 range still requires device validation.

## 1.0.11

- A single respring shortly after SpringBoard started no longer disables the SpringBoard part of Voltix for good; only three interrupted starts in a row do, and installing an update resets it.
- The app no longer re-reads the whole battery history every few seconds while it is open; it only reloads when the history files changed.
- "Red Below" thresholds under 20 % work with the system battery colors again.

## 1.0.10

- Check the saved signed license before choosing the initial screen, avoiding an activation-screen flash for licensed users.
- Remove the outdated developer/server-configuration notice.
- Publish command status immediately and read status independently of the battery-history throttle.
- Label the full-charge cancellation explicitly and keep it available even if the charge limit is turned off.
- Show battery-driver return codes for failed charge-control tests without changing their pass/fail criteria or claiming unsupported controls work.
- Hide internal C license entry points from dynamic exports. Signed device-bound licenses remain the actual copy protection; this is not binary encryption.

## 1.0.9

- Configure the production Havoc activation service and require signed licenses in the distribution build.
- Fix Cloudflare's unsupported redirect mode so ownership requests reach Havoc; reject upstream redirects without forwarding the seller token.
- Strengthen the upstream contract test and cover redirected ownership responses.
- Keep device testing of the protected build separate from the successful 1.0.8 development-build test.

## 1.0.8

- Merge the original repository through 1.0.7, retaining signed arm64e metadata checks for iOS 18 and SpringBoard startup safeguards.
- Add consent-based Havoc purchase activation in the app and signed, device-bound offline licenses.
- Add a Cloudflare Worker proxy; seller tokens and signing secrets stay off the device.
- Gate Voltix features through the daemon while keeping diagnostics and stock charging available.
- Preserve valid cached licenses during network failures; renew after 30 days with 15 days of additional offline grace.
- Add public production build configuration checks and activation-service tests.
- Add German and English Havoc product descriptions and deployment instructions.
- Live deployment, Havoc purchase verification and on-device tests remain pending.

## 1.0.3

- Defer SpringBoard integration until after application launch.
- Keep integration disabled after interrupted initialization until an explicit retry in Diagnostics.
- Remove the self-killing SpringBoard watchdog.
- Guard status-bar text composition against nested UIKit setter calls and keep UIKit state on the main thread.
- Use the original battery color resolver when no custom color applies.
- Require an explicit manual action to publish a private prerelease.
- Device validation across iOS versions is still required.

# Changelog

## 1.0.7
- Fixed the small charts on the overview spilling out of their cards
- With the charge limit off, the second quick action switches heat protection instead of showing a disabled "Charge to 100%"

## 1.0.6
- Time left is estimated from your recent drain (last 3 hours on battery, or the last 12) instead of the gas gauge's one-minute value, which was often a fixed placeholder
- While charging, the time shown is until the charge limit (e.g. "80 % in 35 min") and accounts for the slower charging above 80 %
- App, status bar, HUD, widgets and the charging animation all show the same estimate
- Battery Data shows the estimate next to the gas gauge's own values

## 1.0.5
- Fixed the app crashing when an automation rule, a level alert or a rule action was deleted
- Rules without a name of their own keep describing their trigger after it was changed
- Removed unused code

## 1.0.4
- Fixed icons in lists turning from the accent color to blue after a moment
- "Charge to 100%" no longer shows as active while the charge limit is off
- The charging status says that the device charges normally when the limit and heat protection are off
- Singular for one level alert or one rule

## 1.0.3
- Fixed the crash that froze the Lock Screen and made SpringBoard bootloop on iOS 18 arm64e devices: the tweak was built with a compiler that can't sign Objective-C classes, which iOS 18 requires. It is now built with LLVM 23 and every build is checked before packaging
- The Voltix service runs as arm64
- Widgets and the Control Center toggle are back

## 1.0.2
- Test build without the widget extension and the Control Center module, to find what freezes SpringBoard while installing

## 1.0.1
- Fixed SpringBoard freezing after a respring: Voltix no longer touches system services while SpringBoard starts
- Safety net: if SpringBoard hangs or crashes right after starting with Voltix, the next start runs without Voltix and the app shows a warning
- The service only resets charging on boot if it had paused it before

## 1.0.0
- First test version: app with overview, battery details, history graphs and charging sessions
- Charge limit with pause or bypass mode, heat protection, schedule and charge to 100 % once
- Status bar info, battery icon colors, live HUD and lock screen charging animation
- Alerts with banners, sounds and speech, automation rules
- Home Screen and Lock Screen widgets, Control Center toggle (CCSupport)
