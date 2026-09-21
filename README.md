# Headroom

<img src="Assets/Brand/headroom-app-icon.png" alt="Headroom: a green hammock with room to spare" width="128" height="128">

A native macOS menu-bar app for disk space, Codex usage limits, and weekly usage pacing.

See how much room you have left — on your Mac and in your Codex allowance — without opening another dashboard.

## Features

- **Disk capacity:** percentage used and decimal GB free, with amber warnings at 90% and red at 95%.
- **Codex allowance:** remaining percentage and reset time for the most constrained core usage window.
- **Weekly pace:** an even-use budget showing whether your remaining allowance is keeping pace with the time until reset.
- **Low-space notifications:** optional critical alerts with repeat suppression and bounded retries.
- **Launch at login:** a native macOS setting that reflects the actual system registration.
- **Small native interface:** SwiftUI and AppKit, with no third-party package dependencies.

The menu-bar label looks like this, with a terminal symbol identifying Codex:

```text
90% used ·24GB free | [terminal] 7d 79%
```

`7d` means a weekly allowance and `5h` a five-hour allowance. The percentage beside it is **remaining**, while the disk percentage is **used**. The panel provides the full labels, reset times, freshness and weekly context.

## Requirements

- macOS 14 or later (declared minimum).
- Xcode or Command Line Tools with a compatible Swift toolchain.
- A compatible installed Codex CLI, already signed in with ChatGPT, to show Codex allowance. Storage monitoring works independently.

This early development version has been tested on Apple Silicon with macOS 27 and Codex CLI 0.154.0. Intel, the minimum OS version, other CLI versions and prolonged daily use are not yet verified. Headroom is an independent project and is not affiliated with or endorsed by OpenAI or Apple.

## Build and run

From the repository directory:

```sh
bash scripts/check.sh
open dist/Headroom.app
```

The check script runs the tests, builds a release app, verifies its property list and ad-hoc signature, and checks whitespace. It creates `dist/Headroom.app` and `dist/Headroom.zip`; both are ignored by Git. To build without running tests, use `bash scripts/build.sh`.

The local bundle is ad-hoc signed, not a notarized downloadable release. Build it locally; do not disable Gatekeeper to install it.

Headroom runs in the menu bar. Click its reading to open the panel; the gear opens settings. If Codex cannot be found, choose your installed executable using **Choose Codex…** or **Settings → Advanced**. Headroom does not install the CLI or sign you in.

### Launch at login

Enable **Settings → Launch at login** to register Headroom with macOS. Disable it to unregister. If macOS requires approval, the panel links to Login Items in System Settings.

Keep the app at its installed location after enabling this option; for a local build, that is `dist/Headroom.app`. Recheck the setting after moving or replacing the bundle. Ordinary launches, builds and demo previews do not enable registration automatically. Actual logout/login remains untested; registration and removal have been verified locally.

### Storage alerts

Enable **Notify when disk reaches 95%** and allow macOS notifications. The panel shows whether alerts are Off, Checking, Enabled or Blocked. Menu-bar warnings work even with notifications disabled.

A critical episode sends one successfully submitted alert. Two successful readings below 94% re-arm it. Failed submissions retry at most three times, at least one minute apart. macOS Focus and presentation settings may affect whether an accepted alert appears as a banner.

## How readings work

**Storage** checks the volume containing `~/Dev`, or the home directory if Dev is absent. Used percentage and GB free share the same ordinary-free-capacity measurement. GB is decimal, not GiB. Shared APFS allocations can make percentages differ from `df` or other monitors; see [storage semantics](docs/STORAGE.md).

**Codex** uses the installed CLI's app-server protocol to read usage limits. The lowest remaining percentage among valid core Codex windows is displayed. Unrelated model buckets are excluded. Missing, failed or expired data appears unavailable, never as zero usage or unlimited allowance. See [Codex integration](docs/CODEX.md).

**Weekly pace** compares the fraction of allowance remaining with the fraction of the provider's seven-day reset cycle remaining. A deficit of up to two percentage points is “Near pace”; a larger deficit is “Using faster than pace.” The daily budget is a percentage of the full weekly allowance. In the final day, hours until reset replace the daily figure. This assumes even usage: it is a planning guide, not a forecast or guarantee. Stale or invalid weekly data suppresses the estimate.

Storage refreshes every 30 seconds and Codex every two minutes. Opening the panel or pressing Refresh requests updates. Polling pauses during sleep; wake requests fresh readings. Each CLI read is bounded, and normal quit waits for owned-helper cleanup.

## Privacy and scope

Headroom does not scan directories, delete files, clean caches, run models or start Codex tasks. It reads volume metadata and quota information. It does not read credential files directly or persist account identity, tokens or raw quota responses.

Its preferences store the notification opt-in, a small alert-episode state and an optional CLI executable path. macOS owns login-item registration; Codex owns its existing authentication and network traffic. There is no usage-history database, automatic package installer or automatic updater.

## Development and verification

```sh
bash scripts/check.sh
bash scripts/smoke-lifecycle.sh
```

The lifecycle smoke check uses a deliberately stuck fake CLI and verifies that quitting cleans up the app and helper. It does not use a real Codex account.

The suite covers storage math and alert episodes, quota parsing and mixed windows, weekly pacing, bounded CLI transport and cleanup, setup recovery, and login-item state changes. Read [AGENTS.md](AGENTS.md) for contribution conventions and [verification status](docs/VERIFICATION.md) for tested behavior and outstanding limits.

### Preview and synthetic screenshots

```sh
open dist/Headroom.app --args --demo --preview-window --show-settings
```

Demo mode uses synthetic values and never changes preferences, submits notifications or registers a login item. Available `--demo-state` values are `normal`, `faster`, `near`, `short-exhausted`, `blocked` and `missing-cli`. Use demo data for public screenshots.

`--render /absolute/path.png` with `--preview-window` saves the app's own panel view. `--smoke-test` exits after 15 seconds through the normal quit path. `--codex-cli /path/to/codex` overrides CLI discovery for one launch without saving the path. Quit an already-running copy before launching a preview with different arguments.

### Explicit native notification diagnostic

```sh
dist/Headroom.app/Contents/MacOS/Headroom --check-notifications
```

This sends a clearly labeled synthetic low-space alert if macOS permits it, verifies same-episode suppression and delivered-notification presence, removes the test alert, then exits. It bypasses the saved notification opt-in only for this explicit diagnostic. It does not poll Codex, fill the disk, or write the saved alert preference or episode. Delivered status does not prove that a banner was visually shown.

Add `--request-notification-permission` only when intentionally testing the system permission request; this can change OS authorization. Use a bounded external timeout for unattended runs. The test suite does not change these OS controls.

## Brand assets

The Balanced hammock is Headroom's app identity. Editable color and monochrome SVGs and PNG exports live in `Assets/Brand`. The build generates a complete macOS icon family from shared vector geometry using Apple frameworks. See [brand assets and regeneration](docs/BRAND.md).

## License

[MIT](LICENSE.md) © 2026 Harry Tasioulis.
