import CryptoKit
import Foundation

actor SkillFileWorker {
    struct InstallDestination: Sendable {
        let rootURL: URL
        let storageKey: String
    }

    struct ScannedSkillData: Sendable {
        let id: String
        let name: String
        let displayName: String
        let description: String
        let folderURL: URL
        let skillMarkdownURL: URL
        let references: [SkillReference]
        let stats: SkillStats
    }

    struct MolthubOrigin: Sendable {
        let slug: String
        let version: String?
    }

    func loadRawMarkdown(from zipURL: URL) throws -> String {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer {
            try? fileManager.removeItem(at: tempRoot)
            try? fileManager.removeItem(at: zipURL)
        }

        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try unzip(zipURL, to: tempRoot)

        guard let skillRoot = findSkillRoot(in: tempRoot) else {
            throw NSError(domain: "RemoteSkill", code: 3)
        }

        let skillFileURL = skillRoot.appendingPathComponent("SKILL.md")
        return try String(contentsOf: skillFileURL, encoding: .utf8)
    }

    func loadMarkdown(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func installRemoteSkill(
        zipURL: URL,
        slug: String,
        version: String?,
        destinations: [InstallDestination]
    ) throws -> String? {
        let fileManager = FileManager.default
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

        for destination in destinations {
            let destinationRoot = destination.rootURL
            try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

            let finalURL = destinationRoot.appendingPathComponent(slug)
            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: finalURL)
            }
            try fileManager.copyItem(at: skillRoot, to: finalURL)
            try writeMolthubOrigin(at: finalURL, slug: slug, version: version)
        }

        guard let preferred = destinations.first else { return nil }
        return "\(preferred.storageKey)-\(slug)"
    }

    func scanSkills(at baseURL: URL, storageKey: String) throws -> [ScannedSkillData] {
        let fileManager = FileManager.default

        // Directory symlinks can fail URL-based enumeration on macOS.
        let directoryURL = baseURL.resolvingSymlinksInPath()

        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }

        let items = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return items.compactMap { url -> ScannedSkillData? in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { return nil }

            let name = url.lastPathComponent
            let skillFileURL = url.appendingPathComponent("SKILL.md")
            guard fileManager.fileExists(atPath: skillFileURL.path) else { return nil }

            let markdown = (try? String(contentsOf: skillFileURL, encoding: .utf8)) ?? ""
            let metadata = parseMetadata(from: markdown)

            let references = referenceFiles(in: url.appendingPathComponent("references"))
            let stats = SkillStats(
                references: references.count,
                assets: countEntries(in: url.appendingPathComponent("assets")),
                scripts: countEntries(in: url.appendingPathComponent("scripts")),
                templates: countEntries(in: url.appendingPathComponent("templates"))
            )

            return ScannedSkillData(
                id: "\(storageKey)-\(name)",
                name: name,
                displayName: formatTitle(metadata.name ?? name),
                description: metadata.description ?? "No description available.",
                folderURL: url,
                skillMarkdownURL: skillFileURL,
                references: references,
                stats: stats
            )
        }
    }

    func computeSkillHash(for rootURL: URL) throws -> String {
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ""
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let path = fileURL.path
            if path.contains("/.git/") || path.contains("/.clawdhub/") || path.contains("/.molthub/") {
                continue
            }
            if fileURL.lastPathComponent == ".DS_Store" {
                continue
            }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            files.append(fileURL)
        }

        files.sort { $0.path < $1.path }

        var hasher = SHA256()
        for fileURL in files {
            guard let data = try? Data(contentsOf: fileURL),
                  String(data: data, encoding: .utf8) != nil else {
                continue
            }
            let relative = fileURL.path.replacingOccurrences(of: rootURL.path, with: "")
            hasher.update(data: Data(relative.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: data)
            hasher.update(data: Data([0]))
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func readMolthubOrigin(from skillRoot: URL) -> MolthubOrigin? {
        let originURLs = [
            skillRoot
                .appendingPathComponent(".molthub", isDirectory: true)
                .appendingPathComponent("origin.json"),
            skillRoot
                .appendingPathComponent(".clawdhub", isDirectory: true)
                .appendingPathComponent("origin.json")
        ]

        for originURL in originURLs {
            guard let data = try? Data(contentsOf: originURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let slug = json["slug"] as? String else {
                continue
            }

            let version = json["version"] as? String
            return MolthubOrigin(slug: slug, version: version)
        }

        return nil
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

    private func writeMolthubOrigin(at skillRoot: URL, slug: String, version: String?) throws {
        let originDir = skillRoot
            .appendingPathComponent(".molthub", isDirectory: true)
        try FileManager.default.createDirectory(at: originDir, withIntermediateDirectories: true)

        let originURL = originDir.appendingPathComponent("origin.json")
        let payload: [String: Any] = [
            "slug": slug,
            "version": version ?? "latest",
            "source": "molthub",
            "installedAt": Int(Date().timeIntervalSince1970)
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        try data.write(to: originURL, options: [.atomic])
    }

    private func parseMetadata(from markdown: String) -> SkillMetadata {
        let lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var name: String?
        var description: String?

        if lines.first?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) == "---" {
            var index = 1
            while index < lines.count {
                let line = String(lines[index])
                if line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) == "---" {
                    break
                }
                if let (key, value) = parseFrontmatterLine(line) {
                    if key == "name" {
                        name = value
                    } else if key == "description" {
                        description = value
                    }
                }
                index += 1
            }
        }

        if name == nil || description == nil {
            let fallback = parseMarkdownFallback(from: lines)
            name = name ?? fallback.name
            description = description ?? fallback.description
        }

        return SkillMetadata(name: name, description: description)
    }

    private func parseFrontmatterLine(_ line: String) -> (String, String)? {
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let rawValue = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return (key, value)
    }

    private func parseMarkdownFallback(from lines: [Substring]) -> SkillMetadata {
        var title: String?
        var description: String?

        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if title == nil, line.hasPrefix("# ") {
                title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if description == nil, !line.isEmpty, !line.hasPrefix("#") {
                description = String(line)
                break
            }
            index += 1
        }

        return SkillMetadata(name: title, description: description)
    }

    private func formatTitle(_ title: String) -> String {
        let normalized = title
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return normalized
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func countEntries(in url: URL) -> Int {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        return items.count
    }

    private func referenceFiles(in url: URL) -> [SkillReference] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let references = items.compactMap { fileURL -> SkillReference? in
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { return nil }
            guard fileURL.pathExtension.lowercased() == "md" else { return nil }

            let filename = fileURL.deletingPathExtension().lastPathComponent
            return SkillReference(
                id: fileURL.path,
                name: formatTitle(filename),
                url: fileURL
            )
        }

        return references.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
