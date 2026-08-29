// Shared cleanup helper for tests/smoke.test.mjs.
//
// The smoke suite shares one fake-indexeddb instance across ~120 sequential
// blocks. Every block that creates a store record is responsible for
// deleting it before the next block runs, or that record leaks into later
// blocks' `.all()`/count/"fresh install" assertions and corrupts an
// unrelated assertion hundreds of lines away. Hand-written
// `await db.<Store>.del(id)` calls at the tail of a block only run when
// every assertion above them completes without throwing — a thrown
// assertion (or a genuine bug in the code under test) skips the cleanup and
// leaves the record behind for the rest of the run.
//
// withCleanup(fn) removes that footgun. `fn` receives a `keep(storeApi, id)`
// callback; every store/id pair passed to `keep` is deleted in a `finally`
// block regardless of whether `fn` returns normally or throws. Deletion runs
// last-registered-first, matching the existing hand-written convention of
// deleting dependents (e.g. Sessions) before the records they reference
// (e.g. Programs).
//
// Usage:
//   await withCleanup(async (keep) => {
//     const id = keep(db.Sessions, await db.Sessions.save({ ... }));
//     ok(..., "...");
//   })();
//
// Not for the `db.importBundle(parsed)` restore pattern used elsewhere in
// the suite — that replaces the whole snapshot rather than deleting specific
// records, and is unaffected by this helper.
export function withCleanup(fn) {
  return async (...args) => {
    const tracked = [];
    const keep = (storeApi, id) => { tracked.push([storeApi, id]); return id; };
    try {
      return await fn(keep, ...args);
    } finally {
      for (let i = tracked.length - 1; i >= 0; i--) {
        const [storeApi, id] = tracked[i];
        await storeApi.del(id);
      }
    }
  };
}
