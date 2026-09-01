import Foundation

/// A version as a release tag carries it: `1.2.3`, `v1.2.3`, `1.1.0-beta.2`.
/// Missing components read as zero, so `1.2` and `1.2.0` are the same version.
public struct SemanticVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// Dot-separated pre-release identifiers; empty for a final release.
    public let prerelease: [String]

    public init(major: Int, minor: Int = 0, patch: Int = 0, prerelease: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    public init?(_ text: String) {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.first == "v" || body.first == "V" { body.removeFirst() }
        // Build metadata carries no ordering, so it is dropped.
        let withoutBuild = body.split(separator: "+", maxSplits: 1).first.map(String.init) ?? ""
        let parts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let core = parts.first, !core.isEmpty else { return nil }

        let numbers = core.split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count <= 3 else { return nil }
        var components: [Int] = []
        for number in numbers {
            guard let value = Int(number), value >= 0 else { return nil }
            components.append(value)
        }
        guard let major = components.first else { return nil }

        self.major = major
        self.minor = components.count > 1 ? components[1] : 0
        self.patch = components.count > 2 ? components[2] : 0
        if parts.count > 1, !parts[1].isEmpty {
            self.prerelease = parts[1].split(separator: ".").map(String.init)
        } else {
            self.prerelease = []
        }
    }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.isEmpty ? core : core + "-" + prerelease.joined(separator: ".")
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        // A pre-release precedes the release it leads up to.
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty
        }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            switch (Int(left), Int(right)) {
            case let (leftNumber?, rightNumber?): return leftNumber < rightNumber
            // Numeric identifiers rank below alphanumeric ones (semver 11.4).
            case (_?, nil): return true
            case (nil, _?): return false
            default: return left < right
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

/// The parts of a GitHub release the app has any use for.
public struct ReleaseInfo: Sendable, Equatable, Decodable {
    public let tagName: String
    public let name: String?
    public let htmlURL: URL
    public let publishedAt: Date?

    public var version: SemanticVersion? { SemanticVersion(tagName) }
    /// The release's own name where it has one, the tag otherwise.
    public var displayName: String {
        if let name, !name.isEmpty { return name }
        return tagName
    }

    public init(tagName: String, name: String? = nil, htmlURL: URL, publishedAt: Date? = nil) {
        self.tagName = tagName
        self.name = name
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }
}

public enum UpdateCheckError: Error, Sendable, Equatable {
    case invalidRepository
    /// 403 or 429: GitHub allows 60 unauthenticated calls an hour per address.
    case rateLimited
    /// No published release, or the repository is not reachable.
    case notFound
    case badStatus(Int)
    case invalidResponse
}

/// Asks GitHub what the newest release is and compares it with what is
/// running. The decision is a pure function on purpose — the network call is
/// the part that cannot be tested, so it holds no logic worth testing.
public enum UpdateCheck {
    public enum Outcome: Sendable, Equatable {
        case upToDate(ReleaseInfo)
        case updateAvailable(ReleaseInfo)
        /// The running version could not be read or parsed, so there is
        /// nothing to compare against.
        case unknownVersion(ReleaseInfo)

        public var release: ReleaseInfo {
            switch self {
            case .upToDate(let release), .updateAvailable(let release), .unknownVersion(let release):
                return release
            }
        }
    }

    public static func evaluate(release: ReleaseInfo, currentVersion: String) -> Outcome {
        guard
            let current = SemanticVersion(currentVersion),
            let latest = release.version
        else { return .unknownVersion(release) }
        return latest > current ? .updateAvailable(release) : .upToDate(release)
    }

    /// The newest published release. `/releases/latest` leaves out drafts and
    /// pre-releases, which is exactly what a stable user should be offered.
    public static func fetchLatestRelease(
        owner: String,
        repo: String,
        userAgent: String,
        session: URLSession = .shared
    ) async throws -> ReleaseInfo {
        guard
            !owner.isEmpty, !repo.isEmpty,
            let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")
        else { throw UpdateCheckError.invalidRepository }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        // GitHub rejects requests without one.
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }
        switch http.statusCode {
        case 200:
            break
        case 403, 429:
            throw UpdateCheckError.rateLimited
        case 404:
            throw UpdateCheckError.notFound
        default:
            throw UpdateCheckError.badStatus(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(ReleaseInfo.self, from: data)
        } catch {
            throw UpdateCheckError.invalidResponse
        }
    }
}
