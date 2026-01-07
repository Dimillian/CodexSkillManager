import Foundation

enum SkillSource: String, CaseIterable, Identifiable {
    case local = "Local"
    case clawdhub = "Clawdhub"

    var id: String { rawValue }
}
