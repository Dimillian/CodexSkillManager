import MarkdownUI
import SwiftUI

struct RemoteSkillDetailView: View {
    @Environment(RemoteSkillStore.self) private var store

    var body: some View {
        if let skill = store.selectedSkill {
            Group {
                switch store.detailState {
                case .idle, .loading:
                    loadingView(for: skill)
                case .failed(let message):
                    errorView(for: skill, message: message)
                case .loaded:
                    markdownView(for: skill)
                }
            }
            .navigationTitle(skill.displayName)
            .navigationSubtitle("Clawdhub")
        } else {
            ContentUnavailableView(
                "Select a skill",
                systemImage: "sparkles",
                description: Text("Pick a skill from Clawdhub.")
            )
        }
    }

    private func loadingView(for skill: RemoteSkill) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView(for: skill)
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading SKILL.md…")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    private func errorView(for skill: RemoteSkill, message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView(for: skill)
            Text("Unable to load SKILL.md: \(message)")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    private func markdownView(for skill: RemoteSkill) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerView(for: skill)
                Markdown(store.detailMarkdown)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    private func headerView(for skill: RemoteSkill) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(skill.displayName)
                .font(.largeTitle.bold())
            if let summary = skill.summary {
                Text(summary)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            if let version = skill.latestVersion {
                Text("Latest version \(version)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
