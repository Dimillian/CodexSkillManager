import Foundation
import Testing

@testable import CodexSkillManager

@Suite("Add Custom Path Workflow Tests")
struct AddCustomPathTests {

    @MainActor
    @Test("AddCustomPath does not modify source directory")
    func customPathDoesNotModifySource() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempRoot) }

        // Create a custom path directory with a skill
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let skillFolder = tempRoot.appendingPathComponent("test-skill")
        try fileManager.createDirectory(at: skillFolder, withIntermediateDirectories: true)

        let skillMd = """
        ---
        name: Test Skill
        description: A test skill for custom path testing
        ---

        # Test Skill
        This is a test skill.
        """
        try skillMd.write(
            to: skillFolder.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // Create a marker file to verify nothing is moved/copied/symlinked
        let markerFile = skillFolder.appendingPathComponent("marker.txt")
        try "original".write(to: markerFile, atomically: true, encoding: .utf8)

        // Add custom path using SkillStore
        let customPathStore = CustomPathStore()
        let store = SkillStore(customPathStore: customPathStore)

        try store.addCustomPath(tempRoot)

        // Verify source directory is unchanged
        #expect(fileManager.fileExists(atPath: skillFolder.path))
        #expect(fileManager.fileExists(atPath: markerFile.path))

        let markerContent = try String(contentsOf: markerFile, encoding: .utf8)
        #expect(markerContent == "original")

        // Verify no symlinks were created
        let values = try? skillFolder.resourceValues(forKeys: [.isSymbolicLinkKey])
        #expect(values?.isSymbolicLink != true)
    }

    @MainActor
    @Test("Custom path skills are discovered via scanning")
    func customPathSkillsDiscoveredByScanning() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempRoot) }

        // Create custom path with platform subdirectory structure
        // Custom paths scan for .claude/skills, .codex/skills, etc.
        let skillsDir = tempRoot.appendingPathComponent(".claude/skills")
        try fileManager.createDirectory(at: skillsDir, withIntermediateDirectories: true)

        for i in 1...3 {
            let skillFolder = skillsDir.appendingPathComponent("skill-\(i)")
            try fileManager.createDirectory(at: skillFolder, withIntermediateDirectories: true)

            let skillMd = """
            ---
            name: Skill \(i)
            description: Test skill number \(i)
            ---

            # Skill \(i)
            """
            try skillMd.write(
                to: skillFolder.appendingPathComponent("SKILL.md"),
                atomically: true,
                encoding: .utf8
            )
        }

        // Add custom path
        let customPathStore = CustomPathStore()
        let store = SkillStore(customPathStore: customPathStore)

        try store.addCustomPath(tempRoot)

        // Load skills (which triggers scanning)
        await store.loadSkills()

        // Verify skills were discovered
        let customPathSkills = store.skills.filter { $0.customPath != nil }
        #expect(customPathSkills.count == 3)

        // Verify skill names
        let skillNames = Set(customPathSkills.map { $0.name })
        #expect(skillNames.contains("skill-1"))
        #expect(skillNames.contains("skill-2"))
        #expect(skillNames.contains("skill-3"))
    }

    @MainActor
    @Test("Custom path does not create files in system directories")
    func customPathNoSystemDirectoryModification() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempRoot) }

        // Create custom path
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let skillFolder = tempRoot.appendingPathComponent("test-skill")
        try fileManager.createDirectory(at: skillFolder, withIntermediateDirectories: true)

        try "# Test\n".write(
            to: skillFolder.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // Get skill platform directories before adding custom path
        let platformRoots = SkillPlatform.allCases.flatMap { $0.rootURLs }
        var beforeContents: [URL: [String]] = [:]

        for rootURL in platformRoots {
            if fileManager.fileExists(atPath: rootURL.path) {
                let contents = (try? fileManager.contentsOfDirectory(
                    at: rootURL,
                    includingPropertiesForKeys: nil,
                    options: []
                )) ?? []
                beforeContents[rootURL] = contents.map { $0.lastPathComponent }
            }
        }

        // Add custom path
        let customPathStore = CustomPathStore()
        let store = SkillStore(customPathStore: customPathStore)

        try store.addCustomPath(tempRoot)
        await store.loadSkills()

        // Verify platform directories are unchanged
        for rootURL in platformRoots {
            if let beforeList = beforeContents[rootURL] {
                let afterContents = (try? fileManager.contentsOfDirectory(
                    at: rootURL,
                    includingPropertiesForKeys: nil,
                    options: []
                )) ?? []
                let afterList = afterContents.map { $0.lastPathComponent }

                #expect(Set(beforeList) == Set(afterList),
                       "Platform directory \(rootURL.path) was modified")
            }
        }
    }
}
