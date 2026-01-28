import AppKit
import SwiftUI

struct SkillSplitView: View {
    @Environment(SkillStore.self) private var store
    @Environment(RemoteSkillStore.self) private var remoteStore

    @State private var searchText = ""
    @State private var showingImport = false
    @State private var showingAddPath = false
    @State private var source: SkillSource = .local
    @State private var downloadErrorMessage: String?
    @State private var isDownloadingRemote = false
    @State private var didDownloadRemote = false
    @State private var installSkill: RemoteSkill?
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
            .sheet(isPresented: $showingAddPath) {
                AddCustomPathView()
                    .environment(store)
            }
            .sheet(item: $installSkill) { skill in
                RemoteInstallSheet(
                    skill: skill,
                    installedTargets: store.installedPlatforms(for: skill.slug),
                    selection: $installTargets,
                    isInstalling: $isDownloadingRemote,
                    didInstall: $didDownloadRemote,
                    errorMessage: $downloadErrorMessage
                )
                .environment(store)
                .environment(remoteStore)
            }
            .alert("Download failed", isPresented: downloadErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(downloadErrorMessage ?? "Unable to download this skill.")
            }
            .searchable(
                text: $searchText,
                placement: .sidebar,
                prompt: source == .local ? "Filter skills" : "Search Molthub"
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
            onInstallRemoteSkill: { skill in
                presentRemoteInstallSheet(for: skill)
            },
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
        case .molthub:
            RemoteSkillDetailView()
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent() -> some CustomizableToolbarContent {
        if source == .molthub {
            ToolbarItem(id: "download") {
                Button {
                    presentRemoteInstallSheet()
                } label: {
                    downloadLabel
                }
                .labelStyle(.iconOnly)
                .disabled(isDownloadingRemote || !canDownloadRemoteSkill)
            }

            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed)
            }

        }

        ToolbarItem(id: "open") {
            openFolderItem
        }

        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed)
        }

        ToolbarItem(id: "add") {
            Menu {
                Button("Import Skill...") {
                    showingImport = true
                }
                Button("Add Custom Path...") {
                    showingAddPath = true
                }
            } label: {
                Label("Add", systemImage: "plus")
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

    @ViewBuilder
    private var openFolderItem: some View {
        if shouldShowOpenFolderMenu {
            Menu {
                ForEach(SkillPlatform.allCases) { platform in
                    if installedPlatformsForSelected.contains(platform) {
                        Button("Open \(platform.rawValue) Folder") {
                            openSelectedSkillFolder(platform: platform)
                        }
                    }
                }
            } label: {
                Label("Open Skill Folder", systemImage: "folder")
            }
            .labelStyle(.iconOnly)
            .disabled(source != .local)
        } else {
            Button {
                openSelectedSkillFolder(platform: nil)
            } label: {
                Label("Open Skill Folder", systemImage: "folder")
            }
            .labelStyle(.iconOnly)
            .disabled(source != .local)
        }
    }

    private var shouldShowOpenFolderMenu: Bool {
        installedPlatformsForSelected.count > 1
    }

    private var installedPlatformsForSelected: Set<SkillPlatform> {
        guard source == .local, let slug = store.selectedSkill?.name else { return [] }
        return store.installedPlatforms(for: slug)
    }

    private func openSelectedSkillFolder(platform: SkillPlatform?) {
        guard source == .local else { return }
        let fallbackURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/skills")
        let selected = store.selectedSkill
        let url: URL
        if let platform, let slug = selected?.name {
            if let selected, selected.platform == platform {
                url = selected.folderURL
            } else if let match = store.skills.first(where: {
                $0.name == slug && $0.platform == platform && $0.customPath == selected?.customPath
            }) {
                url = match.folderURL
            } else if let match = store.skills.first(where: { $0.name == slug && $0.platform == platform }) {
                url = match.folderURL
            } else {
                url = platform.rootURL.appendingPathComponent(slug)
            }
        } else {
            url = selected?.folderURL ?? fallbackURL
        }
        NSWorkspace.shared.open(url)
    }

    private func presentRemoteInstallSheet(for skill: RemoteSkill? = nil) {
        if let skill {
            remoteStore.selectedSkillID = skill.id
        }
        guard let resolved = skill ?? remoteStore.selectedSkill else { return }
        installTargets = defaultInstallTargets(for: resolved.slug)
        installSkill = resolved
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
        ).mapValues { Set($0.compactMap(\.platform)) }
    }

    private func defaultInstallTargets(for slug: String) -> Set<SkillPlatform> {
        let installed = store.installedPlatforms(for: slug)
        let missing = Set(SkillPlatform.allCases).subtracting(installed)
        return missing.isEmpty ? installed : missing
    }
}

private struct RemoteInstallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SkillStore.self) private var store
    @Environment(RemoteSkillStore.self) private var remoteStore

    let skill: RemoteSkill
    let installedTargets: Set<SkillPlatform>
    @Binding var selection: Set<SkillPlatform>
    @Binding var isInstalling: Bool
    @Binding var didInstall: Bool
    @Binding var errorMessage: String?

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
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Install") {
                    Task { await installSkill() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty || isInstalling)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 340)
    }

    private func installSkill() async {
        guard !selection.isEmpty else { return }
        isInstalling = true
        didInstall = false
        do {
            try await store.installRemoteSkill(
                skill,
                client: remoteStore.client,
                destinations: selection
            )
            didInstall = true
            dismiss()
            try? await Task.sleep(for: .seconds(1.2))
        } catch {
            errorMessage = error.localizedDescription
        }
        isInstalling = false
        if didInstall {
            didInstall = false
        }
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
                }
            }
            .onChange(of: searchText) { _, newValue in
                guard source == .molthub else { return }
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await remoteStore.search(query: newValue)
                }
            }
    }
}
