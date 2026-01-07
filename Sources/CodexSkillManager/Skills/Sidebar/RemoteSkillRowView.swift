import SwiftUI

struct RemoteSkillRowView: View {
    let skill: RemoteSkill
    let isInstalled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(skill.displayName)
                .font(.headline)
                .foregroundStyle(.primary)

            if let summary = skill.summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                if let version = skill.latestVersion {
                    TagView(text: "v\(version)")
                }

                if isInstalled {
                    TagView(text: "Installed", tint: .green)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
