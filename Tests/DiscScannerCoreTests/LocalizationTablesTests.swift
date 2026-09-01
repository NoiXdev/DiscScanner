import Foundation
import Testing

// The UI strings belong to the `DiscScanner` executable target, which has no
// test target of its own, so these read the tables straight from the source
// tree. They are the guard rail behind `L(_:)`: a key present in only one
// language shows English to German users, a format specifier that differs
// between the two crashes `String(format:)`, and a table that stops parsing
// takes every string with it.
private let resourcesURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // DiscScannerCoreTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // repository root
    .appendingPathComponent("Sources/DiscScanner/Resources")

/// Parses one `Localizable.strings` the same way Foundation does at runtime.
private func table(_ localization: String) throws -> [String: String] {
    let url = resourcesURL
        .appendingPathComponent("\(localization).lproj/Localizable.strings")
    let data = try Data(contentsOf: url)
    let plist = try PropertyListSerialization.propertyList(
        from: data, options: [], format: nil
    )
    return try #require(plist as? [String: String])
}

/// `%@`, `%d`, … in the order they appear.
private func formatSpecifiers(_ value: String) -> [String] {
    let characters = Array(value)
    var specifiers: [String] = []
    var index = 0
    while index + 1 < characters.count {
        if characters[index] == "%" {
            specifiers.append("%\(characters[index + 1])")
            index += 2
        } else {
            index += 1
        }
    }
    return specifiers
}

@Test func localizationsCoverTheSameKeys() throws {
    let english = try table("en")
    let german = try table("de")
    #expect(!english.isEmpty)
    #expect(Set(english.keys) == Set(german.keys))
}

@Test func translationsAreNotEmpty() throws {
    for localization in ["en", "de"] {
        for (key, value) in try table(localization) {
            #expect(
                !value.trimmingCharacters(in: .whitespaces).isEmpty,
                "\(localization): \(key) has no translation"
            )
        }
    }
}

@Test func translationsKeepTheirFormatSpecifiers() throws {
    let english = try table("en")
    let german = try table("de")
    for (key, value) in english {
        #expect(
            formatSpecifiers(value) == formatSpecifiers(german[key] ?? ""),
            "de: \(key) does not match the English format specifiers"
        )
    }
}
