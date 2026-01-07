import Foundation

struct SkillStats: Hashable {
    let references: Int
    let assets: Int
    let scripts: Int
    let templates: Int
}

struct SkillReference: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
}

struct Skill: Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String
    let description: String
    let platform: SkillPlatform
    let folderURL: URL
    let skillMarkdownURL: URL
    let references: [SkillReference]
    let stats: SkillStats

    var folderPath: String { folderURL.path }

    var tagLabels: [String] {
        var labels: [String] = []
        labels.append(label(for: stats.references, singular: "reference"))
        labels.append(label(for: stats.assets, singular: "asset"))
        labels.append(label(for: stats.scripts, singular: "script"))
        labels.append(label(for: stats.templates, singular: "template"))
        return labels.filter { !$0.isEmpty }
    }
}

private func label(for count: Int, singular: String) -> String {
    guard count > 0 else { return "" }
    let word = count == 1 ? singular : "\(singular)s"
    return "\(count) \(word)"
}
