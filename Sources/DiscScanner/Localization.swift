import Foundation

// Where the UI strings live depends on how the app was built:
//
//   * a packaged .app carries `en.lproj` / `de.lproj` in its own
//     `Contents/Resources` (scripts/package-app, `make app`),
//   * `swift run` only has SwiftPM's resource bundle
//     `DiscScanner_DiscScanner.bundle` next to the binary.
//
// Both are resolved by hand rather than through SwiftPM's generated
// `Bundle.module`: that accessor ends in `fatalError()` when the resource
// bundle is not exactly where it expects it, which is what killed 1.0.0 on
// the first `ContentView.body` evaluation (EXC_BREAKPOINT inside
// `NSBundle.module`, straight out of the app's first view). A localization
// that cannot be found must degrade to the untranslated key — never take
// the app down.

private final class BundleFinder {}

private let resourceBundleName = "DiscScanner_DiscScanner"

/// True when `bundle` actually carries the string table, so an empty
/// `.lproj` marker directory does not count as a hit.
private func hasStrings(_ bundle: Bundle) -> Bool {
    bundle.url(
        forResource: "Localizable",
        withExtension: "strings",
        subdirectory: nil,
        localization: "en"
    ) != nil
}

/// The bundle `L(_:)` reads from. Falls back to `Bundle.main`, whose
/// `NSLocalizedString` echoes the key back when the table is missing.
private let localizationBundle: Bundle = {
    // The main bundle first: in a packaged app that is where the .lproj
    // directories live, and it is also the bundle macOS consults when it
    // picks the app's language.
    if hasStrings(Bundle.main) { return Bundle.main }

    let directories = [
        Bundle.main.resourceURL,                        // inside an .app
        Bundle(for: BundleFinder.self).resourceURL,     // linked framework
        Bundle.main.bundleURL,                          // `swift run` layout
        Bundle.main.executableURL?.deletingLastPathComponent(),
    ]
    for case let directory? in directories {
        let url = directory.appendingPathComponent(resourceBundleName + ".bundle")
        if let bundle = Bundle(url: url), hasStrings(bundle) { return bundle }
    }
    return Bundle.main
}()

func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: localizationBundle, comment: "")
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(
        format: NSLocalizedString(key, bundle: localizationBundle, comment: ""),
        arguments: args
    )
}
