# Headroom verification — 21 September 2026

## Balanced hammock app icon

- PASS: approved A — Balanced direction recreated as shared vector geometry, editable color/monochrome SVGs and PNG exports; Light icon packaged as `Headroom.icns`.
- PASS: `bash scripts/check.sh` — 52 tests, release build, icon generation, plist/signature and whitespace checks.
- PASS: native icon inspection found all expected pixel sizes from 16 through 1024; macOS resolved the new app icon from the installed bundle.
- PASS: 1024-pixel and 32-pixel artwork visually inspected. The recreation uses flat layers rather than reproducing the reference's raster shading.
- PASS: normal relaunch and live disk/Codex smoke; menu item remains 210 points and wholly right of the notch.
- NOT RUN: all system surfaces and long-lived icon caches; dark/tinted app-icon variants are not included.

## Launch at Login

Added only a native Launch at Login setting using `SMAppService.mainApp`. The switch reflects system status, refreshes on panel/settings open and app activation, and handles approval requirements and registration errors. It never registers automatically on an ordinary launch or in demo mode.

- PASS: `bash scripts/check.sh` — 52 tests (45 core, 7 app), release build, plist/signature and whitespace checks.
- PASS: five focused tests cover registration/removal, external revocation/reapproval, failed registration, failed removal and demo isolation using injected operations; they do not change real login items.
- PASS: native app UI changed Off → On → Off → On, with the checked state read back from macOS. Left enabled for this user at `~/Dev/headroom/dist/Headroom.app`.
- PASS: native expanded settings visually inspected with no clipping.
- PASS: `bash scripts/smoke-lifecycle.sh` — app and stuck helper exited in 1.71 seconds.
- PASS: live disk/Codex smoke after registration; 210-point menu item wholly right of notch. Updated Headroom relaunched in the menu bar.
- NOT RUN: actual logout/login, to avoid disrupting the current session. Registration is verified, but a physical sign-in remains an acceptance check.

## Current simplification pass

The panel now keeps each quota percentage/reset together, includes weekly remaining/reset when a shorter window is selected, and moves arithmetic/re-arm/APFS explanations into hover help. CLI override is under Advanced, with a direct Choose Codex action when missing. The two-point pace policy and alert safeguards are unchanged. An explicit synthetic native notification diagnostic exercises the real OS path without writing the saved alert preference or episode.

| Check | Result |
|---|---|
| `bash scripts/check.sh` | PASS: 47 tests (45 core, 2 app-model recovery), release build, plist/signature and whitespace checks |
| `bash scripts/smoke-lifecycle.sh` | PASS: stuck-helper quit and cleanup in 1.76 seconds |
| Native renders | PASS: normal, short exhausted with weekly context, blocked settings, and missing CLI; no clipping observed |
| Real notification submission | PASS: synthetic critical sample accepted, one attempt, recorded in macOS delivered notifications; test alert then removed |
| Same-episode repeat suppression | PASS: two further checks retained one attempt |
| OS permission revoked | PASS: temporarily switched Headroom notifications off in System Settings; diagnostic reported Blocked with zero attempts |
| OS permission restored | PASS: restored original On setting; accepted/delivered and repeat suppression passed again |
| Live disk and Codex | PASS |
| Current menu geometry | PASS: 210-point item wholly right of notch; left edge 890.0, safe-region start 824.5 |
| Reload | PASS: normal old-process quit, updated menu-bar app launched |
| Banner visually observed / first-time permission prompt | NOT RUN: delivered status is from macOS API; permission was already allowed before this check |
| Physical sleep/wake, prolonged energy, full accessibility | NOT RUN in this pass |

The diagnostic used a synthetic 96%-used sample and a separate notification identifier; it did not fill the disk, poll Codex, or write the saved alert preference/episode. System permission was restored to its original setting. No source commit, publication, startup registration, or external monitor preference change occurred. Older verification below is historical.

## Historical first-build trial

