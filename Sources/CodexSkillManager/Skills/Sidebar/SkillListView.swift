import SwiftUI

struct SkillListView: View {
    @Environment(SkillStore.self) private var store
    @Environment(RemoteSkillStore.self) private var remoteStore

    let localSkills: [Skill]
    let remoteLatestSkills: [RemoteSkill]
    let remoteSearchResults: [RemoteSkill]
    let remoteSearchState: RemoteSkillStore.LoadState
    let remoteLatestState: RemoteSkillStore.LoadState
    let remoteQuery: String
    let installedPlatforms: [String: Set<SkillPlatform>]
    let onInstallRemoteSkill: (RemoteSkill) -> Void

    @Binding var source: SkillSource
    @Binding var localSelection: Skill.ID?
    @Binding var remoteSelection: RemoteSkill.ID?

    private var groupedLocalSkills: [SkillStore.LocalSkillGroup] {
        store.groupedLocalSkills(from: localSkills)
    }

    var body: some View {
        List(selection: source == .local ? $localSelection : $remoteSelection) {
            if source == .local {
                SidebarHeaderView(
                    skillCount: groupedLocalSkills.count,
                    source: $source
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                localSectionContent()
            } else {
                SidebarHeaderView(
                    skillCount: remoteLatestSkills.count,
                    source: $source
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                if shouldShowSearchSection {
                    Section("Search Results") {
                        searchSectionContent
                    }
                }

                Section("Latest Drops") {
                    latestSectionContent
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        switch source {
                        case .local:
                            await store.loadSkills()
                        case .clawhub:
                            await remoteStore.loadLatest()
                        }
                    }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
            }
        }
    }

    private var shouldShowSearchSection: Bool {
        !remoteQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var searchSectionContent: some View {
        if remoteSearchState == .loading {
            HStack {
                ProgressView()
                Text("Searching…")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        } else if case let .failed(message) = remoteSearchState {
            Text("Search failed: \(message)")
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else if remoteSearchResults.isEmpty {
            Text("No results yet.")
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else {
            ForEach(remoteSearchResults) { skill in
                RemoteSkillRowView(
                    skill: skill,
                    installedTargets: installedPlatforms[skill.slug, default: []],
                    onInstall: { onInstallRemoteSkill(skill) }
                )
            }
        }
    }

    @ViewBuilder
    private var latestSectionContent: some View {
        if remoteLatestState == .loading {
            HStack {
                ProgressView()
                Text("Loading latest…")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        } else if case let .failed(message) = remoteLatestState {
            Text("Latest drops unavailable: \(message)")
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else if remoteLatestSkills.isEmpty {
            Text("No skills yet.")
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else {
            ForEach(remoteLatestSkills) { skill in
                RemoteSkillRowView(
                    skill: skill,
                    installedTargets: installedPlatforms[skill.slug, default: []],
                    onInstall: { onInstallRemoteSkill(skill) }
                )
            }
        }
    }

    @ViewBuilder
    private func localSectionContent() -> some View {
        // Group user directory skills separately to avoid custom-path slugs hiding them.
        let platformSkills = store.groupedPlatformSkills(from: localSkills)
        let mine = platformSkills.filter { store.isOwnedSkill($0.skill) }
        let clawhub = platformSkills.filter { !store.isOwnedSkill($0.skill) }

        let hasAnySkills = !mine.isEmpty || !clawhub.isEmpty || !store.customPaths.isEmpty

        if !hasAnySkills {
            Text("No skills yet.")
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else {
            // Platform skill sections
            Section("Mine") {
                localRows(for: mine)
            }
            Section("Clawhub") {
                localRows(for: clawhub)
            }

            // Custom path sections
            ForEach(store.customPaths) { customPath in
                let pathSkills = localSkills.filter { $0.customPath?.id == customPath.id }
                let grouped = store.groupedLocalSkills(from: pathSkills)

                Section {
                    if grouped.isEmpty {
                        Text("No skills in this folder.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        localRows(for: grouped)
                    }
                } header: {
                    CustomPathSectionHeader(customPath: customPath)
                }
            }
        }
    }

    @ViewBuilder
    private func localRows(for skills: [SkillStore.LocalSkillGroup]) -> some View {
        ForEach(skills) { skill in
            SkillRowView(
                skill: skill.skill,
                installedPlatforms: skill.installedPlatforms
            )
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task { await store.deleteSkills(ids: skill.deleteIDs) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .onDelete { offsets in
            let ids = offsets
                .filter { skills.indices.contains($0) }
                .flatMap { skills[$0].deleteIDs }
            Task { await store.deleteSkills(ids: ids) }
        }
    }
}
