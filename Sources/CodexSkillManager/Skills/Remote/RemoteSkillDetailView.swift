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
                case .loaded, .cachedRefreshing:
                    markdownView(for: skill)
                }
            }
            .navigationTitle(skill.displayName)
            .navigationSubtitle("Clawhub")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openClawhubURL(for: skill)
                    } label: {
                        Image(systemName: "globe")
                    }
                    .help("Open on Clawhub")
                }
            }
        } else {
            ContentUnavailableView(
                "Select a skill",
                systemImage: "sparkles",
                description: Text("Pick a skill from Clawhub.")
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
                    .textSelection(.enabled)
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
            HStack(spacing: 6) {
                if let owner = ownerDisplayName {
                    TagView(text: "By \(owner)")
                }
                if let version = skill.latestVersion {
                    TagView(text: "v\(version)")
                }
                if let statsText = statsText(for: skill) {
                    TagView(text: statsText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openClawhubURL(for skill: RemoteSkill) {
        guard let url = URL(string: "https://clawhub.ai/skills/\(skill.slug)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func statsText(for skill: RemoteSkill) -> String? {
        let downloads = skill.downloads ?? 0
        let stars = skill.stars ?? 0
        guard downloads > 0 || stars > 0 else { return nil }
        return "⬇ \(downloads)  ⭐ \(stars)"
    }

    private var ownerDisplayName: String? {
        guard let owner = store.detailOwner else { return nil }
        if let displayName = owner.displayName, !displayName.isEmpty {
            return displayName
        }
        if let handle = owner.handle, !handle.isEmpty {
            return "@\(handle)"
        }
        return nil
    }
}
