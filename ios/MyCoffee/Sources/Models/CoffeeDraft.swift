import Foundation

/// The result of `POST /api/coffees/extract` (PLAN.md §6.8's Add Coffee
/// wizard, step 3) — one draft field per attribute the light ensemble could
/// resolve, keyed by the same client field name `editField`/`editFields`
/// already send (`"roaster"`, `"originCountry"`, …), so confirming a field and
/// saving the wizard is exactly a `CoffeeFieldEdit` list (#77 reuses the
/// review-queue field UI verbatim rather than inventing a second shape).
struct ExtractedDraft {
    /// Keyed by client field name, e.g. `fields["roaster"]`.
    let fields: [String: DraftField]
    let spentUsd: Double?

    init(dto: ExtractedDraftDTO) {
        fields = Dictionary(uniqueKeysWithValues: dto.fields.map { field, value in
            (field, DraftField(field: field, dto: value))
        })
        spentUsd = dto.spentUsd
    }
}

/// One extracted-but-unconfirmed field. `value`/`candidates` are raw strings
/// straight from the extraction ensemble, not resolved ids — exactly what a
/// confirmed SAVE sends back as a `CoffeeFieldEdit.value`.
struct DraftField: Identifiable, Hashable {
    var id: String { field }
    let field: String
    let value: String?
    let confidence: Double?
    let decision: String? // "absent" | "accepted" | "split"
    let candidates: [DraftCandidate]
    let evidence: String?

    /// The ensemble found nothing to fill in for this field — #77's confirm
    /// screen shouldn't show a confirm-mark for it at all.
    var isAbsent: Bool { value == nil && candidates.isEmpty }

    init(field: String, dto: ExtractedDraftFieldDTO) {
        self.field = field
        value = dto.value
        confidence = dto.confidence
        decision = dto.decision
        candidates = dto.candidates.map { DraftCandidate(value: $0.value) }
        evidence = dto.evidence
    }
}

struct DraftCandidate: Hashable {
    let value: String
}
