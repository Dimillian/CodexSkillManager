import MarkdownUI
import SwiftUI

struct SkillMarkdownView: View {
    @Environment(SkillStore.self) private var store
    @Environment(RemoteSkillStore.self) private var remoteStore

    let skill: Skill
    let markdown: String

    @State private var needsPublish = false
    @State private var isOwned = false
    @State private var clawdhubOrigin: SkillFileWorker.ClawdhubOrigin?
    @State private var installedVersion: String?
    @State private var latestVersion: String?
    @State private var updateAvailable = false
    @State private var isUpdating = false
    @State private var isCheckingPublish = false
    @State private var showingPublishSheet = false
    @State private var isPublishing = false
    @State private var changelog = ""
    @State private var tags = "latest"
    @State private var bump: PublishBump = .patch
    @State private var publishErrorMessage: String?
    @State private var publishedVersion: String?
    @State private var cliStatus = SkillStore.CliStatus(
        isInstalled: false,
        isLoggedIn: false,
        username: nil,
        errorMessage: nil
    )
    @State private var isCheckingCli = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isOwned {
                    publishSection
                } else if clawdhubOrigin != nil {
                    installSection
                }
                Markdown(markdown)

                if !skill.references.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("References")
                            .font(.title2.bold())
                        ReferenceListView(references: skill.references)
                    }
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(skill.displayName)
        .navigationSubtitle(skill.folderPath)
        .task(id: skill.id) {
            await refreshPublishState()
        }
        .sheet(isPresented: $showingPublishSheet, onDismiss: {
            Task { await refreshPublishState() }
        }) {
            PublishSkillSheet(
                skill: skill,
                isPublishing: isPublishing,
                nextVersion: nextPublishVersion,
                bump: $bump,
                changelog: $changelog,
                tags: $tags,
                onCancel: { showingPublishSheet = false },
                onPublish: { Task { await publishSkill() } }
            )
        }
        .alert("Publish failed", isPresented: publishErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(publishErrorMessage ?? "Unable to publish this skill.")
        }
    }

    private var publishSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            publishHeader
            publishContent
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var publishHeader: some View {
        HStack {
            Text("Clawdhub")
                .font(.headline)
            Spacer()
            if isCheckingPublish || isCheckingCli {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
    }

    @ViewBuilder
    private var publishContent: some View {
        if isCheckingCli || isCheckingPublish {
            Text("Checking Clawdhub status…")
                .foregroundStyle(.secondary)
        } else if !cliStatus.isInstalled {
            publishInstallContent
        } else if !cliStatus.isLoggedIn {
            publishLoginContent
        } else {
            publishReadyContent
        }
    }

    private var publishInstallContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Install Bun to run the Clawdhub CLI.")
                .foregroundStyle(.secondary)

            Button("Install Bun") {
                openInstallDocs()
            }
            .buttonStyle(.bordered)
        }
    }

    private var publishLoginContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Run bunx clawdhub@latest login in Terminal, then check again.")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Copy login command") {
                    copyLoginCommand()
                }
                .buttonStyle(.bordered)

                Button("Check again") {
                    Task { await refreshPublishState() }
                }
                .buttonStyle(.bordered)
                .disabled(isCheckingCli)
            }
        }
    }

    private var publishReadyContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let username = cliStatus.username {
                Text("Signed in as \(username)")
                    .foregroundStyle(.secondary)
            }

            if let publishedVersion {
                Text("Latest version \(publishedVersion)")
                    .foregroundStyle(.secondary)
            } else {
                Text("First publish will be 1.0.0.")
                    .foregroundStyle(.secondary)
            }

            Text(needsPublish ? "Changes detected. Publish an update." : "No unpublished changes.")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Publish to Clawdhub") {
                    showingPublishSheet = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPublishing)

                if !needsPublish {
                    TagView(text: "Up to date", tint: .green)
                }
            }
        }
    }

    private var installSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            publishHeader
            installContent
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private var installContent: some View {
        if isCheckingPublish {
            Text("Checking Clawdhub status…")
                .foregroundStyle(.secondary)
        } else {
            if let installedVersion {
                Text("Installed version \(installedVersion)")
                    .foregroundStyle(.secondary)
            }
            if let latestVersion, updateAvailable {
                Text("Update available: v\(latestVersion)")
                    .foregroundStyle(.secondary)
            } else if latestVersion != nil {
                Text("You’re up to date.")
                    .foregroundStyle(.secondary)
            }

            if updateAvailable, let latestVersion {
                Button(isUpdating ? "Updating…" : "Update to v\(latestVersion)") {
                    Task { await updateSkill() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUpdating)
            }
        }
    }

    private func refreshPublishState() async {
        resetPublishState()
        let owned = store.isOwnedSkill(skill)
        isOwned = owned
        if owned {
            await refreshOwnedState()
        } else {
            await refreshInstalledState()
        }
    }

    private func refreshOwnedState() async {
        isCheckingCli = true
        cliStatus = await store.fetchClawdhubStatus()
        isCheckingCli = false
        if cliStatus.isInstalled && cliStatus.isLoggedIn {
            isCheckingPublish = true
            async let publishCheck = store.skillNeedsPublish(skill)
            async let versionCheck = fetchPublishedVersion()
            needsPublish = await publishCheck
            publishedVersion = await versionCheck
            isCheckingPublish = false
        }
    }

    private func refreshInstalledState() async {
        isCheckingPublish = true
        let origin = await store.clawdhubOrigin(for: skill)
        clawdhubOrigin = origin
        installedVersion = origin?.version
        guard let origin else {
            isCheckingPublish = false
            return
        }
        let latest = await fetchLatestVersion(slug: origin.slug)
        latestVersion = latest
        if let latest, let installed = installedVersion {
            updateAvailable = store.isNewerVersion(latest, than: installed)
        } else {
            updateAvailable = false
        }
        isCheckingPublish = false
    }

    private func resetPublishState() {
        isOwned = false
        needsPublish = false
        clawdhubOrigin = nil
        installedVersion = nil
        latestVersion = nil
        updateAvailable = false
        publishedVersion = nil
        cliStatus = SkillStore.CliStatus(
            isInstalled: false,
            isLoggedIn: false,
            username: nil,
            errorMessage: nil
        )
        isCheckingCli = false
        isCheckingPublish = false
    }

    private func publishSkill() async {
        isPublishing = true
        publishErrorMessage = nil
        do {
            let tagList = tags
                .split(separator: ",")
                .map { String($0) }
            try await store.publishSkill(
                skill,
                bump: bump,
                changelog: changelog,
                tags: tagList,
                publishedVersion: publishedVersion
            )
            needsPublish = false
            showingPublishSheet = false
            changelog = ""
        } catch {
            publishErrorMessage = error.localizedDescription
        }
        isPublishing = false
    }

    private func updateSkill() async {
        guard let origin = clawdhubOrigin else { return }
        isUpdating = true
        do {
            try await store.updateInstalledSkill(
                slug: origin.slug,
                version: latestVersion,
                client: remoteStore.client
            )
            await refreshInstalledState()
        } catch {
            publishErrorMessage = error.localizedDescription
        }
        isUpdating = false
    }

    private func copyLoginCommand() {
        let command = "bunx clawdhub@latest login"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
            pasteboard.setString(command, forType: .string)
    }

    private func openInstallDocs() {
        guard let url = URL(string: "https://bun.sh") else { return }
        NSWorkspace.shared.open(url)
    }

    private func fetchPublishedVersion() async -> String? {
        do {
            return try await remoteStore.client.fetchLatestVersion(skill.name)
        } catch {
            return nil
        }
    }

    private func fetchLatestVersion(slug: String) async -> String? {
        do {
            return try await remoteStore.client.fetchLatestVersion(slug)
        } catch {
            return nil
        }
    }

    private var nextPublishVersion: String {
        if let publishedVersion,
           let next = store.nextVersion(from: publishedVersion, bump: bump) {
            return next
        }
        return "1.0.0"
    }

    private var publishErrorBinding: Binding<Bool> {
        Binding(
            get: { publishErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    publishErrorMessage = nil
                }
            }
        )
    }
}
