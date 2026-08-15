// Daily gym-tag stamp — which local day already auto-showed (or hand-opened)
// the membership barcode, so the hero button can compact and the
// first-launch-of-day auto-open fires once. The web mirror of the native
// @AppStorage(RootView.gymTagLastAutoDayKey) owner.
//
// This lives outside the views so the persistence layer (db.js) can clear the
// stamp when the store is wiped or replaced by an import without importing a
// view module: the stamp describes the pre-import install's day, and a
// restored phone must get its prominent tag (and auto-show) back. Every
// helper swallows storage failures (private mode) — the tag simply stays
// prominent.
export const GYM_TAG_DAY_KEY = "cadenceGymTagAutoDay";

export function gymTagShownOn(dayKey) {
  try { return localStorage.getItem(GYM_TAG_DAY_KEY) === dayKey; } catch { return false; }
}

export function markGymTagShown(dayKey) {
  try { localStorage.setItem(GYM_TAG_DAY_KEY, dayKey); } catch { /* noop */ }
}

export function clearGymTagDay() {
  try { localStorage.removeItem(GYM_TAG_DAY_KEY); } catch { /* noop */ }
}
