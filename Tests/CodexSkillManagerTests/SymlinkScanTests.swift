import Foundation
import Testing

@testable import CodexSkillManager

@Suite("Symlink Scan")
struct SymlinkScanTests {
    @Test("scanSkills follows directory symlinks")
    func scanSkillsFollowsDirectorySymlinks() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let realRoot = tempRoot.appendingPathComponent("real")
        let symlinkRoot = tempRoot.appendingPathComponent("link")

        try fileManager.createDirectory(at: realRoot, withIntermediateDirectories: true)

        let skillRoot = realRoot.appendingPathComponent("my-skill")
        try fileManager.createDirectory(at: skillRoot, withIntermediateDirectories: true)
        try "# My Skill\n".write(
            to: skillRoot.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        try fileManager.createSymbolicLink(at: symlinkRoot, withDestinationURL: realRoot)

        let worker = SkillFileWorker()
        let scanned = try await worker.scanSkills(at: symlinkRoot, storageKey: "test")

        #expect(scanned.count == 1)
        #expect(scanned.first?.name == "my-skill")
    }

    @MainActor
    @Test("Scanned symlinked skills have correct metadata")
    func symlinkSkillMetadataExtraction() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempRoot) }

        // Create real skill with frontmatter
        let realRoot = tempRoot.appendingPathComponent("real")
        let skillRoot = realRoot.appendingPathComponent("metadata-skill")
        try fileManager.createDirectory(at: skillRoot, withIntermediateDirectories: true)

        let skillMd = """
        ---
        name: Metadata Test Skill
        description: A skill for testing metadata extraction through symlinks
        ---

        # Metadata Test Skill
        This skill tests metadata extraction.
        """
        try skillMd.write(
            to: skillRoot.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // Create symlink to skill
        let symlinkRoot = tempRoot.appendingPathComponent("link")
        try fileManager.createDirectory(at: symlinkRoot, withIntermediateDirectories: true)
        let symlinkSkill = symlinkRoot.appendingPathComponent("metadata-skill")
        try fileManager.createSymbolicLink(at: symlinkSkill, withDestinationURL: skillRoot)

        // Scan through symlink
        let worker = SkillFileWorker()
        let scanned = try await worker.scanSkills(at: symlinkRoot, storageKey: "test")

        #expect(scanned.count == 1)
        #expect(scanned.first?.name == "metadata-skill")
        #expect(scanned.first?.displayName == "Metadata Test Skill")
        #expect(scanned.first?.description == "A skill for testing metadata extraction through symlinks")
    }

    @MainActor
    @Test("Symlinked skills count references correctly")
    func symlinkReferencesCounting() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempRoot) }

        // Create skill with references
        let skillRoot = tempRoot.appendingPathComponent("skill-with-refs")
        try fileManager.createDirectory(at: skillRoot, withIntermediateDirectories: true)

        let skillMd = "# Skill with References\n"
        try skillMd.write(
            to: skillRoot.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // Create references directory with markdown files
        let refsDir = skillRoot.appendingPathComponent("references")
        try fileManager.createDirectory(at: refsDir, withIntermediateDirectories: true)

        try "# Reference 1".write(to: refsDir.appendingPathComponent("ref1.md"), atomically: true, encoding: .utf8)
        try "# Reference 2".write(to: refsDir.appendingPathComponent("ref2.md"), atomically: true, encoding: .utf8)
        try "# Reference 3".write(to: refsDir.appendingPathComponent("ref3.md"), atomically: true, encoding: .utf8)

        // Create symlink to skill
        let symlinkRoot = tempRoot.appendingPathComponent("link")
        try fileManager.createDirectory(at: symlinkRoot, withIntermediateDirectories: true)
        let symlinkSkill = symlinkRoot.appendingPathComponent("skill-with-refs")
        try fileManager.createSymbolicLink(at: symlinkSkill, withDestinationURL: skillRoot)

        // Scan through symlink
        let worker = SkillFileWorker()
        let scanned = try await worker.scanSkills(at: symlinkRoot, storageKey: "test")

        #expect(scanned.count == 1)

        guard let skill = scanned.first else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "No skill found"])
        }

        #expect(skill.references.count == 3)

        let refNames = skill.references.map { $0.name }
        #expect(refNames.contains("Ref1"))
        #expect(refNames.contains("Ref2"))
        #expect(refNames.contains("Ref3"))
    }

    @MainActor
    @Test("Symlinked skills count assets/scripts/templates")
    func symlinkStatsCounting() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempRoot) }

        // Create skill with assets, scripts, and templates
        let skillRoot = tempRoot.appendingPathComponent("full-skill")
        try fileManager.createDirectory(at: skillRoot, withIntermediateDirectories: true)

        let skillMd = "# Full Skill\n"
        try skillMd.write(
            to: skillRoot.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // Create assets directory with files
        let assetsDir = skillRoot.appendingPathComponent("assets")
        try fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        try "asset1".write(to: assetsDir.appendingPathComponent("logo.png"), atomically: true, encoding: .utf8)
        try "asset2".write(to: assetsDir.appendingPathComponent("icon.svg"), atomically: true, encoding: .utf8)

        // Create scripts directory with files
        let scriptsDir = skillRoot.appendingPathComponent("scripts")
        try fileManager.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        try "#!/bin/bash\n".write(to: scriptsDir.appendingPathComponent("setup.sh"), atomically: true, encoding: .utf8)
        try "#!/bin/bash\n".write(to: scriptsDir.appendingPathComponent("build.sh"), atomically: true, encoding: .utf8)
        try "#!/bin/bash\n".write(to: scriptsDir.appendingPathComponent("deploy.sh"), atomically: true, encoding: .utf8)

        // Create templates directory with files
        let templatesDir = skillRoot.appendingPathComponent("templates")
        try fileManager.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        try "template1".write(to: templatesDir.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)

        // Create symlink to skill
        let symlinkRoot = tempRoot.appendingPathComponent("link")
        try fileManager.createDirectory(at: symlinkRoot, withIntermediateDirectories: true)
        let symlinkSkill = symlinkRoot.appendingPathComponent("full-skill")
        try fileManager.createSymbolicLink(at: symlinkSkill, withDestinationURL: skillRoot)

        // Scan through symlink
        let worker = SkillFileWorker()
        let scanned = try await worker.scanSkills(at: symlinkRoot, storageKey: "test")

        #expect(scanned.count == 1)

        guard let skill = scanned.first else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "No skill found"])
        }

        let stats = skill.stats
        let assets = stats.assets
        let scripts = stats.scripts
        let templates = stats.templates
        #expect(assets == 2)
        #expect(scripts == 3)
        #expect(templates == 1)
    }

    @MainActor
    @Test("Symlinked skills in nested structure")
    func symlinkInNestedStructure() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempRoot) }

        // Create real skill in nested directory
        let realRoot = tempRoot.appendingPathComponent("real/deeply/nested")
        try fileManager.createDirectory(at: realRoot, withIntermediateDirectories: true)

        let skillRoot = realRoot.appendingPathComponent("nested-skill")
        try fileManager.createDirectory(at: skillRoot, withIntermediateDirectories: true)

        let skillMd = """
        ---
        name: Nested Skill
        ---

        # Nested Skill
        """
        try skillMd.write(
            to: skillRoot.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // Create symlink in flat directory
        let linkRoot = tempRoot.appendingPathComponent("links")
        try fileManager.createDirectory(at: linkRoot, withIntermediateDirectories: true)
        let symlinkSkill = linkRoot.appendingPathComponent("nested-skill")
        try fileManager.createSymbolicLink(at: symlinkSkill, withDestinationURL: skillRoot)

        // Scan through symlink
        let worker = SkillFileWorker()
        let scanned = try await worker.scanSkills(at: linkRoot, storageKey: "test")

        #expect(scanned.count == 1)
        #expect(scanned.first?.name == "nested-skill")
        #expect(scanned.first?.displayName == "Nested Skill")
    }

    @MainActor
    @Test("Multiple symlinked skills are all discovered")
    func multipleSymlinkedSkills() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempRoot) }

        // Create multiple real skills
        let realRoot = tempRoot.appendingPathComponent("real")
        try fileManager.createDirectory(at: realRoot, withIntermediateDirectories: true)

        for i in 1...5 {
            let skillRoot = realRoot.appendingPathComponent("skill-\(i)")
            try fileManager.createDirectory(at: skillRoot, withIntermediateDirectories: true)
            try "# Skill \(i)\n".write(
                to: skillRoot.appendingPathComponent("SKILL.md"),
                atomically: true,
                encoding: .utf8
            )
        }

        // Create symlink directory with links to all skills
        let linkRoot = tempRoot.appendingPathComponent("links")
        try fileManager.createDirectory(at: linkRoot, withIntermediateDirectories: true)

        for i in 1...5 {
            let sourceSkill = realRoot.appendingPathComponent("skill-\(i)")
            let linkSkill = linkRoot.appendingPathComponent("skill-\(i)")
            try fileManager.createSymbolicLink(at: linkSkill, withDestinationURL: sourceSkill)
        }

        // Scan symlink directory
        let worker = SkillFileWorker()
        let scanned = try await worker.scanSkills(at: linkRoot, storageKey: "test")

        #expect(scanned.count == 5)

        let skillNames = Set(scanned.map { $0.name })
        for i in 1...5 {
            #expect(skillNames.contains("skill-\(i)"))
        }
    }
}
