import MarkdownUI
import SwiftUI
import UniformTypeIdentifiers

private struct ImportCandidate {
    let rootURL: URL
    let skillFileURL: URL
    let skillName: String
    let markdown: String
    let temporaryRoot: URL?
}

struct ImportSkillView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SkillStore.self) private var store
    @State private var showingPicker = false
    @State private var candidate: ImportCandidate?
    @State private var status: Status = .idle
    @State private var errorMessage: String = ""
    @State private var installTargets: Set<SkillPlatform> = [.codex]
    @State private var useSymlink: Bool = true
    private let importWorker = SkillImportWorker()

    private enum Status {
        case idle
        case validating
        case valid
        case invalid
        case importing
        case imported
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
            Spacer()
            actions
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [.folder, .zip],
            allowsMultipleSelection: false
        ) { result in
            handlePick(result)
        }
        .onDisappear {
            cleanupCandidate()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Import Skill")
                .font(.title.bold())
            Text("Choose a skill folder or zip file, then pick where to install it.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .idle:
            emptyState
        case .validating:
            ProgressView("Validating…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .valid:
            preview
        case .invalid:
            invalidState
        case .importing:
            ProgressView("Importing…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .imported:
            successState
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Pick a folder or zip",
            systemImage: "tray.and.arrow.down",
            description: Text("We’ll verify it contains a SKILL.md and show a preview.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var invalidState: some View {
        ContentUnavailableView(
            "Not a valid skill",
            systemImage: "xmark.octagon",
            description: Text(errorMessage)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var successState: some View {
        ContentUnavailableView(
            "Imported",
            systemImage: "checkmark.seal",
            description: Text("The skill was added to your selected skills folders.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var preview: some View {
        guard let candidate else {
            return AnyView(EmptyView())
        }

        return AnyView(
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(candidate.skillName)
                            .font(.title2.bold())
                        Text(candidate.rootURL.path)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    InstallTargetSelectionView(
                        installedTargets: [],
                        selection: $installTargets
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Import using symlink", isOn: $useSymlink)
                            .disabled(candidate.temporaryRoot != nil)

                        if candidate.temporaryRoot != nil {
                            Text("Symlinks cannot be used with zip files (will be copied instead)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Markdown(candidate.markdown)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.06))
            )
        )
    }

    private var actions: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Choose…") {
                showingPicker = true
            }

            Button("Import") {
                Task { await importCandidate() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(status != .valid || installTargets.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func handlePick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            status = .invalid
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else {
                status = .idle
                return
            }
            Task { await validate(url: url) }
        }
    }

    private func validate(url: URL) async {
        status = .validating
        errorMessage = ""
        cleanupCandidate()

        let resolved = url.standardizedFileURL
        let fileValues = try? resolved.resourceValues(forKeys: [.isDirectoryKey])

        if fileValues?.isDirectory == true {
            await validateFolder(resolved)
        } else if resolved.pathExtension.lowercased() == "zip" {
            await validateZip(resolved)
        } else {
            status = .invalid
            errorMessage = "Select a folder or .zip file."
        }
    }

    private func validateFolder(_ folderURL: URL) async {
        if let payload = await importWorker.validateFolder(folderURL) {
            let candidate = ImportCandidate(
                rootURL: payload.rootURL,
                skillFileURL: payload.skillFileURL,
                skillName: formatTitle(payload.skillName),
                markdown: payload.markdown,
                temporaryRoot: payload.temporaryRoot
            )
            self.candidate = candidate
            status = .valid
        } else {
            status = .invalid
            errorMessage = "This folder doesn’t contain a SKILL.md file."
        }
    }

    private func validateZip(_ zipURL: URL) async {
        do {
            if let payload = try await importWorker.validateZip(zipURL) {
                let candidate = ImportCandidate(
                    rootURL: payload.rootURL,
                    skillFileURL: payload.skillFileURL,
                    skillName: formatTitle(payload.skillName),
                    markdown: payload.markdown,
                    temporaryRoot: payload.temporaryRoot
                )
                self.candidate = candidate
                status = .valid
            } else {
                status = .invalid
                errorMessage = "This zip doesn’t contain a SKILL.md file."
            }
        } catch {
            status = .invalid
            errorMessage = "Unable to read the zip file."
        }
    }

    private func importCandidate() async {
        guard let candidate else { return }
        guard !installTargets.isEmpty else { return }
        status = .importing

        do {
            let shouldMove = candidate.temporaryRoot == nil && installTargets.count == 1
            let destinations = installTargets.map {
                SkillFileWorker.InstallDestination(rootURL: $0.rootURL, storageKey: $0.storageKey)
            }
            let payload = SkillImportWorker.ImportCandidatePayload(
                rootURL: candidate.rootURL,
                skillFileURL: candidate.skillFileURL,
                skillName: candidate.skillName,
                markdown: candidate.markdown,
                temporaryRoot: candidate.temporaryRoot
            )
            try await importWorker.importCandidate(payload, destinations: destinations, shouldMove: shouldMove, useSymlink: useSymlink)

            await store.loadSkills()
            status = .imported
        } catch {
            status = .invalid
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func uniqueDestinationURL(base: URL) -> URL {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: base.path) {
            return base
        }

        let baseName = base.lastPathComponent
        let parent = base.deletingLastPathComponent()
        var index = 1
        while true {
            let candidate = parent.appendingPathComponent("\(baseName)-\(index)")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func cleanupCandidate() {
        if let temp = candidate?.temporaryRoot {
            Task { await importWorker.cleanupTemporaryRoot(temp) }
        }
        candidate = nil
    }
}
