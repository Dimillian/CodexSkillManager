import AppKit
import SwiftUI

struct SkillSplitView: View {
    @Environment(SkillStore.self) private var store
    @Environment(RemoteSkillStore.self) private var remoteStore

    @State private var searchText = ""
    @State private var showingImport = false
    @State private var source: SkillSource = .local
    @State private var downloadErrorMessage: String?
    @State private var isDownloadingRemote = false
    @State private var didDownloadRemote = false

    private var filteredSkills: [Skill] {
        guard !searchText.isEmpty else { return store.skills }
        return store.skills.filter { skill in
            skill.displayName.localizedCaseInsensitiveContains(searchText)
                || skill.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        splitView
            .modifier(
                SkillSplitLifecycleModifier(
                    source: $source,
                    searchText: $searchText
                )
            )
            .toolbar(id: "main-toolbar") {
                toolbarContent()
            }
            .sheet(isPresented: $showingImport) {
                ImportSkillView()
                    .environment(store)
            }
            .alert("Download failed", isPresented: downloadErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(downloadErrorMessage ?? "Unable to download this skill.")
            }
            .searchable(
                text: $searchText,
                placement: .sidebar,
                prompt: source == .local ? "Filter skills" : "Search Clawdhub"
            )
    }

    private var splitView: some View {
        NavigationSplitView {
            listView
        } detail: {
            detailView
        }
    }

    private var listView: some View {
        SkillListView(
            localSkills: filteredSkills,
            remoteLatestSkills: remoteStore.latestSkills,
            remoteSearchResults: remoteStore.searchResults,
            remoteSearchState: remoteStore.searchState,
            remoteLatestState: remoteStore.latestState,
            remoteQuery: searchText,
            installedSlugs: Set(store.skills.map(\.name)),
            source: $source,
            localSelection: localSelectionBinding,
            remoteSelection: remoteSelectionBinding
        )
    }

    @ViewBuilder
    private var detailView: some View {
        switch source {
        case .local:
            SkillDetailView()
        case .clawdhub:
            RemoteSkillDetailView()
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent() -> some CustomizableToolbarContent {
        if source == .clawdhub {
            ToolbarItem(id: "download") {
                Button {
                    downloadSelectedRemote()
                } label: {
                    downloadLabel
                }
                .labelStyle(.iconOnly)
                .disabled(isDownloadingRemote || !canDownloadRemoteSkill)
            }

            ToolbarSpacer(.fixed)
        }

        ToolbarItem(id: "open") {
            Button {
                openSelectedSkillFolder()
            } label: {
                Label("Open Skill Folder", systemImage: "folder")
            }
            .labelStyle(.iconOnly)
            .disabled(source != .local)
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

    private var canDownloadRemoteSkill: Bool {
        guard let skill = remoteStore.selectedSkill else { return false }
        return !store.isInstalled(slug: skill.slug)
    }

    private var localSelectionBinding: Binding<Skill.ID?> {
        Binding(
            get: { store.selectedSkillID },
            set: { store.selectedSkillID = $0 }
        )
    }

    private var remoteSelectionBinding: Binding<RemoteSkill.ID?> {
        Binding(
            get: { remoteStore.selectedSkillID },
            set: { remoteStore.selectedSkillID = $0 }
        )
    }

    @ViewBuilder
    private var downloadLabel: some View {
        if isDownloadingRemote {
            ProgressView()
        } else if didDownloadRemote || (remoteStore.selectedSkill.map { store.isInstalled(slug: $0.slug) } ?? false) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Image(systemName: "arrow.down.circle")
        }
    }

    private func openSelectedSkillFolder() {
        guard source == .local else { return }
        let url = store.selectedSkill?.folderURL
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/skills/public")
        NSWorkspace.shared.open(url)
    }

    private func downloadSelectedRemote() {
        guard let skill = remoteStore.selectedSkill else { return }
        isDownloadingRemote = true
        didDownloadRemote = false
        Task {
            do {
                try await store.installRemoteSkill(skill, client: remoteStore.client)
                didDownloadRemote = true
                try? await Task.sleep(for: .seconds(1.2))
            } catch {
                downloadErrorMessage = error.localizedDescription
            }
            isDownloadingRemote = false
            if didDownloadRemote {
                didDownloadRemote = false
            }
        }
    }

    private var downloadErrorBinding: Binding<Bool> {
        Binding(
            get: { downloadErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    downloadErrorMessage = nil
                }
            }
        )
    }
}

private struct SkillSplitLifecycleModifier: ViewModifier {
    @Environment(SkillStore.self) private var store
    @Environment(RemoteSkillStore.self) private var remoteStore

    @Binding var source: SkillSource
    @Binding var searchText: String

    func body(content: Content) -> some View {
        content
            .task {
                await store.loadSkills()
                await remoteStore.loadLatest()
            }
            .onChange(of: store.selectedSkillID) { _, _ in
                Task { await store.loadSelectedSkill() }
            }
            .onChange(of: remoteStore.selectedSkillID) { _, _ in
                Task { await remoteStore.loadSelectedSkill() }
            }
            .onChange(of: source) { _, newValue in
                if newValue == .local {
                    Task { await store.loadSelectedSkill() }
                } else {
                    Task { await remoteStore.loadLatest() }
                }
            }
            .onChange(of: searchText) { _, newValue in
                guard source == .clawdhub else { return }
                Task { await remoteStore.search(query: newValue) }
            }
    }
}
