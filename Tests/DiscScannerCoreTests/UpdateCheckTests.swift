import Foundation
import Testing
@testable import DiscScannerCore

private func release(_ tag: String) -> ReleaseInfo {
    ReleaseInfo(tagName: tag, htmlURL: URL(string: "https://example.invalid")!)
}

@Test func versionsParseWithAndWithoutTheTagPrefix() throws {
    #expect(SemanticVersion("v1.2.3") == SemanticVersion(major: 1, minor: 2, patch: 3))
    #expect(SemanticVersion("1.2.3") == SemanticVersion(major: 1, minor: 2, patch: 3))
    // Missing components are zero, so a two-part tag still compares.
    #expect(SemanticVersion("1.2") == SemanticVersion(major: 1, minor: 2, patch: 0))
    #expect(SemanticVersion("2") == SemanticVersion(major: 2))
    #expect(SemanticVersion(" v1.0.0 ") == SemanticVersion(major: 1))
    // Build metadata carries no ordering.
    #expect(SemanticVersion("1.0.0+2026") == SemanticVersion(major: 1))
    #expect(SemanticVersion("1.1.0-beta.2")?.prerelease == ["beta", "2"])
}

@Test func nonsenseIsNotAVersion() {
    #expect(SemanticVersion("") == nil)
    #expect(SemanticVersion("release") == nil)
    #expect(SemanticVersion("1.2.3.4") == nil)
    #expect(SemanticVersion("1.x.0") == nil)
    #expect(SemanticVersion("-1.0.0") == nil)
}

@Test func versionsOrderByComponent() throws {
    let ascending = ["1.0.0", "1.0.1", "1.1.0", "1.10.0", "2.0.0"]
        .compactMap(SemanticVersion.init)
    #expect(ascending.count == 5)
    #expect(ascending == ascending.sorted())
}

@Test func prereleasesPrecedeTheirRelease() throws {
    let beta = try #require(SemanticVersion("1.1.0-beta.1"))
    let secondBeta = try #require(SemanticVersion("1.1.0-beta.2"))
    let alpha = try #require(SemanticVersion("1.1.0-alpha"))
    let final = try #require(SemanticVersion("1.1.0"))
    #expect(beta < final)
    #expect(alpha < beta)
    #expect(beta < secondBeta)
    // Numeric identifiers rank below alphanumeric ones.
    let numeric = try #require(SemanticVersion("1.0.0-1"))
    let alphanumeric = try #require(SemanticVersion("1.0.0-alpha"))
    #expect(numeric < alphanumeric)
    #expect(!(final < final))
}

@Test func aNewerTagIsAnUpdate() {
    #expect(UpdateCheck.evaluate(release: release("v1.0.2"), currentVersion: "1.0.1")
        == .updateAvailable(release("v1.0.2")))
    #expect(UpdateCheck.evaluate(release: release("v1.0.1"), currentVersion: "1.0.1")
        == .upToDate(release("v1.0.1")))
    // A local build ahead of the newest release is not an update either.
    #expect(UpdateCheck.evaluate(release: release("v1.0.1"), currentVersion: "1.1.0")
        == .upToDate(release("v1.0.1")))
}

@Test func anUnreadableVersionDecidesNothing() {
    #expect(UpdateCheck.evaluate(release: release("v1.0.2"), currentVersion: "")
        == .unknownVersion(release("v1.0.2")))
    #expect(UpdateCheck.evaluate(release: release("nightly"), currentVersion: "1.0.1")
        == .unknownVersion(release("nightly")))
}

@Test func aGitHubReleasePayloadDecodes() throws {
    // Trimmed from the real /releases/latest response — the unknown keys are
    // there on purpose: the payload has dozens and must not break decoding.
    let json = """
    {
      "url": "https://api.github.com/repos/NoiXdev/DiscScanner/releases/1",
      "html_url": "https://github.com/NoiXdev/DiscScanner/releases/tag/v1.0.1",
      "id": 1,
      "tag_name": "v1.0.1",
      "name": "v1.0.1",
      "draft": false,
      "prerelease": false,
      "published_at": "2026-09-01T08:30:23Z",
      "assets": [],
      "body": "* fix: never trap when the localization bundle is missing"
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let release = try decoder.decode(ReleaseInfo.self, from: Data(json.utf8))

    #expect(release.tagName == "v1.0.1")
    #expect(release.displayName == "v1.0.1")
    #expect(release.version == SemanticVersion(major: 1, minor: 0, patch: 1))
    #expect(release.htmlURL.absoluteString
        == "https://github.com/NoiXdev/DiscScanner/releases/tag/v1.0.1")
    #expect(release.publishedAt == Date(timeIntervalSince1970: 1_788_251_423))
}

@Test func aReleaseWithoutANameFallsBackToTheTag() {
    #expect(release("v2.0.0").displayName == "v2.0.0")
    #expect(ReleaseInfo(tagName: "v2.0.0", name: "", htmlURL: URL(string: "https://example.invalid")!)
        .displayName == "v2.0.0")
}
