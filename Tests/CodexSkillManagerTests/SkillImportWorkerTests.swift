import Foundation
import Testing

@testable import CodexSkillManager

@Suite("Skill Import Worker Tests")
struct SkillImportWorkerTests {

    @Test("Creates symlink when useSymlink is true")
    func createsSymlinkWhenEnabled() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempRoot) }

        // Create source skill folder
        let sourceSkill = tempRoot.appendingPathComponent("source-skill")
        try fileManager.createDirectory(at: sourceSkill, withIntermediateDirectories: true)

        let skillMd = """
        ---
        name: Source Skill
        description: A source skill for symlink testing
        ---

        # Source Skill
        """
        try skillMd.write(
            to: sourceSkill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // Create destination directory
        let destinationRoot = tempRoot.appendingPathComponent("destination")
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        // Create import candidate
        let candidate = SkillImportWorker.ImportCandidatePayload(
            rootURL: sourceSkill,
            skillFileURL: sourceSkill.appendingPathComponent("SKILL.md"),
            skillName: "source-skill",
            markdown: skillMd,
            temporaryRoot: nil
        )

        let destination = SkillFileWorker.InstallDestination(
            rootURL: destinationRoot,
            storageKey: "test"
        )

        // Import with symlink
        let worker = SkillImportWorker()
        try await worker.importCandidate(
            candidate,
            destinations: [destination],
            shouldMove: false,
            useSymlink: true
        )

        // Verify symlink created
        let symlinkURL = destinationRoot.appendingPathComponent("source-skill")
        #expect(fileManager.fileExists(atPath: symlinkURL.path))

        let values = try symlinkURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        #expect(values.isSymbolicLink == true)

        // Verify symlink points to source
        let symlinkDestination = try fileManager.destinationOfSymbolicLink(atPath: symlinkURL.path)
        #expect(symlinkDestination == sourceSkill.path)

        // Verify source still exists
        #expect(fileManager.fileExists(atPath: sourceSkill.path))
    }

    @Test("Moves files when useSymlink is false and shouldMove is true")
    func movesWhenSymlinkDisabled() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempRoot) }

        // Create source skill folder
        let sourceSkill = tempRoot.appendingPathComponent("move-skill")
        try fileManager.createDirectory(at: sourceSkill, withIntermediateDirectories: true)

        let skillMd = "# Move Skill\n"
        try skillMd.write(
            to: sourceSkill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // Create destination directory
        let destinationRoot = tempRoot.appendingPathComponent("destination")
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        // Create import candidate
        let candidate = SkillImportWorker.ImportCandidatePayload(
            rootURL: sourceSkill,
            skillFileURL: sourceSkill.appendingPathComponent("SKILL.md"),
            skillName: "move-skill",
            markdown: skillMd,
            temporaryRoot: nil
        )

        let destination = SkillFileWorker.InstallDestination(
            rootURL: destinationRoot,
            storageKey: "test"
        )

        // Import with move
        let worker = SkillImportWorker()
        try await worker.importCandidate(
            candidate,
            destinations: [destination],
            shouldMove: true,
            useSymlink: false
        )

        // Verify files moved to destination
        let movedURL = destinationRoot.appendingPathComponent("move-skill")
        #expect(fileManager.fileExists(atPath: movedURL.path))

        // Verify it's a real directory, not a symlink
        let values = try? movedURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        #expect(values?.isSymbolicLink != true)

        // Verify source folder deleted
        #expect(!fileManager.fileExists(atPath: sourceSkill.path))
    }

    @Test("Copies files when useSymlink is false and shouldMove is false")
    func copiesWhenSymlinkDisabled() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempRoot) }

        // Create source skill folder
        let sourceSkill = tempRoot.appendingPathComponent("copy-skill")
        try fileManager.createDirectory(at: sourceSkill, withIntermediateDirectories: true)

        let skillMd = "# Copy Skill\n"
        try skillMd.write(
            to: sourceSkill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // Create destination directory
        let destinationRoot = tempRoot.appendingPathComponent("destination")
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        // Create import candidate
        let candidate = SkillImportWorker.ImportCandidatePayload(
            rootURL: sourceSkill,
            skillFileURL: sourceSkill.appendingPathComponent("SKILL.md"),
            skillName: "copy-skill",
            markdown: skillMd,
            temporaryRoot: nil
        )

        let destination = SkillFileWorker.InstallDestination(
            rootURL: destinationRoot,
            storageKey: "test"
        )

        // Import with copy
        let worker = SkillImportWorker()
        try await worker.importCandidate(
            candidate,
            destinations: [destination],
            shouldMove: false,
            useSymlink: false
        )

        // Verify files copied to destination
        let copiedURL = destinationRoot.appendingPathComponent("copy-skill")
        #expect(fileManager.fileExists(atPath: copiedURL.path))

        // Verify it's a real directory, not a symlink
        let values = try? copiedURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        #expect(values?.isSymbolicLink != true)

        // Verify source folder still exists
        #expect(fileManager.fileExists(atPath: sourceSkill.path))

        // Verify both have SKILL.md
        #expect(fileManager.fileExists(atPath: sourceSkill.appendingPathComponent("SKILL.md").path))
        #expect(fileManager.fileExists(atPath: copiedURL.appendingPathComponent("SKILL.md").path))
    }

    @Test("Creates multiple symlinks for multiple destinations")
    func multipleDestinationSymlinks() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempRoot) }

        // Create source skill folder
        let sourceSkill = tempRoot.appendingPathComponent("multi-skill")
        try fileManager.createDirectory(at: sourceSkill, withIntermediateDirectories: true)

        let skillMd = "# Multi Skill\n"
        try skillMd.write(
            to: sourceSkill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // Create multiple destination directories
        let destination1 = tempRoot.appendingPathComponent("dest1")
        let destination2 = tempRoot.appendingPathComponent("dest2")
        let destination3 = tempRoot.appendingPathComponent("dest3")

        try fileManager.createDirectory(at: destination1, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destination2, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destination3, withIntermediateDirectories: true)

        // Create import candidate
        let candidate = SkillImportWorker.ImportCandidatePayload(
            rootURL: sourceSkill,
            skillFileURL: sourceSkill.appendingPathComponent("SKILL.md"),
            skillName: "multi-skill",
            markdown: skillMd,
            temporaryRoot: nil
        )

        let destinations = [
            SkillFileWorker.InstallDestination(rootURL: destination1, storageKey: "test1"),
            SkillFileWorker.InstallDestination(rootURL: destination2, storageKey: "test2"),
            SkillFileWorker.InstallDestination(rootURL: destination3, storageKey: "test3")
        ]

        // Import with symlinks to multiple destinations
        let worker = SkillImportWorker()
        try await worker.importCandidate(
            candidate,
            destinations: destinations,
            shouldMove: false,
            useSymlink: true
        )

        // Verify all three symlinks created
        let symlink1 = destination1.appendingPathComponent("multi-skill")
        let symlink2 = destination2.appendingPathComponent("multi-skill")
        let symlink3 = destination3.appendingPathComponent("multi-skill")

        #expect(fileManager.fileExists(atPath: symlink1.path))
        #expect(fileManager.fileExists(atPath: symlink2.path))
        #expect(fileManager.fileExists(atPath: symlink3.path))

        // Verify all are symlinks
        let values1 = try symlink1.resourceValues(forKeys: [.isSymbolicLinkKey])
        let values2 = try symlink2.resourceValues(forKeys: [.isSymbolicLinkKey])
        let values3 = try symlink3.resourceValues(forKeys: [.isSymbolicLinkKey])

        #expect(values1.isSymbolicLink == true)
        #expect(values2.isSymbolicLink == true)
        #expect(values3.isSymbolicLink == true)

        // Verify all point to same source
        let dest1 = try fileManager.destinationOfSymbolicLink(atPath: symlink1.path)
        let dest2 = try fileManager.destinationOfSymbolicLink(atPath: symlink2.path)
        let dest3 = try fileManager.destinationOfSymbolicLink(atPath: symlink3.path)

        #expect(dest1 == sourceSkill.path)
        #expect(dest2 == sourceSkill.path)
        #expect(dest3 == sourceSkill.path)
    }

    @Test("Creates numbered version when skill already exists")
    func createsNumberedVersionWhenExists() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempRoot) }

        // Create two source directories for the same skill name
        let sourceV1 = tempRoot.appendingPathComponent("source-v1/my-skill")
        let sourceV2 = tempRoot.appendingPathComponent("source-v2/my-skill")

        try fileManager.createDirectory(at: sourceV1, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: sourceV2, withIntermediateDirectories: true)

        try "# Version 1\n".write(
            to: sourceV1.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Version 2\n".write(
            to: sourceV2.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // Create destination directory
        let destinationRoot = tempRoot.appendingPathComponent("destination")
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        let destination = SkillFileWorker.InstallDestination(
            rootURL: destinationRoot,
            storageKey: "test"
        )

        // Import version 1
        let candidateV1 = SkillImportWorker.ImportCandidatePayload(
            rootURL: sourceV1,
            skillFileURL: sourceV1.appendingPathComponent("SKILL.md"),
            skillName: "my-skill",
            markdown: "# Version 1\n",
            temporaryRoot: nil
        )

        let worker = SkillImportWorker()
        try await worker.importCandidate(
            candidateV1,
            destinations: [destination],
            shouldMove: false,
            useSymlink: true
        )

        // Verify first symlink created
        let symlink1 = destinationRoot.appendingPathComponent("my-skill")
        #expect(fileManager.fileExists(atPath: symlink1.path))

        // Import version 2 with same name (should create numbered version)
        let candidateV2 = SkillImportWorker.ImportCandidatePayload(
            rootURL: sourceV2,
            skillFileURL: sourceV2.appendingPathComponent("SKILL.md"),
            skillName: "my-skill",
            markdown: "# Version 2\n",
            temporaryRoot: nil
        )

        try await worker.importCandidate(
            candidateV2,
            destinations: [destination],
            shouldMove: false,
            useSymlink: true
        )

        // Verify numbered version created (my-skill-1)
        let symlink2 = destinationRoot.appendingPathComponent("my-skill-1")
        #expect(fileManager.fileExists(atPath: symlink2.path))

        // Verify both symlinks point to their respective sources
        let dest1 = try fileManager.destinationOfSymbolicLink(atPath: symlink1.path)
        let dest2 = try fileManager.destinationOfSymbolicLink(atPath: symlink2.path)

        #expect(dest1 == sourceV1.path)
        #expect(dest2 == sourceV2.path)
    }

    @Test("Validates folder correctly finds SKILL.md")
    func validateFolderFindsSkillMd() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempRoot) }

        // Create skill folder
        let skillFolder = tempRoot.appendingPathComponent("test-skill")
        try fileManager.createDirectory(at: skillFolder, withIntermediateDirectories: true)

        let skillMd = """
        ---
        name: Test Skill
        ---

        # Test Skill
        """
        try skillMd.write(
            to: skillFolder.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // Validate folder
        let worker = SkillImportWorker()
        let candidate = await worker.validateFolder(skillFolder)

        #expect(candidate != nil)
        #expect(candidate?.skillName == "test-skill")
        #expect(candidate?.rootURL == skillFolder)
        #expect(candidate?.markdown.contains("# Test Skill") == true)
    }

    @Test("Validates folder returns nil for invalid folder")
    func validateFolderReturnsNilForInvalid() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: tempRoot) }

        // Create folder without SKILL.md
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        // Validate folder
        let worker = SkillImportWorker()
        let candidate = await worker.validateFolder(tempRoot)

        #expect(candidate == nil)
    }
}
