import SwiftUI

struct RemoteSkillDetailView: View {
    let skill: RemoteSkill?

    var body: some View {
        if let skill {
            VStack(alignment: .leading, spacing: 16) {
                Text(skill.displayName)
                    .font(.largeTitle.bold())
                if let summary = skill.summary {
                    Text(summary)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                if let version = skill.version {
                    Text("Latest version \(version)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .navigationTitle(skill.displayName)
            .navigationSubtitle("Clawdhub")
        } else {
            ContentUnavailableView("Select a skill",
                                   systemImage: "sparkles",
                                   description: Text("Pick a skill from Clawdhub."))
        }
    }
}
