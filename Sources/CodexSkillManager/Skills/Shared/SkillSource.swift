import Foundation

enum SkillSource: String, CaseIterable, Identifiable {
    case local = "Local"
    case clawhub = "Clawhub"

    var id: String { rawValue }
}
