import Foundation
import Testing

// MARK: - Test Doubles (mirroring production types for testing)

/// Mirrors SkillPlatform from the main target for testing path patterns
enum TestSkillPlatform: String, CaseIterable {
    case codex = "Codex"
    case claude = "Claude Code"
    case opencode = "OpenCode"
    case copilot = "GitHub Copilot"

    var storageKey: String {
        switch self {
        case .codex: return "codex"
        case .claude: return "claude"
        case .opencode: return "opencode"
        case .copilot: return "copilot"
        }
    }

    var relativePath: String {
        relativePaths.first ?? ".codex/skills"
    }

    var relativePaths: [String] {
        switch self {
        case .codex: return [".codex/skills", ".codex/skills/public"]
        case .claude: return [".claude/skills"]
        case .opencode: return [".config/opencode/skill"]
        case .copilot: return [".copilot/skills"]
        }
    }

    var rootURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(relativePath)
    }

    func skillsURL(in baseURL: URL) -> URL {
        baseURL.appendingPathComponent(relativePath)
    }

    func skillsURLs(in baseURL: URL) -> [URL] {
        relativePaths.map { baseURL.appendingPathComponent($0) }
    }
}

/// Mirrors CustomSkillPath for testing
struct TestCustomSkillPath: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let displayName: String

    init(url: URL, displayName: String? = nil) {
        self.id = UUID()
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
    }

    var storageKey: String {
        "custom-\(id.uuidString.prefix(8).lowercased())"
    }
}

/// Mirrors Skill for testing path association
struct TestSkill: Identifiable, Hashable {
    let id: String
    let name: String
    let platform: TestSkillPlatform?
    let customPath: TestCustomSkillPath?
    let folderURL: URL

    var isFromCustomPath: Bool {
        customPath != nil
    }

    var isFromUserDirectory: Bool {
        customPath == nil && platform != nil
    }
}

// MARK: - Tests

@Suite("Skill Platform Path Patterns")
struct SkillPlatformPathTests {

    @Test("Platform relative paths are correct")
    func platformRelativePaths() {
        #expect(TestSkillPlatform.codex.relativePath == ".codex/skills")
        #expect(TestSkillPlatform.codex.relativePaths == [".codex/skills", ".codex/skills/public"])
        #expect(TestSkillPlatform.claude.relativePath == ".claude/skills")
        #expect(TestSkillPlatform.opencode.relativePath == ".config/opencode/skill")
        #expect(TestSkillPlatform.copilot.relativePath == ".copilot/skills")
    }

    @Test("Platform root URLs are based on home directory")
    func platformRootURLsUseHomeDirectory() {
        let home = FileManager.default.homeDirectoryForCurrentUser

        for platform in TestSkillPlatform.allCases {
            let expectedURL = home.appendingPathComponent(platform.relativePath)
            #expect(platform.rootURL == expectedURL)
            #expect(platform.rootURL.path.hasPrefix(home.path))
        }
    }

    @Test("Platform storage keys are unique and lowercase")
    func platformStorageKeysAreUnique() {
        let storageKeys = TestSkillPlatform.allCases.map(\.storageKey)
        let uniqueKeys = Set(storageKeys)

        #expect(uniqueKeys.count == TestSkillPlatform.allCases.count)

        for key in storageKeys {
            #expect(key == key.lowercased())
        }
    }

    @Test("skillsURL generates correct path within custom base")
    func skillsURLWithCustomBase() {
        let customBase = URL(fileURLWithPath: "/Users/test/projects/my-project")

        #expect(
            TestSkillPlatform.claude.skillsURL(in: customBase).path ==
            "/Users/test/projects/my-project/.claude/skills"
        )
        #expect(
            TestSkillPlatform.codex.skillsURL(in: customBase).path ==
            "/Users/test/projects/my-project/.codex/skills"
        )
        #expect(
            TestSkillPlatform.codex.skillsURLs(in: customBase).map(\.path) ==
            [
                "/Users/test/projects/my-project/.codex/skills",
                "/Users/test/projects/my-project/.codex/skills/public"
            ]
        )
        #expect(
            TestSkillPlatform.opencode.skillsURL(in: customBase).path ==
            "/Users/test/projects/my-project/.config/opencode/skill"
        )
        #expect(
            TestSkillPlatform.copilot.skillsURL(in: customBase).path ==
            "/Users/test/projects/my-project/.copilot/skills"
        )
    }
}

@Suite("Custom Path vs User Directory Differentiation")
struct PathDifferentiationTests {

    @Test("User directory skills have platform but no customPath")
    func userDirectorySkillsHavePlatformOnly() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let skill = TestSkill(
            id: "claude-my-skill",
            name: "my-skill",
            platform: .claude,
            customPath: nil,
            folderURL: home.appendingPathComponent(".claude/skills/my-skill")
        )

