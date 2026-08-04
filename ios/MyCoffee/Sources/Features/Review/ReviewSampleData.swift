import Foundation

/// Fixture for `ReviewQueueEngine`'s default source — the real feed
/// (`GET /api/review`) isn't wired yet; see `status/ios-ux.md` for the
/// flagged `CoffeeStore`/`APIClient` gap. Built to exercise both queue-order
/// rules from PLAN.md §6.5: two batch groups of ≥8 (the brief's own quoted
/// `Etiopia → Ethiopia` and `DAK → DAK Coffee Roasters` examples) and a
/// handful of per-coffee singles with varying open-field counts, so "batches
/// first, then fewest-open-fields-first" is actually visible in the demo.
enum ReviewSampleData {
    static let tasks: [ReviewTask] = originCountryBatch + roasterBatch + singles

    // MARK: - Batch group A: origin country alias (11 tasks, ≥8 threshold)

    private static let originCountryBatch: [ReviewTask] = {
        // sample-001's own `rawCaption` ("Etiopia Nekisse, spalat") already
        // carries this exact typo (`Store/SampleData.swift`), so anchor one
        // real task to it rather than inventing every entry from scratch.
        var entries: [(photoId: String, coffeeId: String?, snippet: String)] = [
            ("sample-001", "sample-001", "Etiopia Nekisse, spalat"),
        ]
        let synthetic = [
            "Etiopia Yirgacheffe, washed", "Etiopia Guji natural", "Etiopia Sidamo Grade 1",
            "Etiopia Kochere, floral", "Etiopia Limu washed", "Etiopia Harrar natural",
            "Etiopia Gedeb, 1900masl", "Etiopia Konga, honey", "Etiopia Bench Maji",
            "Etiopia Nensebo washed",
        ]
        for (index, snippet) in synthetic.enumerated() {
            entries.append(("photo-eth-\(index)", nil, snippet))
        }
        return entries.enumerated().map { offset, entry in
            ReviewTask(
                id: 1000 + offset,
                coffeeId: entry.coffeeId,
                photoId: entry.photoId,
                field: .originCountry,
                rawValue: "Etiopia",
                reason: "no exact vocabulary match",
                rawSnippet: entry.snippet,
                candidates: [
                    ReviewCandidate(value: "Ethiopia", hint: nil),
                    ReviewCandidate(value: "Eritrea", hint: "2 other coffees"),
                ],
                createdAt: fixedDate(hoursAgo: 400 - offset)
            )
        }
    }()

    // MARK: - Batch group B: roaster alias (9 tasks, ≥8 threshold)

    private static let roasterBatch: [ReviewTask] = {
        let synthetic = [
            "DAK Ethiopia Nekisse", "DAK Kenya AA", "DAK Colombia Anaerobic", "DAK Guatemala Natural",
            "DAK Panama Geisha", "DAK Brazil Pulped Natural", "DAK Ethiopia Washed",
            "DAK Kenya Kayanza", "DAK Colombia Decaf",
        ]
        return synthetic.enumerated().map { offset, snippet in
            ReviewTask(
                id: 2000 + offset,
                coffeeId: nil,
                photoId: "photo-dak-\(offset)",
                field: .roaster,
                rawValue: "DAK",
                reason: "abbreviated on the bag",
                rawSnippet: snippet,
                candidates: [
                    ReviewCandidate(value: "DAK Coffee Roasters", hint: nil),
                ],
                createdAt: fixedDate(hoursAgo: 300 - offset)
            )
        }
    }()

    // MARK: - Singles: per-coffee groups, varying open-field counts

    private static let singles: [ReviewTask] = [
        // 1 open field — should surface first among the singles.
        ReviewTask(
            id: 3001, coffeeId: "sample-022", photoId: "photo-single-1",
            field: .profile, rawValue: "unspecified", reason: "no process stated on the bag",
            rawSnippet: "Brazil, natural sweetness, no process printed",
            candidates: [
                ReviewCandidate(value: "Natural", hint: nil),
                ReviewCandidate(value: "Washed", hint: "3 other coffees"),
            ],
            createdAt: fixedDate(hoursAgo: 48)
        ),

        // 2 open fields on one coffee.
        ReviewTask(
            id: 3002, coffeeId: "photo-multi-1", photoId: "photo-multi-1",
            field: .farm, rawValue: "El Injierto", reason: "fuzzy match below threshold",
            rawSnippet: "Finca El Injierto, Guatemala",
            candidates: [
                ReviewCandidate(value: "El Injerto", hint: nil),
            ],
            createdAt: fixedDate(hoursAgo: 40)
        ),
        ReviewTask(
            id: 3003, coffeeId: "photo-multi-1", photoId: "photo-multi-1",
            field: .altitude, rawValue: "1200-2400", reason: "range span 1200 m > 800 m threshold",
            rawSnippet: "Grown between 1200 and 2400 masl",
            candidates: [
                ReviewCandidate(value: "1200–1600 m", hint: nil),
                ReviewCandidate(value: "2000–2400 m", hint: "1 other coffee"),
            ],
            createdAt: fixedDate(hoursAgo: 39)
        ),

        // 3 open fields on another coffee — should surface last among singles.
        ReviewTask(
            id: 3004, coffeeId: "photo-multi-2", photoId: "photo-multi-2",
            field: .roasterCountry, rawValue: "Danemark", reason: "misspelled country name",
            rawSnippet: "Roasted in Danemark",
            candidates: [ReviewCandidate(value: "Denmark", hint: nil)],
            createdAt: fixedDate(hoursAgo: 30)
        ),
        ReviewTask(
            id: 3005, coffeeId: "photo-multi-2", photoId: "photo-multi-2",
            field: .weight, rawValue: "unclear", reason: "weight not legible in photo",
            rawSnippet: "Net wt. ___g (smudged)",
            candidates: [
                ReviewCandidate(value: "200 g", hint: nil),
                ReviewCandidate(value: "250 g", hint: "2 other coffees"),
            ],
            createdAt: fixedDate(hoursAgo: 29)
        ),
        ReviewTask(
            id: 3006, coffeeId: "photo-multi-2", photoId: "photo-multi-2",
            field: .price, rawValue: "unclear", reason: "price not legible in photo",
            rawSnippet: "€__.50",
            candidates: [
                ReviewCandidate(value: "€18.50", hint: nil),
                ReviewCandidate(value: "€19.50", hint: nil),
            ],
            createdAt: fixedDate(hoursAgo: 28)
        ),
    ]

    /// A fixed anchor rather than `Date()` so preview/demo ordering is stable
    /// across runs (there's no local Xcode here to eyeball it live).
    private static func fixedDate(hoursAgo: Int) -> Date {
        let anchor = DateComponents(calendar: .init(identifier: .gregorian), year: 2026, month: 8, day: 4, hour: 12).date!
        return anchor.addingTimeInterval(-Double(hoursAgo) * 3600)
    }
}
