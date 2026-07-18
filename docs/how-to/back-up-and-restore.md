# Back up and restore your data

Cadence is local-first: your data lives on the device, in the browser's
IndexedDB (web) or on-device storage (iOS). Nothing is synced anywhere.
That means **backups are your responsibility** — and on the web
especially, iOS Safari can evict local storage for sites you haven't
visited in a while.

## Export

**Settings → Data**:

- **Export JSON** — the full backup bundle: sessions, body log, protein,
  check-ins, milestones, programs (including mid-cycle state: pending
  peak grades and cycle-swap markers), tracked lifts, gyms, exercise
  library, settings. Open workouts are included and remain open after a
  restore.
- **Export CSV** — sessions flattened for spreadsheets. Not a backup;
  it can't be re-imported.

Export regularly — after a PR day is a good habit. The JSON is plain
text; keep it wherever you keep files you care about.

Cadence also keeps the last three **local recovery checkpoints** when the app
backgrounds and before imports/resets. You can create or restore one from
Settings. They are useful for undoing a wrong-but-valid import. They are not a
durable backup: Safari eviction, clearing site data, or deleting the iOS app
removes them too.

## Restore

**Settings → Data → Import** and pick a backup JSON.

- The bundle is the same format on both platforms: an iOS export
  restores into the web app and vice versa. This is also the way to
  move between devices.
- Current exports declare a schema version. Cadence still accepts legacy
  unversioned backups, but refuses a newer schema it doesn't understand
  before changing local data. Update the app, then retry the restore.
- Restore is transactional and per-section: only the sections present in
  the bundle are replaced (an old backup without `programs` leaves your
  programs alone), and a malformed file aborts without changing anything.
  Preflight reports the invalid field before storage is touched.
- Mid-cycle program state survives the round trip — pending peak
  results apply at the next rollover and cycle-scoped swaps still revert
  on schedule, whichever platform finishes the cycle.

One safety rule on restore: gym barcode images are only accepted as
inline image data, never as remote URLs, so a tampered backup can't make
the app phone home.

## Reset

**Settings → Reset all data** wipes the device's copy (the seed data
returns on next launch). The web app creates and preserves a local recovery
checkpoint first, but export JSON before resetting if the data matters.
