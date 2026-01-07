import Foundation
import Observation

@MainActor
@Observable final class RemoteSkillStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum DetailState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var latestSkills: [RemoteSkill] = []
    var searchResults: [RemoteSkill] = []
    var latestState: LoadState = .idle
    var searchState: LoadState = .idle
    var selectedSkillID: RemoteSkill.ID?
    var detailMarkdown: String = ""
    var detailState: DetailState = .idle

    private let apiClient: RemoteSkillClient

    init(client: RemoteSkillClient) {
        self.apiClient = client
    }

    var client: RemoteSkillClient {
        apiClient
    }

    var selectedSkill: RemoteSkill? {
        (searchResults + latestSkills).first { $0.id == selectedSkillID }
    }

    func loadLatest(limit: Int = 12) async {
        latestState = .loading
        do {
            latestSkills = try await apiClient.fetchLatest(limit)
            latestState = .loaded
        } catch {
            latestState = .failed(error.localizedDescription)
        }
    }

    func search(query: String, limit: Int = 20) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            searchState = .idle
            return
        }

        searchState = .loading
        do {
            searchResults = try await apiClient.search(trimmed, limit)
            searchState = .loaded
        } catch {
            searchState = .failed(error.localizedDescription)
        }
    }

    func loadSelectedSkill() async {
        guard let skill = selectedSkill else {
            detailState = .idle
            detailMarkdown = ""
            return
        }

        detailState = .loading

        do {
            let zipURL = try await apiClient.download(skill.slug, skill.latestVersion)
            let fileManager = FileManager.default
            let tempRoot = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)

            try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            try unzip(zipURL, to: tempRoot)

            guard let skillRoot = findSkillRoot(in: tempRoot) else {
                throw NSError(domain: "RemoteSkill", code: 3)
            }

            let skillFileURL = skillRoot.appendingPathComponent("SKILL.md")
            let raw = try String(contentsOf: skillFileURL, encoding: .utf8)
            detailMarkdown = stripFrontmatter(from: raw)
            detailState = .loaded

            try? fileManager.removeItem(at: tempRoot)
            try? fileManager.removeItem(at: zipURL)
        } catch {
            detailState = .failed(error.localizedDescription)
            detailMarkdown = ""
        }
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