        #expect(skill.isFromUserDirectory == true)
        #expect(skill.isFromCustomPath == false)
        #expect(skill.platform == .claude)
        #expect(skill.customPath == nil)
    }

    @Test("Custom path skills have both platform and customPath")
    func customPathSkillsHaveBoth() {
        let customPath = TestCustomSkillPath(
            url: URL(fileURLWithPath: "/Users/test/projects/my-project")
        )
        let skill = TestSkill(
            id: "custom-abc123-claude-my-skill",
            name: "my-skill",
            platform: .claude,
            customPath: customPath,
            folderURL: URL(fileURLWithPath: "/Users/test/projects/my-project/.claude/skills/my-skill")
        )

        #expect(skill.isFromCustomPath == true)
        #expect(skill.isFromUserDirectory == false)
        #expect(skill.platform == .claude)
        #expect(skill.customPath != nil)
    }

    @Test("Same skill name can exist in both user directory and custom path")
    func sameSkillNameInDifferentLocations() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let customPath = TestCustomSkillPath(
            url: URL(fileURLWithPath: "/Users/test/projects/my-project")
        )

        let userSkill = TestSkill(
            id: "claude-my-skill",
            name: "my-skill",
            platform: .claude,
            customPath: nil,
            folderURL: home.appendingPathComponent(".claude/skills/my-skill")
        )

        let customSkill = TestSkill(
            id: "custom-abc123-claude-my-skill",
            name: "my-skill",
            platform: .claude,
            customPath: customPath,
            folderURL: URL(fileURLWithPath: "/Users/test/projects/my-project/.claude/skills/my-skill")
        )

        // Same name but different sources
        #expect(userSkill.name == customSkill.name)
        #expect(userSkill.id != customSkill.id)
        #expect(userSkill.isFromUserDirectory == true)
        #expect(customSkill.isFromCustomPath == true)
        #expect(userSkill.folderURL != customSkill.folderURL)
    }

    @Test("Custom path storage key is distinct from platform storage key")
    func storageKeysAreDistinct() {
        let customPath = TestCustomSkillPath(
            url: URL(fileURLWithPath: "/Users/test/projects/my-project")
        )

        // Custom path storage key should start with "custom-"
        #expect(customPath.storageKey.hasPrefix("custom-"))

        // Platform storage keys should not start with "custom-"
        for platform in TestSkillPlatform.allCases {
            #expect(!platform.storageKey.hasPrefix("custom-"))
        }
    }
}

@Suite("Platform Discovery in Custom Paths")
struct PlatformDiscoveryTests {

    @Test("All platform patterns are checked for custom paths")
    func allPlatformPatternsChecked() {
        let customBase = URL(fileURLWithPath: "/Users/test/projects/my-project")

        // Verify all platforms generate distinct paths
        let paths = TestSkillPlatform.allCases.map { $0.skillsURL(in: customBase).path }
        let uniquePaths = Set(paths)

        #expect(uniquePaths.count == TestSkillPlatform.allCases.count)
    }

    @Test("Custom path skill IDs include both custom path and platform identifiers")
    func customPathSkillIDsAreUnique() {
        let customPath = TestCustomSkillPath(
            url: URL(fileURLWithPath: "/Users/test/projects/my-project")
        )

        // Simulating storage key generation like in SkillStore.loadSkills()
        for platform in TestSkillPlatform.allCases {
            let combinedStorageKey = "\(customPath.storageKey)-\(platform.storageKey)"

            #expect(combinedStorageKey.contains("custom-"))
            #expect(combinedStorageKey.contains(platform.storageKey))
        }
    }

    @Test("User directory and custom path for same platform produce different root URLs")
    func differentRootsForSamePlatform() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let customBase = URL(fileURLWithPath: "/Users/test/projects/my-project")

        for platform in TestSkillPlatform.allCases {
            let userRootURL = platform.rootURL
            let customRootURL = platform.skillsURL(in: customBase)

            #expect(userRootURL != customRootURL)
            #expect(userRootURL.path.hasPrefix(home.path))
            #expect(customRootURL.path.hasPrefix(customBase.path))
        }
    }
}

@Suite("Skill Grouping and Ownership")
struct SkillGroupingTests {

    /// Simulates isOwnedSkill logic from SkillStore
    func isOwnedSkill(_ skill: TestSkill, hasClawhubOrigin: Bool) -> Bool {
        // Skills from custom paths are always considered "owned"
        if skill.customPath != nil {
            return true
        }
        // For user directory skills, check for clawhub origin
        return !hasClawhubOrigin
    }

