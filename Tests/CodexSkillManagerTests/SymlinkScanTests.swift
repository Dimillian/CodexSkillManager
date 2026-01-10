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
}
