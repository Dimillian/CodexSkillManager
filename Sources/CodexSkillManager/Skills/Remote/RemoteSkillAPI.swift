import Foundation

struct RemoteSkillAPI {
    struct SkillListResponse: Decodable {
        let items: [SkillListItem]
    }

    struct SkillListItem: Decodable {
        let slug: String
        let displayName: String
        let summary: String?
        let updatedAt: TimeInterval
        let latestVersion: LatestVersion?
    }

    struct LatestVersion: Decodable {
        let version: String
        let createdAt: TimeInterval
        let changelog: String
    }

    struct SearchResponse: Decodable {
        let results: [SearchResult]
    }

    struct SearchResult: Decodable {
        let slug: String?
        let displayName: String?
        let summary: String?
        let version: String?
        let updatedAt: TimeInterval?
    }
}
