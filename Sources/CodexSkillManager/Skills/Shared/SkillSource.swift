import Foundation

enum SkillSource: String, CaseIterable, Identifiable {
    case local = "Local"
    case molthub = "Molthub"

    var id: String { rawValue }
}
