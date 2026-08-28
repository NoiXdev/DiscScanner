import Testing
import Foundation
@testable import DiscScannerCore

struct FileDeleterTests {
    private func makeTempFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("deleter-\(UUID().uuidString).bin")
        try Data(repeating: 1, count: 1_024).write(to: url)
        return url
    }

    @Test func permanentlyDeletesAndReportsPerItemFailures() throws {
        let existing = try makeTempFile()
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)").path

        let result = FileDeleter.delete(paths: [existing.path, missing], method: .permanent)

        #expect(result.deletedPaths == [existing.path])
        #expect(result.failures.count == 1)
        #expect(result.failures[0].path == missing)
        #expect(!FileManager.default.fileExists(atPath: existing.path))
    }

    @Test func movesFilesToTrash() throws {
        // Actually moves the temp file to the user's Trash — acceptable side
        // effect for a local test run.
        let file = try makeTempFile()
        let result = FileDeleter.delete(paths: [file.path], method: .trash)
        #expect(result.deletedPaths == [file.path])
        #expect(result.failures.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func pruneRedundantDropsDescendantsOfSelectedAncestors() {
        let paths: Set<String> = ["/a", "/a/b", "/a/b/c", "/ax", "/c/d"]
        #expect(FileDeleter.pruneRedundant(paths) == ["/a", "/ax", "/c/d"])
    }
}
