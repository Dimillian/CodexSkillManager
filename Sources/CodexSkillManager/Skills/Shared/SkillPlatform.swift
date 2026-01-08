import SwiftUI

enum SkillPlatform: String, CaseIterable, Identifiable, Hashable, Sendable {
    case codex = "Codex"
    case claude = "Claude Code"

    var id: String { rawValue }

    var storageKey: String {
        switch self {
        case .codex:
            return "codex"
        case .claude:
            return "claude"
        }
    }

    var rootURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .codex:
            return home.appendingPathComponent(".codex/skills/public")
        case .claude:
            return home.appendingPathComponent(".claude/skills")
        }
    }

    var description: String {
        switch self {
        case .codex:
            return "Install in \(rootURL.path)"
        case .claude:
            return "Install in \(rootURL.path)"
        }
    }

    var badgeTint: Color {
        switch self {
        case .codex:
            return Color(red: 164.0 / 255.0, green: 97.0 / 255.0, blue: 212.0 / 255.0)
        case .claude:
            return Color(red: 217.0 / 255.0, green: 119.0 / 255.0, blue: 87.0 / 255.0)
        }
    }
}
