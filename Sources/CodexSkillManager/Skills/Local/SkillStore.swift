import Foundation
import Observation

@MainActor
@Observable final class SkillStore {
    enum ListState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum DetailState: Equatable {
        case idle
        case loading
        case loaded
        case missing
        case failed(String)
    }

    var skills: [Skill] = []
    var listState: ListState = .idle
    var detailState: DetailState = .idle
    var referenceState: DetailState = .idle
    var selectedSkillID: Skill.ID?
    var selectedMarkdown: String = ""
    var selectedReferenceID: SkillReference.ID?
    var selectedReferenceMarkdown: String = ""

    var selectedSkill: Skill? {
        skills.first { $0.id == selectedSkillID }
    }

    var selectedReference: SkillReference? {
        guard let selectedSkill, let selectedReferenceID else { return nil }
        return selectedSkill.references.first { $0.id == selectedReferenceID }
    }

    func loadSkills() async {
        listState = .loading
        detailState = .idle
        referenceState = .idle

        let baseURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/skills/public")

        do {
            let items = try FileManager.default.contentsOfDirectory(
                at: baseURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            let skills = items.compactMap { url -> Skill? in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                guard values?.isDirectory == true else { return nil }

                let name = url.lastPathComponent
                let skillFileURL = url.appendingPathComponent("SKILL.md")
                let hasSkillFile = FileManager.default.fileExists(atPath: skillFileURL.path)

                guard hasSkillFile else { return nil }

                let markdown = (try? String(contentsOf: skillFileURL, encoding: .utf8)) ?? ""
                let metadata = parseMetadata(from: markdown)

                let references = referenceFiles(in: url.appendingPathComponent("references"))
                let referencesCount = references.count
                let assetsCount = countEntries(in: url.appendingPathComponent("assets"))
                let scriptsCount = countEntries(in: url.appendingPathComponent("scripts"))
                let templatesCount = countEntries(in: url.appendingPathComponent("templates"))

                return Skill(
                    id: name,
                    name: name,
                    displayName: formatTitle(metadata.name ?? name),
                    description: metadata.description ?? "No description available.",
                    folderURL: url,
                    skillMarkdownURL: skillFileURL,
                    references: references,
                    stats: SkillStats(
                        references: referencesCount,
                        assets: assetsCount,
                        scripts: scriptsCount,
                        templates: templatesCount
                    )
                )
            }

            self.skills = skills.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            listState = .loaded
            if let selectedSkillID,
               self.skills.contains(where: { $0.id == selectedSkillID }) == false {
                self.selectedSkillID = self.skills.first?.id
            } else if selectedSkillID == nil {
                selectedSkillID = self.skills.first?.id
            }

            await loadSelectedSkill()
        } catch {
            listState = .failed(error.localizedDescription)
        }
    }

    func loadSelectedSkill() async {
        guard let selectedSkill else {
            detailState = .idle
            selectedMarkdown = ""
            referenceState = .idle
            selectedReferenceID = nil
            selectedReferenceMarkdown = ""
            return
        }

        let skillURL = selectedSkill.skillMarkdownURL

        detailState = .loading
        referenceState = .idle
        selectedReferenceID = nil
        selectedReferenceMarkdown = ""

        do {
            let raw = try String(contentsOf: skillURL, encoding: .utf8)
            selectedMarkdown = stripFrontmatter(from: raw)
            detailState = .loaded
        } catch {
            detailState = .failed(error.localizedDescription)
            selectedMarkdown = ""
        }
    }

    func selectReference(_ reference: SkillReference) async {
        selectedReferenceID = reference.id
        await loadSelectedReference()
    }

    func loadSelectedReference() async {
        guard let selectedReference else {
            referenceState = .idle
            selectedReferenceMarkdown = ""
            return
        }

        referenceState = .loading

        do {
            let raw = try String(contentsOf: selectedReference.url, encoding: .utf8)
            selectedReferenceMarkdown = stripFrontmatter(from: raw)
            referenceState = .loaded
        } catch {
            referenceState = .failed(error.localizedDescription)
            selectedReferenceMarkdown = ""
        }
    }

    func deleteSkills(ids: [Skill.ID]) async {
        let fileManager = FileManager.default
        for id in ids {
            guard let skill = skills.first(where: { $0.id == id }) else { continue }
            try? fileManager.removeItem(at: skill.folderURL)
        }
        await loadSkills()
    }

    func isInstalled(slug: String) -> Bool {
        skills.contains { $0.name == slug }
    }

    func installRemoteSkill(_ skill: RemoteSkill, client: RemoteSkillClient) async throws {
        let fileManager = FileManager.default
        let zipURL = try await client.download(skill.slug, skill.latestVersion)

        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer {
            try? fileManager.removeItem(at: tempRoot)
            try? fileManager.removeItem(at: zipURL)
        }

        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try unzip(zipURL, to: tempRoot)

        guard let skillRoot = findSkillRoot(in: tempRoot) else {
            throw NSError(domain: "RemoteSkill", code: 1)
        }

        let destinationRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/skills/public")
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        let finalURL = destinationRoot.appendingPathComponent(skill.slug)
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }

        try fileManager.copyItem(at: skillRoot, to: finalURL)

        await loadSkills()
        selectedSkillID = skill.slug
    }

    private func unzip(_ url: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", url.path, destination.path]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(domain: "RemoteSkill", code: 2)
        }
    }

    private func findSkillRoot(in rootURL: URL) -> URL? {
        let fileManager = FileManager.default
        let directSkill = rootURL.appendingPathComponent("SKILL.md")
        if fileManager.fileExists(atPath: directSkill.path) {
            return rootURL
        }

        guard let children = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let candidateDirs = children.compactMap { url -> URL? in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { return nil }
            let skillFile = url.appendingPathComponent("SKILL.md")
            return fileManager.fileExists(atPath: skillFile.path) ? url : nil
        }

        if candidateDirs.count == 1 {
            return candidateDirs[0]
        }

        return nil
    }
}
