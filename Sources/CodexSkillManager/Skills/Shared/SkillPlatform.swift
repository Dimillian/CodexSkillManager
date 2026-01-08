import SwiftUI

enum SkillPlatform: String, CaseIterable, Identifiable, Hashable, Sendable {
    case codex = "Codex"
    case claude = "Claude Code"
    case opencode = "OpenCode"

    var id: String { rawValue }

    var storageKey: String {
        switch self {
        case .codex:
            return "codex"
        case .claude:
            return "claude"
        case .opencode:
            return "opencode"
        }
    }

    var rootURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .codex:
            return home.appendingPathComponent(".codex/skills/public")
        case .claude:
            return home.appendingPathComponent(".claude/skills")
        case .opencode:
            return home.appendingPathComponent(".config/opencode/skill")
        }
    }

    var description: String {
        switch self {
        case .codex:
            return "Install in \(rootURL.path)"
        case .claude:
            return "Install in \(rootURL.path)"
        case .opencode:
            return "Install in \(rootURL.path)"
        }
    }

    var badgeTint: Color {
        switch self {
        case .codex:
            return Color(red: 164.0 / 255.0, green: 97.0 / 255.0, blue: 212.0 / 255.0)
        case .claude:
            return Color(red: 217.0 / 255.0, green: 119.0 / 255.0, blue: 87.0 / 255.0)
        case .opencode:
            return Color(red: 76.0 / 255.0, green: 144.0 / 255.0, blue: 226.0 / 255.0)
        }
    }
}
