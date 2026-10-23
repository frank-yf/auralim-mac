[English](README.md) | [简体中文](README.zh-CN.md) | [Website](https://frank-yf.github.io/auralim-site/en/)

# Auralim · 晦明

**Between light and dark.**

*晦明变化，循日而行。*

Auralim is a native macOS menu bar app built with Swift and SwiftUI. It switches between light and dark appearance at local sunrise and sunset. Sunrise, sunset, and time-zone lookup are calculated on your Mac, without online APIs or macOS's automatic appearance schedule.

## Product overview

### Features

- **Automatic sunrise and sunset switching**: independently calculates solar events to switch to light at sunrise and dark at sunset.
- **Separate time offsets**: adjust sunrise and sunset independently by ±120 minutes, using synchronized sliders and minute inputs. Settings show the adjusted switch times.
- **Three appearance modes**: Light, Auto, and Dark stay synchronized between the menu bar panel and settings. System Auto and App Auto are clearly distinguished.
- **Travel support**: automatic location uses your current coordinates and local time zone. You can also choose a built-in city; failed refreshes keep the cached location, using the saved manual city only when no valid cache exists.
- **Wake recovery**: checks appearance and the schedule on launch, wake, session restore, and system time changes.
- **Menu bar app**: a warm gold sun in light mode and a pale blue-purple moon in dark mode follow the actual system appearance. No Dock icon or WebView. Scheduling uses events and one-shot timers, with no continuous background polling.
- **Preferences**: launch at login, 12 interface languages, and an optional sun-and-moon transition animation that is off by default.

### Languages

English is the development baseline. Settings offers Follow System and 12 languages: English (`en`), Simplified Chinese (`zh-Hans`), Japanese (`ja`), Traditional Chinese (`zh-Hant`), German (`de`), French (`fr`), Spanish (`es`), Brazilian Portuguese (`pt-BR`), Korean (`ko`), Italian (`it`), Russian (`ru`), and Dutch (`nl`).

Language changes apply immediately and are saved locally. Follow System uses the first supported language in macOS preferences, with English as the fallback. Chinese script takes precedence over region; Portuguese variants use Brazilian Portuguese. Interface text, help, city names, date formatting, update messages, and system permission descriptions use shared localization resources. macOS chooses the language of its own permission dialogs.

### Download and install

Requires **macOS 13 or later**. Release packages include both Intel and Apple silicon architectures.

1. Download the DMG installer or ZIP archive from [GitHub Releases](https://github.com/frank-yf/auralim-mac/releases).
2. Drag `Auralim.app` into Applications, then open it. The app appears in the menu bar.
3. Click the menu bar icon, then choose **Settings…**.

v0.2.1 is ad-hoc signed and has not been notarized by Apple. macOS may block the first launch. After confirming the download source, follow [Apple's official instructions](https://support.apple.com/en-us/102445). Checksum files are included with the release.

### In-app updates

Starting with 0.3, Sparkle 2 checks daily and downloads compatible stable updates in the background. Settings shows progress and a **Restart to update** button when ready. Clicking installs and relaunches; updates do not force a restart. Following Sparkle's standard behavior, a prepared update may also install on normal quit. Manual checks, inline errors, retry and a GitHub release-page fallback are available in the footer.

The signed feed is hosted at `https://github.com/frank-yf/auralim-mac/releases/latest/download/appcast.xml`; package URLs point to immutable release tags. Both the feed and archives use EdDSA signatures, with verification before extraction; signed-feed failures never expire into relaxed validation. Requests go to GitHub without location coordinates; system profiling is disabled. Older versions need one manual installation of 0.3 or later to gain the updater.

### Usage

Choose Manual city or Automatic location in settings, then select an appearance mode in the menu bar panel or settings:

With no saved city, the app matches the system time zone to a built-in city. It uses the first listed city when several share a zone, and Shanghai if no match exists. The choice is saved for later launches.

| Mode | Behavior |
| --- | --- |
| Light | Switches to light immediately and pauses the app's automatic schedule |
| Auto | Switches at local sunrise and sunset, including your offsets |
| Dark | Switches to dark immediately and pauses the app's automatic schedule |

When the app's automatic schedule is disabled, Auralim reads the system settings on every launch. A fixed system Light or Dark setting highlights the corresponding segment. With System Auto, none of the three segments is highlighted, and the app displays **System Auto**. Enabling the app's Auto mode explicitly displays **App Auto**.

When using the app's automatic schedule, turn off automatic appearance in macOS System Settings to avoid conflicting schedules. The first appearance change requires permission to control System Events. Automatic location requires location permission.

#### Sunrise and sunset offsets

Both sliders use the center as zero. Move either way to adjust the switch time:

| Event | Slide left | Slide right |
| --- | --- | --- |
| Sunrise | Delay switching to light; stay dark longer | Switch to light earlier |
| Sunset | Delay switching to dark; stay light longer | Switch to dark earlier |

In the input fields, negative numbers mean earlier and positive numbers mean later, from −120 to +120 minutes. Changes apply when you release the slider, press Return, or leave the input field. Reset returns the offset to zero. Settings show the adjusted “Switch to light” and “Switch to dark” times, using the active location's time zone and local date.

The automatic schedule keeps light appearance during polar day and dark appearance during polar night. Offsets that cross adjacent day or night boundaries are limited or skipped, with a notice in the interface. Calculations do not account for terrain obstruction, elevation, or real-time weather.

#### Offline use, privacy, and quitting

Manual city mode works entirely offline. Enabling automatic location for the first time requests macOS location permission. Automatic location uses macOS Location Services, which may require Wi-Fi or a network connection. Coordinates, the local time zone, and the fix timestamp are cached only on your Mac; Auralim never uploads location data. It requests a one-time fix every 3 hours without continuous tracking or a configurable refresh interval. Launch and wake reuse fresh cached data; manual refresh and system time-zone changes request a new fix immediately. Failed refreshes keep the cached location. Your saved manual city is used only when no valid cache exists. City, offset, and language settings are also stored locally.

Closing settings keeps the app running. Choose Quit from the menu bar panel to stop future scheduling while keeping the current system appearance. Launch at login can be enabled in settings. The sun-and-moon animation is off by default and respects the system's Reduce Motion setting when enabled. After wake, Auralim corrects the appearance immediately. If it differs from the appearance before sleep, the animation waits for the desktop to return or unlock and plays once.

## Development guide

### Requirements and build

You need macOS, a Swift 6 toolchain, and the macOS SDK, provided by Xcode or Command Line Tools. The app targets macOS 13 and uses Swift Testing for tests.

```sh
git clone https://github.com/frank-yf/auralim-mac.git
cd auralim-mac
make help
make build
make run
```

Quit the running app before building. `make build` creates and signs `dist/Auralim.app` for the host architecture by default. `make run` opens that app bundle. Run the packaged `.app` so macOS can read its permission usage descriptions and resources.

After changing the icon artwork in `Resources/Icons/Auralim.png`, run `make icon` to regenerate `Resources/Auralim.icns` using macOS `sips` and `iconutil`. The command also updates `Sources/Auralim/Resources/AppIcon.png`, the 256px image shared by the settings and menu panels. The artwork and generated icon resources are tracked in Git; `make build` packages them into the app bundle.

Run `make clean` to remove generated `.app` bundles under `dist/` and `artifacts/`, including release staging and extracted verification copies. Source files, DMG / ZIP packages, build caches, and other verification files are preserved.

Builds use ad-hoc signing by default. To specify a Developer ID identity:

```sh
AURALIM_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" make build
```

Production distribution also requires Apple notarization. For a universal package, build Intel and Apple silicon versions separately, combine them, and sign again. Build products, caches, and verification output are stored in `dist/`, `.build/`, and `artifacts/`; these directories are excluded from Git.

### Preparing a GitHub update release

```sh
AURALIM_UNIVERSAL=1 make build
make prepare-update
```

Upload the universal ZIP, signed `appcast.xml` and `SHA256SUMS.txt` from `dist/updates/<version>/` to the stable GitHub Release `v<version>`, and mark it Latest. A DMG alone is not enough. The script validates versions, architecture, signing-key continuity and signatures; it does not publish releases or overwrite existing version artifacts.

The update private key stays in the login Keychain under Sparkle account `app.duskshift.mac`; only its public key ships in the app. Securely back up/import that account with Sparkle's `generate_keys` tool before moving release machines. Generating a different key will break updates for existing installations.

Local ad-hoc builds preserve upstream Sparkle signatures and disable library validation only for the ad-hoc host. Developer ID builds re-sign nested helpers and the framework inside-out and retain library validation; production distribution still requires notarization. The bundle ID remains unchanged to preserve preferences; permission continuity requires testing with the production signing identity.

### Project structure

```text
Sources/Auralim/       Menu bar, settings, localization, appearance, and location services
Sources/AuralimCore/   Solar calculations, offsets, scheduling, and offline time-zone lookup
Sources/CZoneDetect/   Time-zone boundary data parser
Resources/            App metadata, localized display names, and signing entitlements
Tests/                Core logic and native UI tests
scripts/              Build, test, and on-device verification tools
Makefile              Development command entry points
```

Solar calculations use Meeus / NOAA solar coordinate equations and a standard apparent horizon of `−0.833°` to calculate sunrise and sunset within the local date. One-shot timers and system events trigger schedule updates, with appearance requests executed serially. Location uses one-shot requests and one-shot periodic timers, with no continuous updates or significant-change monitoring. Transient failures receive bounded retries within a 30-second acquisition deadline.

### Test only the affected scope

Run only the tests affected by each change. Regular tests require an explicit `FILTER`; they will not run without one:

```sh
make test FILTER=SolarTests
make test FILTER=LocalizationTests
```

| Command | Scope |
| --- | --- |
| `make test-updates` | Update state, install action and localized strings |
| `make test-update-ui` | Native footer clicks and localized light/dark screenshots |
| `make test-update-install` | Real background download, install and relaunch in disposable apps |
| `make test-update-quit` | Install on normal quit without relaunch in a disposable app |
| `make test-update-signature` | Reject a tampered signed feed without installation |
| `make test-sliders` | Slider gradient rendering |
| `make test-ui` | Slider and input interactions, synchronization, and displayed switch times |
| `make test-localization-ui` | Twelve-language native picker, persistence, settings/menu labels, light/dark screenshots |
| `make test-ui-layout` | Settings and menu bar layout, languages, light/dark appearance, and scrolling |
| `make test-appearance-mode` | Appearance modes, system state reads, and request coordination |
| `make test-ui-mode` | Appearance mode switching and synchronization between both panels |
| `make test-transitions` | Animation triggers, system results, and request coordination |
| `make test-ui-transitions` | Half-screen sun-and-moon transitions, the animation toggle, and resource cleanup |

Native UI tests require a macOS login session, Accessibility permission, and Screen Recording permission. They use temporary preferences and mock system services. Actual appearance authorization, sleep/wake recovery, launch at login, location permissions, and travel across time zones require separate on-device validation.

Some Command Line Tools distributions ship a Swift Testing framework that requires macOS 14+ to run tests. This does not change the app's macOS 13 deployment target. See the relevant release for the architectures and macOS versions validated on hardware.

## License and data sources

The project uses the [MIT License](LICENSE). Third-party components and data retain their own licenses:

- [ZoneDetect](https://github.com/BertoldVdb/ZoneDetect): BSD-3-Clause; see [ZoneDetect-LICENSE.txt](Sources/AuralimCore/Resources/ZoneDetect-LICENSE.txt).
- Time-zone boundary data contains information from [timezone-boundary-builder](https://github.com/evansiroky/timezone-boundary-builder), made available under ODbL 1.0; see [TimezoneData-LICENSE.txt](Sources/AuralimCore/Resources/TimezoneData-LICENSE.txt).
- The bundled database is version 2024a and is not updated at runtime. Time-zone offsets and daylight-saving rules come from macOS Foundation. See [TimezoneData-NOTICE.txt](Sources/AuralimCore/Resources/TimezoneData-NOTICE.txt) for pinned sources and full notices, also available from the bottom of the app's settings.

Sparkle is MIT licensed; its full notice is included in the app’s Licenses & data sources.
