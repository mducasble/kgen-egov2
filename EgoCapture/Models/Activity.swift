import Foundation

/// A recordable activity surfaced on the Activities screen. The selected title
/// is carried through the Briefing screen into the Recording session and ends
/// up in `environment.taskDescription` of the emitted `metadata_<code>.json`
/// (which the Lambda already maps to the MCAP task block).
struct Activity: Identifiable, Hashable {
    let id: String
    let title: String
    let desc: String
    let available: Bool
    let hours: Double
}

extension Activity {
    /// Hardcoded catalog. Hours are zeroed — the real values will come from
    /// the backend later (session aggregates by contributor + activity).
    static let catalog: [Activity] = [
        Activity(
            id: "washing_dishes",
            title: "Washing Dishes",
            desc: "Kitchen sink · dishes, pots and utensils. 2–5 minute clips, hands visible throughout.",
            available: true,
            hours: 0
        ),
        Activity(
            id: "ironing_clothes",
            title: "Ironing Clothes",
            desc: "Ironing board setup with garments. Focus on steady hand and full garment passes.",
            available: true,
            hours: 0
        ),
        Activity(
            id: "organizing_wardrobe",
            title: "Organizing Wardrobe",
            desc: "Folding, sorting and placing garments into drawers or shelves.",
            available: true,
            hours: 0
        ),
        Activity(
            id: "cleaning_pet_space",
            title: "Cleaning Pet Space",
            desc: "Litter, bed, food and water area cleanup — hands and tools visible.",
            available: false,
            hours: 0
        ),
        Activity(
            id: "cooking",
            title: "Cooking",
            desc: "Full preparation flow: prep, stove, plating. Multi-step with frequent hand-to-tool handoffs.",
            available: true,
            hours: 0
        )
    ]
}
