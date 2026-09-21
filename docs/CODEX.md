# Codex allowance integration

Headroom invokes the installed Codex CLI as a short-lived stdio app-server. It sends only `initialize`, the `initialized` notification, and `account/rateLimits/read`. It does not start tasks, run models, consume reset credits, read credential files, or persist quota responses. The CLI owns login and refresh behavior. Its stderr is discarded, and UI errors use fixed sanitized messages.

The initial implementation was checked against the installed CLI 0.154.0 using its `app-server generate-json-schema` command, particularly `v1/InitializeParams.json` and `v2/GetAccountRateLimitsResponse.json`. The published protocol entry point is [OpenAI's App Server documentation](https://learn.chatgpt.com/docs/app-server). JSON schema generation and allowance reads do not create a task.

## Quota semantics

- Prefer `rateLimitsByLimitId.codex`. Never compare unrelated model-specific buckets to core quota.
- Accept the backward-compatible `rateLimits` only when its `limitId` explicitly identifies `codex`.
- Choose the lower remaining percentage of the provided valid primary/secondary windows. A null window is absent, never zero usage or unlimited allowance.
- Compute remaining as `max(0, 100 - usedPercent)`. Reject malformed values, negative usage, boolean percentages, contradictory bucket identities, and malformed duration/reset fields.
- Label known durations from returned data. A missing duration is “Current window”; five-hour and weekly windows are not presumed.
- An already-expired reset is an error. Dropping an expired constraint or inventing recovery could incorrectly imply available allowance.
- Explicit `ordinaryUsageAllowed: false` or core `spendControlReached: true` makes usage unavailable even when a percentage is positive. This app shows quota, not a promise that a particular model/request can run.

## Weekly pace

The snapshot also retains a separate weekly window when the core bucket explicitly reports 10,080 minutes and a reset timestamp. This survives selection of a more constrained short window for the headline. We do not infer a week from a missing duration or label. If more than one explicit weekly window is returned, the most constrained is used conservatively.

`weekRemainingPercent = (resetsAt - now) / (7 * 86400) * 100`. Weekly remaining allowance at least equal to that fraction is on pace; a deficit up to 2 percentage points is near pace, and a larger deficit is using faster than an even-use budget. Zero allowance is exhausted. The approximate daily budget divides weekly allowance remaining by days left and is expressed as a percentage of the full weekly allowance, not of the remainder. It is omitted in the final day. No usage-history database or additional network requests are introduced.

Pace is unavailable after reset, before the inferred window start, with missing/invalid weekly data, if the sample is more than five minutes old, or if the clock predates the sample. This is a uniform-use planning guide; it does not predict actual future work or guarantee access. The menu explicitly labels the selected constraint (`7d`, `5h`, or another returned duration). Icon color describes that same constraint: red when exhausted, amber for faster weekly pace only when the selected window is weekly, otherwise neutral. Weekly pace stays separately labeled in the panel and tooltip. A selected short window keeps its reset next to that reading, while the weekly section explicitly shows weekly remaining allowance and reset. Pace arithmetic is available in hover help rather than occupying the main panel. Positive allowance below 1% is shown as `<1%`, avoiding a false exhaustion signal.

## Helper ownership and bounds

The coordinator allows one read at a time. Each read owns one Foundation `Process`, launches the chosen CLI without a shell, prepends the executable directory to `PATH` for npm's `/usr/bin/env node` shim, and uses existing CLI login. Discovery checks GUI/terminal PATH, usual local/Homebrew locations, the installed Codex app, and numeric-sorted nvm installations. The user may choose a CLI explicitly when discovery is unsuitable.

A read is limited to 15 seconds (configurable in the core client) and one MiB of cumulative stdout. Stderr is not accumulated. Newline JSON messages are parsed incrementally. SIGPIPE suppression applies only to the owned input descriptor, not app-wide signal handling.

Success, error, timeout, and cancellation all close input and stop the owned process. Normal termination is followed by a SIGKILL fallback after 0.5 seconds if necessary. The continuation resumes after the process is no longer running, with an explicit shutdown error if it remains running after two seconds. This prevents the next coordinated read from overlapping normal cleanup. App shutdown must cancel and await the read before exiting. Headroom never uses `killall`, a stored PID, or a process-group kill.

The installed npm wrapper forwards SIGTERM to its native child. Live probes observed all transient descendants disappear. A custom wrapper that ignores signals, backgrounds children, or changes the CLI contract is not covered by that evidence; use the actual supported Codex CLI, not an arbitrary launcher. A forced kill of a misbehaving wrapper cannot guarantee cleanup of independently detached descendants.

## Local verification (2026-09-21)

`swift test --filter Codex` passed 15 tests: eight parser cases and seven process tests. Process tests cover the initialize/initialized/read handshake, notification interleaving, sanitized RPC errors, one-MiB output rejection, already-cancelled reads, timeout, cancellation, and ten immediate closed-input exits without crashing the host. Timeout/cancellation tests verify that the owned PID is gone when the read returns.

Two consecutive read-only live probes against the existing login succeeded in 1.33 and 0.74 seconds before the final shutdown refinement. Both returned a valid weekly window and a reset time; no identity or raw provider response was recorded. At approximately 100 ms sampling, observed peak aggregate RSS of transient helper descendants was 155.1 MiB. Ten transient descendant PIDs were seen across both reads, and none remained one second after the probe. This is an observed peak, not a guaranteed maximum or a steady-state resource budget. CPU/energy impact and prolonged repeated polling remain unmeasured.

After adding shutdown waiting and per-pipe SIGPIPE hardening, two more live reads passed. These probes exercise the real CLI/login/response parser; fake-process tests additionally exercise failure paths without changing account state. Long-duration operation, network failures during a real request, and other CLI versions/platform architectures still require field validation.
