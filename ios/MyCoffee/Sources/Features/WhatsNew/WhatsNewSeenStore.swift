import Foundation
import Combine

/// #200 — the one shared "which entries has Radu already ticked" store.
///
/// A singleton, not an `EnvironmentObject`, per the brief's *one shared store*
/// rule: both `WhatsNewView` and `SettingsSheet` observe it, and they'd drift
/// the moment two @StateObject copies existed. UserDefaults is the backing
/// because seen state is (a) tiny, (b) worth keeping across app relaunches,
/// (c) not worth a Keychain trip. Cross-device sync is a separate follow-up —
/// the brief specifies a server endpoint pair for that, but MyCoffee has no
/// per-user identity today (auth is one shared token), so the sync is really
/// phone↔iPad for one person and lands only once a second device exists to
/// justify the schema.
///
/// Entries in `/api/whatsnew` have no stable id, so keys are an FNV-1a hash
/// of `title\ndetail`. A re-worded entry keeps its check (same key); a
/// genuine retitle legitimately unchecks. Positional indexes would shift
/// every checkmark the moment a new item lands on top.
@MainActor
final class WhatsNewSeenStore: ObservableObject {
    static let shared = WhatsNewSeenStore()

    private let storageKey = "whatsnew.seen.v1"
    private let defaults: UserDefaults

    @Published private(set) var seen: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: storageKey) ?? []
        self.seen = Set(stored)
    }

    func isSeen(_ item: WhatsNewItemDTO) -> Bool {
        seen.contains(Self.key(for: item))
    }

    func toggle(_ item: WhatsNewItemDTO) {
        let k = Self.key(for: item)
        if seen.contains(k) {
            seen.remove(k)
        } else {
            seen.insert(k)
        }
        persist()
    }

    /// Only marks the entries you hand in — the caller decides whether that's
    /// only Live (the badge's rule) or Live + Plan (a "clear everything"
    /// gesture). The store does not fetch on its own.
    func markSeen(_ items: [WhatsNewItemDTO]) {
        for item in items { seen.insert(Self.key(for: item)) }
        persist()
    }

    func unseenCount(in items: [WhatsNewItemDTO]) -> Int {
        items.reduce(into: 0) { count, item in
            if !seen.contains(Self.key(for: item)) { count += 1 }
        }
    }

    private func persist() {
        defaults.set(Array(seen), forKey: storageKey)
    }

    /// FNV-1a over UTF-8 bytes of `title\ndetail`. Fast, stable, non-crypto —
    /// a collision here just means two entries share a checkbox, which costs
    /// far less than pulling in a crypto lib for a per-row identity.
    static func key(for item: WhatsNewItemDTO) -> String {
        let composed = "\(item.title)\n\(item.detail)"
        var hash: UInt32 = 0x811c9dc5
        for byte in composed.utf8 {
            hash ^= UInt32(byte)
            hash &*= 0x01000193
        }
        return String(hash, radix: 16)
    }
}
