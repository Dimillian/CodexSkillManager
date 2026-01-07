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
    @State private var showingInstallSheet = false
    @State private var installTargets: Set<SkillPlatform> = [.codex]
    @State private var searchTask: Task<Void, Never>?

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
                    searchText: $searchText,
                    searchTask: $searchTask
                )
            )
            .toolbar(id: "main-toolbar") {
                toolbarContent()
            }
            .sheet(isPresented: $showingImport) {
                ImportSkillView()
                    .environment(store)
            }
            .sheet(isPresented: $showingInstallSheet) {
                if let skill = remoteStore.selectedSkill {
                    RemoteInstallSheet(
                        skill: skill,
                        installedTargets: store.installedPlatforms(for: skill.slug),
                        selection: $installTargets,
                        isInstalling: isDownloadingRemote,
                        onCancel: { showingInstallSheet = false },
                        onInstall: { Task { await downloadSelectedRemote() } }
                    )
                }
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
            installedPlatforms: installedPlatforms,
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
                    presentRemoteInstallSheet()
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
        let installedTargets = store.installedPlatforms(for: skill.slug)
        return installedTargets != Set(SkillPlatform.allCases)
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
        } else if didDownloadRemote || (remoteStore.selectedSkill.map {
            store.installedPlatforms(for: $0.slug) == Set(SkillPlatform.allCases)
        } ?? false) {
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

    private func presentRemoteInstallSheet() {
        guard let skill = remoteStore.selectedSkill else { return }
        installTargets = defaultInstallTargets(for: skill.slug)
        showingInstallSheet = true
    }

    private func downloadSelectedRemote() async {
        guard let skill = remoteStore.selectedSkill else { return }
        guard !installTargets.isEmpty else { return }
        isDownloadingRemote = true
        didDownloadRemote = false
        do {
            try await store.installRemoteSkill(
                skill,
                client: remoteStore.client,
                destinations: installTargets
            )
            didDownloadRemote = true
            showingInstallSheet = false
            try? await Task.sleep(for: .seconds(1.2))
        } catch {
            downloadErrorMessage = error.localizedDescription
        }
        isDownloadingRemote = false
        if didDownloadRemote {
            didDownloadRemote = false
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

    private var installedPlatforms: [String: Set<SkillPlatform>] {
        Dictionary(
            grouping: store.skills,
            by: { $0.name }
        ).mapValues { Set($0.map(\.platform)) }
    }

    private func defaultInstallTargets(for slug: String) -> Set<SkillPlatform> {
        let installed = store.installedPlatforms(for: slug)
        let missing = Set(SkillPlatform.allCases).subtracting(installed)
        return missing.isEmpty ? installed : missing
    }
}

private struct RemoteInstallSheet: View {
    let skill: RemoteSkill
    let installedTargets: Set<SkillPlatform>
    @Binding var selection: Set<SkillPlatform>
    let isInstalling: Bool
    let onCancel: () -> Void
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Install Skill")
                    .font(.title.bold())
                Text("Choose where to install \(skill.displayName).")
                    .foregroundStyle(.secondary)
            }

            InstallTargetSelectionView(
                installedTargets: installedTargets,
                selection: $selection
            )

            Spacer()

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Install") {
                    onInstall()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty || isInstalling)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 340)
    }
}

private struct SkillSplitLifecycleModifier: ViewModifier {
    @Environment(SkillStore.self) private var store
    @Environment(RemoteSkillStore.self) private var remoteStore

    @Binding var source: SkillSource
    @Binding var searchText: String
    @Binding var searchTask: Task<Void, Never>?

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
                    searchTask?.cancel()
                    searchTask = nil
                } else {
                    Task { await remoteStore.loadLatest() }
                }
            }
            .onChange(of: searchText) { _, newValue in
                guard source == .clawdhub else { return }
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await remoteStore.search(query: newValue)
                }
            }
    }
}
