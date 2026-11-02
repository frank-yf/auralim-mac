[English](README.md) | [简体中文](README.zh-CN.md) | [Website](https://frank-yf.github.io/auralim-site/en/)

# Auralim · 晦明

**Between light and dark.**

Auralim is a native macOS menu bar app that switches system appearance with local sunrise and sunset. Built with Swift and SwiftUI, it calculates solar events and time zones on your Mac, independently of macOS Auto.

The Chinese name comes from Ouyang Xiu’s *The Old Drunkard’s Pavilion*: “**晦明**变化者，山间之朝暮也。”

> This README describes **0.5.4**. Downloadable builds are listed on [GitHub Releases](https://github.com/frank-yf/auralim-mac/releases/latest). See [CHANGELOG.md](CHANGELOG.md).

## What it does

- **Light / Auto / Dark** in both the menu panel and settings. Auto follows the app’s solar schedule; it is distinct from macOS Auto.
- **Independent sunrise and sunset offsets**, from −120 to +120 minutes, with synchronized sliders and precise numeric inputs.
- **Choose a city or use automatic location.** Coordinates stay cached locally; failed refreshes keep the previous fix, with a saved city as fallback.
- **Startup recovery.** Auto waits for the desktop and checks system appearance with bounded retries; manual selections take priority.
- **Wake recovery.** Correct the appearance immediately after wake; an enabled animation waits until the desktop is ready or unlocked.
- **Optional transition animation and countdown.** Both are off by default. Launch at login is also available in settings.
- **Manual or automatic software updates**, defaulting to manual while respecting an existing saved choice.
- **12 app languages:** English, Simplified Chinese, Japanese, Traditional Chinese, German, French, Spanish, Brazilian Portuguese, Korean, Italian, Russian and Dutch. The website has English and Simplified Chinese pages.

There is no WebView or continuous location tracking. One-shot timers and system events drive the schedule.

## Install and get started

Requires **macOS 13 or later**. Published universal packages contain Intel and Apple silicon builds; the minimum OS and each hardware configuration still require on-device validation.

1. Download a DMG or ZIP from [Releases](https://github.com/frank-yf/auralim-mac/releases/latest) and place `Auralim.app` in Applications.
2. Open the menu bar icon, then **Settings**. Choose **Select city** or **Automatic location**. On first launch, a city is matched to the system time zone; Shanghai is the fallback.
3. Select **Auto** to enable the solar schedule. Light and Dark pause that schedule and use the chosen appearance.

Current public packages are ad-hoc signed and not Apple notarized. If macOS blocks opening, verify the download source and follow [Apple’s guidance](https://support.apple.com/en-us/102445). Checksums are supplied with the release. The first real appearance change requires permission to control System Events; location permission is requested only when automatic location is enabled.

If app Auto is off, each launch reads the current macOS appearance. System Auto leaves all three segments unselected, with an explanation in settings. This avoids treating system Auto as the app’s solar schedule. When using app Auto, disable macOS’s own automatic appearance schedule to avoid competing schedules.

### Adjust switching times

| Event | Negative / left | Positive / right |
| --- | --- | --- |
| Sunrise → Light | Switch to light earlier | Switch to light later |
| Sunset → Dark | Switch to dark earlier | Switch to dark later |

Release a slider, press Return, or leave an input field to apply a value. Clicking blank space commits the edit; Tab moves focus. Reset returns to zero. Location settings show the **actual, unadjusted** sunrise and sunset as `HH:mm`; the menu panel shows the next adjusted switch with its date and time, in the active location’s time zone.

Polar day stays light and polar night stays dark. Offsets crossing adjacent day/night boundaries are limited or skipped. Terrain, elevation and live weather are not included in the calculation.

### Animation and countdown

| Trigger | Countdown | Appearance change |
| --- | --- | --- |
| Manually select Light / Auto / Dark | Skipped | Play the enabled animation if a change is needed |
| Scheduled solar transition | Follows the setting | Animate if enabled, then apply |
| Wake correction | Skipped | Correct immediately; animate later if enabled and needed |

At animation motion end, Auralim requests the system appearance change and keeps the final frame visible for one second. Reduce Motion skips the animation. The optional countdown is **10 seconds by default**, adjustable from 1–120 seconds:

- **Skip this switch:** skip the current target until the schedule changes target or you explicitly select a mode again.
- **Got it:** hide the panel while the countdown continues.
- **Switch now:** end the wait and continue through the enabled animation.

No system notification permission is needed. Quitting stops the schedule and leaves the current system appearance in place.

### Location, privacy and updates

Manual city mode is entirely offline. Automatic location uses macOS Location Services, which may require Wi-Fi or a network connection. Auralim itself does not upload coordinates. Position, time zone and fix time are stored locally; the fix time is used internally and is not displayed.

A fresh fix is requested every **3 hours**, on manual refresh, or after a system time-zone change. Each acquisition has a **5-second total deadline**, excluding the system permission prompt. Cached coordinates remain active during a refresh and after failure; without a valid cache, the saved city is used. After a temporary failure, route/DNS changes can trigger up to two additional recovery rounds, at least 60 seconds apart. This cannot bypass a VPN that blocks system Location Services.

Updates use Sparkle 2. **Manual updates** checks and downloads only when requested. **Automatic updates** checks daily and downloads compatible updates in the background. Settings show progress and **Restart to update** when ready; Sparkle can also install a prepared update on normal quit. The signed feed and archives are verified before extraction; update requests contain no coordinates and system profiling is disabled.

## Development

Requires macOS, a Swift 6 toolchain and the macOS SDK from Xcode or Command Line Tools.

```sh
git clone https://github.com/frank-yf/auralim-mac.git
cd auralim-mac
make run          # quit local instances, build/sign and open the standard app
make run-debug    # quit local instances, build/sign and open the debug app
```

`make build` and `make build-debug` only build. Outputs are `dist/Auralim.app` and `dist/debug/Auralim Debug.app`. Run commands wait for local development instances to quit, stop on failure and leave installed copies in Applications untouched.

Debug controls are compiled in only with `AURALIM_DEBUG_TOOLS`. The debug app has a separate bundle ID, preferences and permissions, and disables stable automatic updates. It offers countdown, animation and full-sequence previews, plus a cancellable read-only system appearance check. The check also requires System Events Automation permission and never changes appearance. **Switch system appearance after preview** is off at every launch. When enabled, preview motion end applies the selected appearance in manual mode; a countdown-only preview applies when the countdown finishes.

### Build and validate by scope

```sh
make help
make test FILTER=AppearanceCountdownTests
make test FILTER=LocationControllerTests
make test-ui             # native slider and input interactions
make test-ui-debug       # debug settings and preview actions
make test-update-ui      # update controls
make clean              # remove generated .app copies in dist/ and artifacts/
```

Tests require an explicit filter. Use only checks affected by a change; see [VALIDATION.md](VALIDATION.md) for recorded coverage and limitations. Native UI checks use isolated preferences and mock system services and require a logged-in macOS session, Accessibility and Screen Recording permissions. Real permission continuity, VPN recovery, travel and OS/hardware compatibility need on-device validation. Some Swift Testing distributions require macOS 14+ to run tests; the application deployment target remains macOS 13.

### Distribution

```sh
AURALIM_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" make build
make prepare-release    # prepare universal standard/debug release assets locally
```

Developer ID distribution also requires Apple notarization. Without a signing identity, local builds use ad-hoc signing. `make icon` regenerates the `.icns` and shared panel artwork from `Resources/Icons/Auralim.png`.

`make prepare-release` prepares a standard universal DMG, signed update ZIP/feed/checksums, and a separate universal debug ZIP/checksums. It does not publish or overwrite an existing version’s release assets. Publish the standard ZIP, signed `appcast.xml` and checksums together; a DMG alone is insufficient for in-app updates. Debug builds never enter the stable feed.

The update signing key is stored in the login Keychain under the Sparkle account `app.duskshift.mac`. Preserve and securely transfer that key when moving release machines; do not generate a replacement for an existing installation base. Private keys never belong in Git or release archives.

### Source map

| Path | Purpose |
| --- | --- |
| `Sources/Auralim/` | Native UI, appearance coordination, location and updates |
| `Sources/AuralimCore/` | Solar calculations, offsets, scheduling and offline time zones |
| `Sources/CZoneDetect/` | Time-zone boundary parser |
| `Resources/` | App metadata, localized names and entitlements |
| `Tests/`, `scripts/`, `Makefile` | Scoped tests, build and validation tools |

Solar events use Meeus / NOAA equations and the standard apparent horizon of `−0.833°`. Cached location time zones use the bundled boundary database; DST and offsets come from macOS Foundation.

## License and data sources

The project uses the [MIT License](LICENSE). Third-party components and data retain their own licenses:

- [ZoneDetect](https://github.com/BertoldVdb/ZoneDetect): BSD-3-Clause; see [ZoneDetect-LICENSE.txt](Sources/AuralimCore/Resources/ZoneDetect-LICENSE.txt).
- Time-zone boundary data contains information from [timezone-boundary-builder](https://github.com/evansiroky/timezone-boundary-builder), made available under ODbL 1.0; see [TimezoneData-LICENSE.txt](Sources/AuralimCore/Resources/TimezoneData-LICENSE.txt).
- The bundled database is version 2024a and is not updated at runtime. Time-zone offsets and daylight-saving rules come from macOS Foundation. See [TimezoneData-NOTICE.txt](Sources/AuralimCore/Resources/TimezoneData-NOTICE.txt) for pinned sources and full notices, also available from the bottom of the app's settings.

Sparkle is MIT licensed; its full notice is included in the app’s Licenses & data sources.
