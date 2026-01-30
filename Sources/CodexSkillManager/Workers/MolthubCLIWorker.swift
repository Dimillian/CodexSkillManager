import Foundation

actor ClawhubCLIWorker {
    struct CliStatus: Sendable {
        let isInstalled: Bool
        let isLoggedIn: Bool
        let username: String?
        let errorMessage: String?
    }

    func fetchStatus() async -> CliStatus {
        guard let bunx = resolveBunxPath() else {
            return CliStatus(
                isInstalled: false,
                isLoggedIn: false,
                username: nil,
                errorMessage: "Bun is not installed."
            )
        }

        do {
            let whoami = try runProcess(
                executable: bunx,
                arguments: ["clawhub@latest", "whoami"]
            )
            let username = lastNonEmptyLine(from: whoami)
            return CliStatus(
                isInstalled: true,
                isLoggedIn: !username.isEmpty,
                username: username.isEmpty ? nil : username,
                errorMessage: nil
            )
        } catch {
            return CliStatus(
                isInstalled: true,
                isLoggedIn: false,
                username: nil,
                errorMessage: nil
            )
        }
    }

    func publishSkill(
        skillURL: URL,
        publishedVersion: String?,
        bump: PublishBump,
        changelog: String,
        tags: [String]
    ) throws {
        guard let bunx = resolveBunxPath() else {
            throw NSError(domain: "ClawhubPublish", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Bun is not installed."
            ])
        }

        let version = publishVersion(for: publishedVersion, bump: bump)
        let args = publishArguments(
            skillURL: skillURL,
            version: version,
            changelog: changelog,
            tags: tags
        )
        _ = try runProcess(
            executable: bunx,
            arguments: args
        )
    }

    nonisolated static func bumpVersion(_ current: String, bump: PublishBump) -> String? {
        let parts = current.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var major = parts[0]
        var minor = parts[1]
        var patch = parts[2]

        switch bump {
        case .major:
            major += 1
            minor = 0
            patch = 0
        case .minor:
            minor += 1
            patch = 0
        case .patch:
            patch += 1
        }

        return "\(major).\(minor).\(patch)"
    }

    private func publishArguments(
        skillURL: URL,
        version: String,
        changelog: String,
        tags: [String]
    ) -> [String] {
        var args = [
            "clawhub@latest",
            "publish",
            skillURL.path,
            "--version",
            version,
        ]

        if !changelog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(contentsOf: ["--changelog", changelog])
        }

        let cleanedTags = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !cleanedTags.isEmpty {
            args.append(contentsOf: ["--tags", cleanedTags.joined(separator: ",")])
        }

        return args
    }

    private func publishVersion(for latest: String?, bump: PublishBump) -> String {
        guard let latest, let next = Self.bumpVersion(latest, bump: bump) else {
            return "1.0.0"
        }
        return next
    }

    private func resolveBunxPath() -> String? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.bun/bin/bunx",
            "/opt/homebrew/bin/bunx",
            "/usr/local/bin/bunx",
            "/usr/bin/bunx"
        ]

        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return path
        }

        if let which = try? runProcess(executable: "/usr/bin/env", arguments: ["which", "bunx"]) {
            let trimmed = which.trimmingCharacters(in: .whitespacesAndNewlines)
            if fileManager.isExecutableFile(atPath: trimmed) {
                return trimmed
            }
        }

        return nil
    }

    private func lastNonEmptyLine(from output: String) -> String {
        let cleaned = output.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[mK]",
            with: "",
            options: .regularExpression
        )
        return cleaned
            .components(separatedBy: .newlines)
            .reversed()
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func runProcess(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = defaultEnvironment()

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        let combinedOutput = [output, errorOutput]
            .filter { !$0.isEmpty }
            .joined(separator: output.isEmpty || errorOutput.isEmpty ? "" : "\n")

        if process.terminationStatus != 0 {
            throw NSError(domain: "ClawhubPublish", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: errorOutput.isEmpty ? output : errorOutput
            ])
        }

        return combinedOutput
    }

    private func defaultEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        if environment["HOME"]?.isEmpty ?? true {
            environment["HOME"] = home
        }

        let standardPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        if let existing = environment["PATH"], !existing.isEmpty {
            let parts = existing.split(separator: ":").map(String.init)
            let missing = standardPaths.filter { !parts.contains($0) }
            if !missing.isEmpty {
                environment["PATH"] = parts.joined(separator: ":") + ":" + missing.joined(separator: ":")
            }
        } else {
            environment["PATH"] = standardPaths.joined(separator: ":")
        }

        if environment["BUN_INSTALL"]?.isEmpty ?? true {
            environment["BUN_INSTALL"] = "\(home)/.bun"
        }

        return environment
    }
}