    @Test("Custom path skills are always owned")
    func customPathSkillsAlwaysOwned() {
        let customPath = TestCustomSkillPath(
            url: URL(fileURLWithPath: "/Users/test/projects/my-project")
        )
        let skill = TestSkill(
            id: "custom-abc123-claude-my-skill",
            name: "my-skill",
            platform: .claude,
            customPath: customPath,
            folderURL: URL(fileURLWithPath: "/Users/test/projects/my-project/.claude/skills/my-skill")
        )

        // Even if it had a clawhub origin, custom path skills should be owned
        #expect(isOwnedSkill(skill, hasClawhubOrigin: false) == true)
        #expect(isOwnedSkill(skill, hasClawhubOrigin: true) == true)
    }

    @Test("User directory skills ownership depends on clawhub origin")
    func userDirectorySkillsOwnershipDependsOnOrigin() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let skill = TestSkill(
            id: "claude-my-skill",
            name: "my-skill",
            platform: .claude,
            customPath: nil,
            folderURL: home.appendingPathComponent(".claude/skills/my-skill")
        )

        #expect(isOwnedSkill(skill, hasClawhubOrigin: false) == true)  // Mine
        #expect(isOwnedSkill(skill, hasClawhubOrigin: true) == false)  // Clawhub
    }

    @Test("Skills group correctly by source type")
    func skillsGroupBySourceType() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let customPath = TestCustomSkillPath(
            url: URL(fileURLWithPath: "/Users/test/projects/my-project")
        )

        let skills = [
            // User directory skills
            TestSkill(id: "claude-skill1", name: "skill1", platform: .claude, customPath: nil,
                     folderURL: home.appendingPathComponent(".claude/skills/skill1")),
            TestSkill(id: "codex-skill2", name: "skill2", platform: .codex, customPath: nil,
                     folderURL: home.appendingPathComponent(".codex/skills/skill2")),

            // Custom path skills
            TestSkill(id: "custom-abc-claude-skill3", name: "skill3", platform: .claude, customPath: customPath,
                     folderURL: URL(fileURLWithPath: "/Users/test/projects/my-project/.claude/skills/skill3")),
            TestSkill(id: "custom-abc-codex-skill4", name: "skill4", platform: .codex, customPath: customPath,
                     folderURL: URL(fileURLWithPath: "/Users/test/projects/my-project/.codex/skills/skill4")),
        ]

        let userDirSkills = skills.filter { $0.isFromUserDirectory }
        let customPathSkills = skills.filter { $0.isFromCustomPath }

        #expect(userDirSkills.count == 2)
        #expect(customPathSkills.count == 2)

        // Verify they don't overlap
        let userDirIDs = Set(userDirSkills.map(\.id))
        let customPathIDs = Set(customPathSkills.map(\.id))
        #expect(userDirIDs.isDisjoint(with: customPathIDs))
    }
}

@Suite("Sidebar Platform Grouping")
struct SidebarPlatformGroupingTests {
    struct TestLocalSkillGroup {
        let skill: TestSkill
    }

    private func groupedLocalSkills(from filteredSkills: [TestSkill]) -> [TestLocalSkillGroup] {
        let grouped = Dictionary(grouping: filteredSkills, by: { $0.name })
        let preferredPlatformOrder: [TestSkillPlatform] = [.codex, .claude, .opencode, .copilot]

        return grouped.compactMap { _, filteredSkills in
            guard let preferredSelection = preferredPlatformOrder
                .compactMap({ platform in filteredSkills.first(where: { $0.platform == platform }) })
                .first ?? filteredSkills.first else {
                return nil
            }

            return TestLocalSkillGroup(skill: preferredSelection)
        }
        .sorted { lhs, rhs in
            lhs.skill.name.localizedCaseInsensitiveCompare(rhs.skill.name) == .orderedAscending
        }
    }

    @Test("Platform grouping keeps user-directory skills when custom paths share the slug")
    func platformGroupingIgnoresCustomPathSelection() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let customPath = TestCustomSkillPath(url: URL(fileURLWithPath: "/Users/test/projects/my-project"))

        let userDirSkill = TestSkill(
            id: "claude-my-skill",
            name: "my-skill",
            platform: .claude,
            customPath: nil,
            folderURL: home.appendingPathComponent(".claude/skills/my-skill")
        )
        let customPathSkill = TestSkill(
            id: "custom-codex-my-skill",
            name: "my-skill",
            platform: .codex,
            customPath: customPath,
            folderURL: URL(fileURLWithPath: "/Users/test/projects/my-project/.codex/skills/my-skill")
        )

        let groupedAll = groupedLocalSkills(from: [userDirSkill, customPathSkill])
        let oldPlatformGroups = groupedAll.filter { $0.skill.customPath == nil }

        #expect(oldPlatformGroups.isEmpty)

        let newPlatformGroups = groupedLocalSkills(from: [userDirSkill, customPathSkill].filter { $0.customPath == nil })

        #expect(newPlatformGroups.count == 1)
        #expect(newPlatformGroups.first?.skill.customPath == nil)
        #expect(newPlatformGroups.first?.skill.platform == .claude)
    }
}
