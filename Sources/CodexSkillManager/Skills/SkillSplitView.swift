import AppKit
import SwiftUI

struct SkillSplitView: View {
    @Environment(SkillStore.self) private var store
    @State private var searchText = ""
    @State private var showingImport = false
    @State private var source: SkillSource = .local
    @State private var remoteStore = RemoteSkillStore()

    private var filteredSkills: [Skill] {
        guard !searchText.isEmpty else { return store.skills }
        return store.skills.filter { skill in
            skill.displayName.localizedCaseInsensitiveContains(searchText)
                || skill.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            SkillListView(
                source: $source,
                localSkills: filteredSkills,
                localSelection: $store.selectedSkillID,
                remoteSkills: remoteStore.skills,
                remoteSelection: $remoteStore.selectedSkillID
            )
        } detail: {
            switch source {
            case .local:
                SkillDetailView()
            case .clawdhub:
                RemoteSkillDetailView(skill: remoteStore.selectedSkill)
            }
        }
        .task {
            await store.loadSkills()
        }
        .onChange(of: store.selectedSkillID) { _, _ in
            Task { await store.loadSelectedSkill() }
        }
        .onChange(of: source) { _, newValue in
            if newValue == .local {
                Task { await store.loadSelectedSkill() }
            }
        }
        .searchable(
            text: $searchText,
            placement: .sidebar,
            prompt: source == .local ? "Filter skills" : "Search Clawdhub"
        )
        .toolbar(id: "main-toolbar") {
            ToolbarItem(id: "open") {
                Button {
                    openSelectedSkillFolder()
                } label: {
                    Label("Open Skill Folder", systemImage: "folder")
                }
                .labelStyle(.iconOnly)
            }

            ToolbarSpacer(.fixed)

            ToolbarItem(id: "add") {
                Button {
                    showingImport = true
                } label: {
                    Label("Add Skill", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
            }
        }
        .sheet(isPresented: $showingImport) {
            ImportSkillView()
                .environment(store)
        }
    }

    private func openSelectedSkillFolder() {
        guard source == .local else { return }
        let url = store.selectedSkill?.folderURL
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/skills/public")
        NSWorkspace.shared.open(url)
    }
}