The native implementation builds, reads live disk/Codex data, and passes core and lifecycle checks. **Menu-bar replacement acceptance: FAIL in the current arrangement.** The 210-point label is readable but does not fit wholly to the right of this Mac's notch during the actual replacement trial. This preceded the user’s later choice to disable the old monitor and run Headroom; it is not the current installation state.

## Historical checks

| Check | Result |
|---|---|
| `bash scripts/check.sh` | PASS: 26 tests, release build, property list, ad-hoc signature and whitespace checks |
| Live allowance reads | PASS: four core probes and native app reads through the existing login |
| Native app live smoke | PASS: storage and Codex both available; 210-point status label; clean automatic exit |
| Stalled-helper app quit | PASS: app exited in 1.20 seconds; owned helper absent afterward |
| SIGTERM-ignoring helper app quit | PASS: `bash scripts/smoke-lifecycle.sh`; app and helper exited in 1.70 seconds |
| Failure isolation | PASS in stalled helper regression: disk remains available while Codex has no reading |
| Disk measurement reconciliation | PASS: ordinary free bytes agreed; APFS denominator discrepancy documented |
| Native demo panel rendering | PASS for inspected dark appearance; fixture data only |
| Actual replacement fit | FAIL: item left edge 738.0 pt, notch-safe right area begins 824.5 pt; about 86.5 pt overlap |
| Restore existing monitor | PASS: original DisabledPlugins state restored and plugin script SHA-256 unchanged |
| Short resource sample | App approximately 51.2–51.4 MiB RSS; sampled 0% CPU after initial sample in a 15-second run |
| Codex transient-helper footprint | Approximately 155.1 MiB peak aggregate RSS in an earlier short probe; descendants gone afterward |
| Real notification delivery / revoked permission | NOT RUN; notification policy covered by regression tests |
| Physical sleep/wake, prolonged use, energy and disk-write growth | NOT RUN |
| Full VoiceOver navigation, contrast audit, other OS versions / Intel | NOT RUN |
| Public source, license/name clearance, Developer ID / notarization | NOT RUN; nothing published |

The resource samples are observations, not endurance or performance guarantees. The app's code declares macOS 14+, but only the current Apple Silicon macOS 27 host was tested.

## Review fixes

An independent review found that disabling alerts stopped recovery observations; this could retain an old episode latch and suppress the next alert. Recovery now continues while delivery is disabled, and re-enabling within a previously notified episode does not repeat it. Two regression tests cover these sequences.

Lifecycle review added per-pipe SIGPIPE protection and awaited helper cleanup. The native interrupted-read check then exposed a modal-run-loop hang. Cleanup now runs outside MainActor and termination replies are scheduled in the modal run-loop mode. The regression script exercises an actual app quit with a helper that ignores SIGTERM. Apple's [termination documentation](https://developer.apple.com/documentation/appkit/nsapplication/terminatereply/terminatelater) explains the modal-loop constraint.

The reversible SwiftBar trial used its [documented plugin URL actions](https://github.com/swiftbar/SwiftBar#url-scheme). This installed version responded to the short plugin name; the filename-form request did not confirm a state change and was safely restored before retrying. Only the disk plugin was temporarily disabled. No source change or permanent preference change was left behind.

## Historical scope remaining

Resolve menu-bar room versus a shorter label, then test the chosen layout in place. Notification delivery, physical sleep/wake and a representative daily-use session were unverified at that point. The local repository is initialized, source is uncommitted, and no remote is configured.

## Weekly pacing enhancement

The terminal icon now indicates weekly pace independently of disk state: neutral on pace, amber faster than even usage, red exhausted. The panel compares allowance remaining with time remaining in the provider's seven-day cycle and shows a daily allowance budget. Existing numerical quota selection is preserved; an explicitly returned weekly window is tracked separately.

`bash scripts/check.sh` passed 34 tests, release build and signature/whitespace checks after this enhancement. The eight added cases cover parser retention without confusing short windows, missing duration/reset, equal and faster pace, exhaustion, stale/expired/future data, final-day budget handling and elapsed time. Native sample-panel rendering was inspected. No new notifications, credentials, quota history or polling requests were introduced.
