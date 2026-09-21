# Storage measurements and alert episodes

Headroom reads Foundation volume capacity metadata for the configured path. It does not total that directory, scan developer caches, read file contents, or delete anything. The initial path is the user's development directory when available; the app owns the final path selection.

## Definition

- `totalBytes`: `URLResourceValues.volumeTotalCapacity`.
- `freeBytes`: `URLResourceValues.volumeAvailableCapacity` (ordinary available capacity).
- `freeGB`: `freeBytes / 1,000,000,000`, decimal GB.
- `usedPercent`: `(totalBytes - freeBytes) / totalBytes * 100`.

A missing value, zero/nonpositive total, negative free value, or free value larger than total fails the read. A valid zero-free volume is 100% used. Each poll requests fresh resource values. Headroom does not use `volumeAvailableCapacityForImportantUsage` or advertise reclaimable/purgeable estimates as currently free space. See Apple's [ordinary available-capacity API](https://developer.apple.com/documentation/foundation/urlresourcevalues/volumeavailablecapacity).

On a shared APFS container, space consumed by sibling volumes also reduces available headroom. The percentage measures this shared capacity pressure, not solely the selected Data volume's own allocation. Apple describes [APFS shared capacity](https://support.apple.com/en-lb/guide/mac-help/sysp560a2952/mac). Volumes with quotas/reserves and external filesystems are not yet verified; this first local version targets this Mac's internal storage.

## Why the existing SwiftBar percentage differs

The inspected SwiftBar script calls `df -Pk` for the development path and uses its printed Capacity column. Apple's [df source](https://github.com/apple-oss-distributions/file_cmds/blob/main/df/df.c), `usedblks` and `prtstat`, obtains the volume's own consumed allocation through `ATTR_VOL_SPACEUSED`, then divides used blocks by **used + available**, rather than by the printed overall size. The POSIX mode rounds the result upward. This excludes other APFS volumes' used allocation from that percentage's denominator. Headroom deliberately uses total minus ordinary free to keep its percentage, free amount, and total internally consistent.

Read-only local comparison on 2026-09-21 at 05:34 UTC (back-to-back samples; capacity may change between calls):

| Value | Headroom/Foundation | Existing monitor input, `df -Pk` |
| --- | --- | --- |
| Total | 245,107,195,904 bytes | 239,362,496 × 1024 = 245,107,195,904 bytes |
| Available | 24,371,200,000 bytes = 24.3712 GB | 23,800,000 × 1024 = 24,371,200,000 bytes |
| Used numerator | 220,735,995,904 bytes, total minus free | 187,600,000 × 1024 = 192,102,400,000 bytes |
| Used percentage | 90.0569% | 89% printed |

Therefore Headroom may be amber while SwiftBar still reports 89%. This is a documented metric change, not an assertion that the two percentages match. Existing `df -h` also uses binary units (GiB); Headroom's GB is decimal. The screenshot's `23Gi` and a roughly 25 GB reading can describe the same space, with rounding and time differences.

## Alert contract

Colors use the current unrounded valid percentage: normal below 90%, amber from 90% to below 95%, red at 95% or above. Formatting must not be reused as the decision input.

`StorageAlertPolicy` persists an episode latch, recovery count, submission-attempt count, and earliest retry time. It reserves a first attempt at a valid red observation when permission allows it. The caller completes that reservation with success/failure; only an accepted submission latches the episode. Failed submissions permit up to three total attempts, separated by at least 60 seconds. A pending attempt prevents overlapping submissions. Retry count/delay survive restarts; pending execution does not. Old saved episode latches migrate unchanged to avoid duplicate alerts.

Two consecutive successful capacity samples strictly below 94% clear the episode and retry budget. Invalid samples break the recovery sequence. Recovery remains active with notifications disabled. A completion for an already-recovered episode is ignored using the attempt identifier.

The caller checks macOS authorization and alert settings before reserving an attempt. Off/blocked permission does not consume the budget. Failures appear beside storage; after three failed attempts the failure remains visible until recovery. There is no unbounded retry or automatic permission prompt. Successful submission means macOS accepted the notification request, not proof that Focus/presentation settings allowed a visible banner.

## Verification scope

Unit tests cover failed/successful submission outcomes, retry delay and cap, migration/restart, late callbacks, permission-readiness transitions, decimal units, full/invalid capacity, exact critical/recovery boundaries, threshold oscillation, interrupted recovery, invalid samples, restart persistence, and missing-path errors. Physical low-space notifications are not tested by filling the disk; injected sample states cover that path without consuming storage.

Recovery observations continue while notification delivery is disabled. A new critical episode does not consume its first alert while disabled; enabling alerts during that episode can notify once. Re-enabling an already-notified episode does not repeat it.
