import Foundation

struct RemoteSkillClient {
    var fetchLatest: (_ limit: Int) async throws -> [RemoteSkill]
    var search: (_ query: String, _ limit: Int) async throws -> [RemoteSkill]
    var download: (_ slug: String, _ version: String?) async throws -> URL
    var fetchDetail: (_ slug: String) async throws -> RemoteSkillOwner?
    var fetchLatestVersion: (_ slug: String) async throws -> String?
}

extension RemoteSkillClient {
    // Static URLSession configured with URLCache (10MB memory, 50MB disk)
    // Shared across all client instances for efficiency
    private static let session: URLSession = {
        let urlCache = URLCache(
            memoryCapacity: 10 * 1024 * 1024,
            diskCapacity: 50 * 1024 * 1024
        )
        let config = URLSessionConfiguration.default
        config.urlCache = urlCache
        return URLSession(configuration: config)
    }()

    static func live(baseURL: URL = URL(string: "https://clawhub.ai")!) -> RemoteSkillClient {
        let session = Self.session

        return RemoteSkillClient(
            fetchLatest: { limit in
                var components = URLComponents(
                    url: baseURL.appendingPathComponent("/api/v1/skills"),
                    resolvingAgainstBaseURL: false
                )
                components?.queryItems = [
                    URLQueryItem(name: "limit", value: String(limit)),
                ]
                guard let url = components?.url else {
                    throw URLError(.badURL)
                }

                let (data, response) = try await session.data(from: url)
                try validate(response: response)
                let decoded = try JSONDecoder().decode(RemoteSkillAPI.SkillListResponse.self, from: data)
                return decoded.items.map { item in
                    RemoteSkill(
                        id: item.slug,
                        slug: item.slug,
                        displayName: item.displayName,
                        summary: item.summary,
                        latestVersion: item.latestVersion?.version,
                        updatedAt: Date(timeIntervalSince1970: item.updatedAt / 1000),
                        downloads: item.stats?.downloads,
                        stars: item.stats?.stars
                    )
                }
            },
            search: { query, limit in
                var components = URLComponents(
                    url: baseURL.appendingPathComponent("/api/v1/search"),
                    resolvingAgainstBaseURL: false
                )
                components?.queryItems = [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "limit", value: String(limit)),
                ]
                guard let url = components?.url else {
                    throw URLError(.badURL)
                }

                let (data, response) = try await session.data(from: url)
                try validate(response: response)
                let decoded = try JSONDecoder().decode(RemoteSkillAPI.SearchResponse.self, from: data)
                return decoded.results.compactMap { result in
                    guard let slug = result.slug, let displayName = result.displayName else { return nil }
                    return RemoteSkill(
                        id: slug,
                        slug: slug,
                        displayName: displayName,
                        summary: result.summary,
                        latestVersion: result.version,
                        updatedAt: result.updatedAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                        downloads: nil,
                        stars: nil
                    )
                }
            },
            download: { slug, version in
                var components = URLComponents(
                    url: baseURL.appendingPathComponent("/api/v1/download"),
                    resolvingAgainstBaseURL: false
                )
                var queryItems = [URLQueryItem(name: "slug", value: slug)]
                if let version, !version.isEmpty {
                    queryItems.append(URLQueryItem(name: "version", value: version))
                } else {
                    queryItems.append(URLQueryItem(name: "tag", value: "latest"))
                }
                components?.queryItems = queryItems
                guard let url = components?.url else {
                    throw URLError(.badURL)
                }

                let (downloadURL, response) = try await session.download(from: url)
                try validate(response: response)
                return downloadURL
            },
            fetchDetail: { slug in
                var components = URLComponents(
                    url: baseURL.appendingPathComponent("/api/skill"),
                    resolvingAgainstBaseURL: false
                )
                components?.queryItems = [
                    URLQueryItem(name: "slug", value: slug),
                ]
                guard let url = components?.url else {
                    throw URLError(.badURL)
                }

                let (data, response) = try await session.data(from: url)
                try validate(response: response)
                let decoded = try JSONDecoder().decode(RemoteSkillAPI.SkillDetailResponse.self, from: data)
                guard let owner = decoded.owner else { return nil }
                return RemoteSkillOwner(
                    handle: owner.handle,
                    displayName: owner.displayName,
                    imageURL: owner.image
                )
            },
            fetchLatestVersion: { slug in
                let url = baseURL
                    .appendingPathComponent("/api/v1/skills")
                    .appendingPathComponent(slug)
                let (data, response) = try await session.data(from: url)
                try validate(response: response)
                let decoded = try JSONDecoder().decode(RemoteSkillAPI.SkillResponse.self, from: data)
                return decoded.latestVersion?.version
            }
        )
    }
}

private func validate(response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
    }
    guard (200..<300).contains(http.statusCode) else {
        throw URLError(.badServerResponse)
    }
}
