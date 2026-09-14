import Foundation
import Combine

/// #200 — the one shared "which entries has Radu already ticked" store.
///
/// A singleton, not an `EnvironmentObject`, per the brief's *one shared store*
/// rule: both `WhatsNewView` and `SettingsSheet` observe it, and they'd drift
/// the moment two @StateObject copies existed. UserDefaults is the backing
/// because seen state is (a) tiny, (b) worth keeping across app relaunches,
/// (c) not worth a Keychain trip.
///
/// #201 adds cross-device sync on top, and UserDefaults stays the first read:
/// hydration is synchronous and never blocks a render, so the checkmarks are
/// right the instant the sheet opens and the server only ever corrects them.
/// `startSync` REPLACES the local set on a successful GET (the brief's
/// last-writer-wins-per-key rule); a failed POST logs and stays local, and the
/// next successful GET reconciles. There is no per-user identity — one shared
/// INGEST_TOKEN means one seen set — so this is genuinely phone↔iPad for one
/// person, which is exactly what Radu asked for ("I want exactly iPhone iPad
/// sync for what's new that's the whole purpose").
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

    @discardableResult
    func toggle(_ item: WhatsNewItemDTO) -> Bool {
        let k = Self.key(for: item)
        let nowSeen: Bool
        if seen.contains(k) {
            seen.remove(k)
            nowSeen = false
        } else {
            seen.insert(k)
            nowSeen = true
        }
        persist()
        push(key: k, seen: nowSeen)
        return nowSeen
    }

    /// #205(c): the inverse of a tap, for the trailing "Not done" swipe. Idempotent
    /// — swiping an already-unchecked card is a no-op rather than a re-check,
    /// which `toggle` would have made it.
    func markNotSeen(_ item: WhatsNewItemDTO) {
        let k = Self.key(for: item)
        guard seen.contains(k) else { return }
        seen.remove(k)
        persist()
        push(key: k, seen: false)
    }

    /// Only marks the entries you hand in — the caller decides whether that's
    /// only Live (the badge's rule) or Live + Plan (a "clear everything"
    /// gesture). The store does not fetch on its own.
    func markSeen(_ items: [WhatsNewItemDTO]) {
        let newlySeen = items.map(Self.key(for:)).filter { !seen.contains($0) }
        for key in newlySeen { seen.insert(key) }
        persist()
        for key in newlySeen { push(key: key, seen: true) }
    }

    func isSeen(key: String) -> Bool { seen.contains(key) }

    func unseenCount(in items: [WhatsNewItemDTO]) -> Int {
        items.reduce(into: 0) { count, item in
            if !seen.contains(Self.key(for: item)) { count += 1 }
        }
    }

    private func persist() {
        defaults.set(Array(seen), forKey: storageKey)
    }

    // ---- #201: cross-device sync ----

    /// Set once by whichever view is first on screen. Held weakly-ish as a
    /// plain optional rather than injected per call, because `toggle` is called
    /// from a card that has no business knowing about networking.
    private var config: AppConfig?

    /// Hydrate from the server. Call from a `.task` — `WhatsNewView`'s and
    /// `SettingsSheet`'s both, so the badge reflects the iPad's marks even
    /// before the sheet is opened.
    ///
    /// REPLACES the local set on success rather than unioning: a union could
    /// never un-check anything, so un-ticking an entry on the iPad would be
    /// silently undone by the phone's next sync. Last-writer-wins per key is
    /// what the brief asks for, and the server is the writer of record.
    /// A failure leaves the local set exactly as it was.
    func startSync(config: AppConfig) {
        self.config = config
        Task { [weak self] in
            guard let self else { return }
            guard let client = try? APIClient(config: config),
                  let remote = try? await client.whatsNewSeen() else { return }
            self.seen = Set(remote)
            self.persist()
        }
    }

    /// Fire-and-forget write-through. A failed POST is logged and left local —
    /// the next successful `startSync` reconciles — so a tap never blocks on
    /// the network and never fails visibly for something this small.
    private func push(key: String, seen isSeen: Bool) {
        guard let config else { return }
        Task {
            guard let client = try? APIClient(config: config) else { return }
            _ = try? await client.setWhatsNewSeen(key: key, seen: isSeen)
        }
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
