import Foundation

/// Deterministic UUID-shaped identifiers (epic #155 Stage 2) — the exact
/// algorithm web `stableID` has minted program-slot ids with since V4:
/// FNV-1a (32-bit) over the seed, then 32 xorshift rounds emitting one hex
/// nibble each, assembled into a v4-shaped UUID (version nibble `4`, variant
/// nibble `a`; rounds 12 and 16 are discarded by construction). Both
/// implementations are pinned to shared byte-for-byte vectors
/// (StableIDTests / core.test.mjs), so a pre-v11 backup imported on either
/// client derives identical exercise ids.
///
/// JS parity notes, load-bearing: `Math.imul` is a truncating 32-bit
/// multiply (`&*` on UInt32); `<<`/`>>>` operate on the 32-bit pattern
/// (UInt32 shifts here); JS iterates code POINTS but hashes only
/// `charCodeAt(0)` — the lead UTF-16 unit — so astral characters contribute
/// their lead surrogate alone, mirrored below.
public enum StableID {
    public static func uuid(from seed: String) -> String {
        var state: UInt32 = 0x811c9dc5
        for scalar in seed.unicodeScalars {
            let unit: UInt32 = scalar.value <= 0xFFFF
                ? scalar.value
                : 0xD800 + ((scalar.value - 0x10000) >> 10)
            state ^= unit
            state = state &* 0x01000193
        }
        var hex = ""
        for _ in 0..<32 {
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            hex.append(String(state & 15, radix: 16))
        }
        let h = Array(hex)
        return String(h[0..<8]) + "-" + String(h[8..<12]) + "-4" + String(h[13..<16])
            + "-a" + String(h[17..<20]) + "-" + String(h[20..<32])
    }

    /// The legacy-ID namespace for exercises: seed/migration/import all
    /// derive a pre-v11 exercise's portable id from its exact name, so the
    /// same store contents produce the same ids on every client. Names are
    /// identity today — no trimming or case-folding beyond what importers
    /// already applied to the name itself.
    public static func exerciseLegacyID(name: String) -> String {
        uuid(from: "exercise:" + name)
    }
}
