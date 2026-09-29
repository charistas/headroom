# Working on Headroom

`AGENTS.md` is canonical repository guidance; `CLAUDE.md` imports it.

## Scope and architecture

- Headroom is a native macOS menu-bar app for volume capacity, core Codex allowance and weekly pacing. Keep changes small and focused on that purpose.
- `Sources/HeadroomCore` owns data contracts, validation, alert/pace policies and bounded Codex CLI transport.
- `Sources/Headroom` owns SwiftUI/AppKit presentation, timers, notifications and native lifecycle/login-item integration.
- `Tests/HeadroomCoreTests` and `Tests/HeadroomAppTests` cover those respective layers. Build and verification commands live in `scripts/`.
- Prefer Apple frameworks. Discuss new dependencies and review maintenance, release recency, adoption, security and license compatibility before adding them.

## Behavior to preserve

- Disk and Codex failures and freshness remain independent. Missing data is never zero usage or unlimited allowance.
- Disk percentage and free GB must use one coherent ordinary-free-capacity measurement. Thresholds use unrounded values; display rounding must not drive policy.
- Select only core Codex limits. Keep the selected short/weekly window distinct from weekly pacing, including labels, colors and reset times.
- Weekly pacing is an even-use estimate, not a prediction. Suppress it when the required weekly data is missing, invalid or stale.
- Retain alert recovery, bounded retry and restart behavior. A saved alert preference is separate from macOS permission and presentation settings.
- macOS is the source of truth for Launch at Login. Never register automatically during builds, tests, demo mode or an ordinary launch.
- Bound CLI time/output, sanitize errors, avoid overlapping reads and await owned-helper cleanup at normal quit. Do not introduce broad process kills.

## Privacy and boundaries

- Do not read account-token files, persist raw provider responses, run models/tasks, clean caches, scan directories or delete user files as part of ordinary app behavior.
- Keep real account data, credentials, private diagnostics, local screenshots and build products out of Git. Use synthetic demo data for public images and fixtures.
- Do not change other monitoring tools or system preferences as part of routine builds or runs. Such changes require an explicit user request.
- Local implementation does not authorize a commit, push, public release, notarization or distribution. Follow the user's explicit scope for each.

## Changes and verification

- Inspect the working tree first and preserve unrelated work. Fix root causes, follow the existing architecture and avoid broad scripted rewrites.
- Add meaningful regression tests for bug fixes when practical; otherwise explain the exact gap. Keep tests independent of real accounts and OS registration changes through injected operations or fixtures.
- Update the README and relevant documents when behavior, setup or API contracts change. Preserve MIT attribution and license text.
- Run the full local gate before handoff:

  ```sh
  bash scripts/check.sh
  ```

- On this laptop, run the gate as `~/.codex/apple-toolchain/with-lock.sh bash scripts/check.sh`; the current script and its build helper do not acquire the lock themselves.
- Also run `bash scripts/smoke-lifecycle.sh` for changes to process ownership, shutdown, refresh coordination or app lifecycle; on this laptop use `~/.codex/apple-toolchain/with-lock.sh bash scripts/smoke-lifecycle.sh`.
- For UI changes, inspect the native rendered states, including unavailable/error states and menu-bar fit where relevant. Demo previews must have no side effects.
- Native notification checks are explicit diagnostics with real OS effects; never run them silently as part of routine tests. Do not log out or restart the user's Mac to test login behavior without authorization.
- Report what passed, what remains unverified, and any blocked command with its first relevant error. Do not equate compilation, synthetic tests or registration status with full real-world acceptance.

## Apple Toolchain Coordination And Cleanup

On this laptop, before Apple builds, tests or heavy indexing, read `~/.codex/apple-toolchain/SIMULATORS.md` and run native macOS/Swift commands through `~/.codex/apple-toolchain/with-lock.sh COMMAND ARGS...`. A repository adapter may acquire the same lock instead; do not nest locks or bypass a missing/incompatible helper. Keep heavy Apple work serial, and report another session's live lock, active build or booted simulator as a blocker. Idle Xcode and non-active system helpers need not be terminated.

Reuse warm build caches. Preserve required failure evidence, shared caches, user data and other sessions' files; remove only safely disposable task-owned scratch. Stop only task-owned background processes before handoff unless asked to retain them, check their state after build work, and report cleanup and retained resources. Never kill unrelated processes or alter another session's simulator. If simulator work is later introduced, use the host's exact-identity supervisor; do not provision devices or use name-based destinations automatically.

On another machine, use its deliberately configured toolchain with equivalent ownership safeguards. All repository behavior, privacy, release and verification rules remain applicable without this private host setup.
