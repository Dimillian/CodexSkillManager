import Foundation

actor SkillImportWorker {
    struct ImportCandidatePayload: Sendable {
        let rootURL: URL
        let skillFileURL: URL
        let skillName: String
        let markdown: String
        let temporaryRoot: URL?
    }

    func validateFolder(_ folderURL: URL) -> ImportCandidatePayload? {
        guard let skillRoot = findSkillRoot(in: folderURL) else { return nil }
        let skillFileURL = skillRoot.appendingPathComponent("SKILL.md")
        guard let markdown = try? String(contentsOf: skillFileURL, encoding: .utf8) else { return nil }
        return ImportCandidatePayload(
            rootURL: skillRoot,
            skillFileURL: skillFileURL,
            skillName: skillRoot.lastPathComponent,
            markdown: markdown,
            temporaryRoot: nil
        )
    }

    func validateZip(_ zipURL: URL) throws -> ImportCandidatePayload? {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        do {
            try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            try unzip(zipURL, to: tempRoot)

            guard let skillRoot = findSkillRoot(in: tempRoot) else {
                try? fileManager.removeItem(at: tempRoot)
                return nil
            }

            let skillFileURL = skillRoot.appendingPathComponent("SKILL.md")
            guard let markdown = try? String(contentsOf: skillFileURL, encoding: .utf8) else {
                try? fileManager.removeItem(at: tempRoot)
                return nil
            }

            return ImportCandidatePayload(
                rootURL: skillRoot,
                skillFileURL: skillFileURL,
                skillName: skillRoot.lastPathComponent,
                markdown: markdown,
                temporaryRoot: tempRoot
            )
        } catch {
            try? fileManager.removeItem(at: tempRoot)
            throw error
        }
    }

    func importCandidate(
        _ candidate: ImportCandidatePayload,
        destinations: [SkillFileWorker.InstallDestination],
        shouldMove: Bool,
        useSymlink: Bool
    ) throws {
        let fileManager = FileManager.default

        for destination in destinations {
            let destinationRoot = destination.rootURL
            try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
            let finalURL = uniqueDestinationURL(
                base: destinationRoot.appendingPathComponent(candidate.rootURL.lastPathComponent)
            )
            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: finalURL)
            }

            if useSymlink {
                try fileManager.createSymbolicLink(at: finalURL, withDestinationURL: candidate.rootURL)
            } else if shouldMove {
                try fileManager.moveItem(at: candidate.rootURL, to: finalURL)
            } else {
                try fileManager.copyItem(at: candidate.rootURL, to: finalURL)
            }
        }
    }

    func cleanupTemporaryRoot(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func unzip(_ url: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", url.path, destination.path]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(domain: "ImportSkill", code: 1)
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
}
