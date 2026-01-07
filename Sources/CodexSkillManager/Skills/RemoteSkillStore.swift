import Foundation
import Observation

@MainActor
@Observable final class RemoteSkillStore {
    var skills: [RemoteSkill] = []
    var selectedSkillID: RemoteSkill.ID?

    var selectedSkill: RemoteSkill? {
        skills.first { $0.id == selectedSkillID }
    }
}
