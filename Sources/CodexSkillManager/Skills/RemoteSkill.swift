import Foundation

struct RemoteSkill: Identifiable, Hashable {
    let id: String
    let slug: String
    let displayName: String
    let summary: String?
    let version: String?
}
