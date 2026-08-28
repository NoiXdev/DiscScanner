# DiscScanner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Native macOS app that scans a folder or volume recursively with live UI updates, shows large files/folders as a sortable tree and a treemap, and deletes items to Trash or permanently.

**Architecture:** SwiftPM package with a UI-free core library (`DiscScannerCore`: scan engine, treemap layout, deletion, tree pruning) and a SwiftUI executable (`DiscScanner`). The scanner traverses directories in parallel on a concurrent GCD queue, aggregates sizes bottom-up behind a lock, and publishes immutable snapshot trees + progress ~4×/second through an `AsyncStream`. A Makefile bundles the release binary into `DiscScanner.app`.

**Tech Stack:** Swift 6 toolchain (language mode 5), SwiftUI, Swift Testing (`swift test`), no external dependencies.

## Global Constraints

- Platform: macOS 14+ (`platforms: [.macOS(.v14)]`), swift-tools-version 6.0, `swiftLanguageMode(.v5)` on every target.
- No external package dependencies.
- All code, comments, commit messages in English. Conventional Commits (`feat`/`fix`/`test`/`chore`/`build`/`docs`).
- Every commit ends with footer: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- UI strings only via the `L(_:)` helper + `Localizable.strings` (English base, German translation). No hardcoded user-visible strings in views.
- `FileNode.id` is the absolute path (`String`). All selection/zoom state uses paths, never object identity.
- Sizes are allocated-on-disk bytes (`totalFileAllocatedSize`, fallback `fileAllocatedSize`), type `Int64`.
- Spec: `docs/superpowers/specs/2026-08-28-disc-scanner-design.md`.

---

### Task 1: Package scaffold + git init

**Files:**
- Create: `.gitignore`, `Package.swift`
- Create: `Sources/DiscScannerCore/DiscScannerCore.swift`
- Create: `Sources/DiscScanner/DiscScannerApp.swift`
- Test: `Tests/DiscScannerCoreTests/PackageTests.swift`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: buildable package with targets `DiscScannerCore` (library), `DiscScanner` (executable), `DiscScannerCoreTests`. Later tasks add files to these targets.

- [ ] **Step 1: Initialize git repo**

```bash
cd /Users/noidee/_dev/disc_scanner
git init -b main
```

- [ ] **Step 2: Create `.gitignore`**

```gitignore
.build/
build/
.DS_Store
*.xcodeproj
.swiftpm/
```

- [ ] **Step 3: Create `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiscScanner",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "DiscScannerCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DiscScanner",
            dependencies: ["DiscScannerCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DiscScannerCoreTests",
            dependencies: ["DiscScannerCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

- [ ] **Step 4: Create stub sources**

`Sources/DiscScannerCore/DiscScannerCore.swift`:

```swift
public enum DiscScannerCore {
    public static let version = "0.1.0"
}
```

`Sources/DiscScanner/DiscScannerApp.swift` (minimal; replaced in Task 8):

```swift
import SwiftUI

@main
struct DiscScannerApp: App {
    var body: some Scene {
        WindowGroup {
            Text("DiscScanner")
        }
    }
}
```

`Tests/DiscScannerCoreTests/PackageTests.swift`:

```swift
import Testing
@testable import DiscScannerCore

@Test func packageVersionIsSet() {
    #expect(DiscScannerCore.version == "0.1.0")
}
```

- [ ] **Step 5: Verify build and tests**

Run: `swift build && swift test`
Expected: build succeeds, 1 test passes.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: scaffold SwiftPM package with core, app, and test targets"
```

---

### Task 2: FileNode model + MutableNode snapshot conversion

**Files:**
- Create: `Sources/DiscScannerCore/FileNode.swift`
- Create: `Sources/DiscScannerCore/MutableNode.swift`
- Test: `Tests/DiscScannerCoreTests/FileNodeTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public struct FileNode: Identifiable, Sendable, Equatable` with `name: String`, `path: String`, `isDirectory: Bool`, `allocatedSize: Int64`, `isAccessDenied: Bool`, `children: [FileNode]`, `id: String` (== path), `outlineChildren: [FileNode]?`, `find(path:) -> FileNode?`.
  - internal `final class MutableNode` with same fields mutable, `weak var parent: MutableNode?`, `func snapshot() -> FileNode` (children sorted by size descending).

- [ ] **Step 1: Write the failing tests**

`Tests/DiscScannerCoreTests/FileNodeTests.swift`:

```swift
import Testing
@testable import DiscScannerCore

struct FileNodeTests {
    private func makeTree() -> MutableNode {
        let root = MutableNode(name: "root", path: "/root", isDirectory: true, parent: nil)
        let sub = MutableNode(name: "sub", path: "/root/sub", isDirectory: true, parent: root)
        let small = MutableNode(name: "small.bin", path: "/root/small.bin", isDirectory: false, parent: root)
        small.allocatedSize = 100
        let big = MutableNode(name: "big.bin", path: "/root/sub/big.bin", isDirectory: false, parent: sub)
        big.allocatedSize = 500
        sub.children = [big]
        sub.allocatedSize = 500
        root.children = [small, sub]
        root.allocatedSize = 600
        return root
    }

    @Test func snapshotSortsChildrenBySizeDescending() {
        let node = makeTree().snapshot()
        #expect(node.children.map(\.name) == ["sub", "small.bin"])
        #expect(node.allocatedSize == 600)
    }

    @Test func idIsPath() {
        let node = makeTree().snapshot()
        #expect(node.id == "/root")
        #expect(node.children[0].id == "/root/sub")
    }

    @Test func findLocatesNestedNodes() {
        let node = makeTree().snapshot()
        #expect(node.find(path: "/root/sub/big.bin")?.allocatedSize == 500)
        #expect(node.find(path: "/root") != nil)
        #expect(node.find(path: "/root/nope") == nil)
        #expect(node.find(path: "/rootx") == nil)
    }

    @Test func outlineChildrenIsNilForFilesAndEmptyDirs() {
        let node = makeTree().snapshot()
        #expect(node.outlineChildren != nil)
        #expect(node.find(path: "/root/small.bin")?.outlineChildren == nil)
        let emptyDir = MutableNode(name: "e", path: "/e", isDirectory: true, parent: nil).snapshot()
        #expect(emptyDir.outlineChildren == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: FAIL — `MutableNode`/`FileNode` not defined.

- [ ] **Step 3: Implement `FileNode`**

`Sources/DiscScannerCore/FileNode.swift`:

```swift
import Foundation

public struct FileNode: Identifiable, Sendable, Equatable {
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let allocatedSize: Int64
    public let isAccessDenied: Bool
    public let children: [FileNode]

    public var id: String { path }

    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        allocatedSize: Int64,
        isAccessDenied: Bool = false,
        children: [FileNode] = []
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.allocatedSize = allocatedSize
        self.isAccessDenied = isAccessDenied
        self.children = children
    }
}

public extension FileNode {
    /// Children for outline/disclosure UIs: nil for files and empty directories.
    var outlineChildren: [FileNode]? {
        isDirectory && !children.isEmpty ? children : nil
    }

    /// Depth-first lookup by absolute path. Prunes branches that are not path prefixes.
    func find(path: String) -> FileNode? {
        if self.path == path { return self }
        guard path.hasPrefix(self.path + "/") else { return nil }
        for child in children {
            if let found = child.find(path: path) { return found }
        }
        return nil
    }
}
```

- [ ] **Step 4: Implement `MutableNode`**

`Sources/DiscScannerCore/MutableNode.swift`:

```swift
import Foundation

/// Mutable tree node used internally by the scanner. All mutation happens
/// under ScanState's lock; UI only ever sees immutable FileNode snapshots.
final class MutableNode {
    let name: String
    let path: String
    let isDirectory: Bool
    var allocatedSize: Int64 = 0
    var isAccessDenied = false
    var children: [MutableNode] = []
    weak var parent: MutableNode?

    init(name: String, path: String, isDirectory: Bool, parent: MutableNode?) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.parent = parent
    }

    func snapshot() -> FileNode {
        FileNode(
            name: name,
            path: path,
            isDirectory: isDirectory,
            allocatedSize: allocatedSize,
            isAccessDenied: isAccessDenied,
            children: children.map { $0.snapshot() }.sorted { $0.allocatedSize > $1.allocatedSize }
        )
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test`
Expected: PASS (all FileNode tests + package test).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add FileNode snapshot model and internal MutableNode tree"
```

---

### Task 3: Parallel scan traversal (`ScanState` + `DiskScanner.performScan`)

**Files:**
- Create: `Sources/DiscScannerCore/ScanProgress.swift`
- Create: `Sources/DiscScannerCore/ScanState.swift`
- Create: `Sources/DiscScannerCore/DiskScanner.swift`
- Test: `Tests/DiscScannerCoreTests/ScanEngineTests.swift`

**Interfaces:**
- Consumes: `MutableNode`, `FileNode` (Task 2).
- Produces:
  - `public struct ScanProgress: Sendable, Equatable` — `filesScanned: Int`, `directoriesScanned: Int`, `totalBytes: Int64`, `accessDeniedCount: Int`, `currentPath: String`, `public init()`.
  - internal `final class ScanState: @unchecked Sendable` — `setRoot(_:)`, `cancel()`, `isCancelled`, `markFinished()`, `isFinished`, `mutate<T>((inout ScanProgress) -> T) -> T`, `progressSnapshot() -> ScanProgress`, `treeSnapshot() -> FileNode?`.
  - `public final class DiskScanner: @unchecked Sendable` — `public init()`, `public func cancel()`, internal `static func performScan(url: URL, state: ScanState) -> FileNode` (blocking, parallel). Task 4 adds the public `scan(url:interval:)` stream API.

- [ ] **Step 1: Write the failing tests**

`Tests/DiscScannerCoreTests/ScanEngineTests.swift`:

```swift
import Testing
import Foundation
@testable import DiscScannerCore

struct ScanEngineTests {
    /// root/
    ///   a.bin            100 KiB
    ///   sub1/b.bin       200 KiB
    ///   sub1/c.bin        50 KiB
    ///   sub1/nested/d.bin 24 KiB
    ///   link -> sub1     (symlink, must not be followed)
    /// All sizes are 4096-multiples so allocated size == byte count on APFS.
    private func makeFixture() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("scan-fixture-\(UUID().uuidString)")
        try fm.createDirectory(
            at: root.appendingPathComponent("sub1/nested"),
            withIntermediateDirectories: true
        )
        func write(_ relativePath: String, bytes: Int) throws {
            try Data(repeating: 1, count: bytes)
                .write(to: root.appendingPathComponent(relativePath))
        }
        try write("a.bin", bytes: 102_400)
        try write("sub1/b.bin", bytes: 204_800)
        try write("sub1/c.bin", bytes: 51_200)
        try write("sub1/nested/d.bin", bytes: 24_576)
        try fm.createSymbolicLink(
            at: root.appendingPathComponent("link"),
            withDestinationURL: root.appendingPathComponent("sub1")
        )
        return root
    }

    @Test func aggregatesSizesBottomUpAndSkipsSymlinks() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = ScanState()
        let tree = DiskScanner.performScan(url: root, state: state)

        let sub1 = tree.find(path: root.appendingPathComponent("sub1").path)
        #expect(sub1?.allocatedSize == 204_800 + 51_200 + 24_576)

        let link = tree.find(path: root.appendingPathComponent("link").path)
        #expect(link != nil)
        #expect(link?.isDirectory == false)
        #expect(link?.children.isEmpty == true)

        let filesTotal: Int64 = 102_400 + 204_800 + 51_200 + 24_576
        #expect(tree.allocatedSize >= filesTotal)
        // small slack for the symlink inode itself
        #expect(tree.allocatedSize <= filesTotal + 8_192)

        let sizes = tree.children.map(\.allocatedSize)
        #expect(sizes == sizes.sorted(by: >))

        let progress = state.progressSnapshot()
        #expect(progress.filesScanned == 5) // 4 files + 1 symlink
        #expect(progress.directoriesScanned == 3) // root, sub1, nested
    }

    @Test func marksUnreadableDirectoriesAndContinues() throws {
        let fm = FileManager.default
        let root = try makeFixture()
        let lockedDir = root.appendingPathComponent("locked")
        try fm.createDirectory(at: lockedDir, withIntermediateDirectories: false)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedDir.path)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedDir.path)
            try? fm.removeItem(at: root)
        }
        let state = ScanState()
        let tree = DiskScanner.performScan(url: root, state: state)

        #expect(tree.find(path: lockedDir.path)?.isAccessDenied == true)
        #expect(state.progressSnapshot().accessDeniedCount == 1)
        // scan continued past the locked dir
        #expect(tree.find(path: root.appendingPathComponent("a.bin").path) != nil)
    }

    @Test func cancelledScanReturnsPartialTree() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = ScanState()
        state.cancel()
        let tree = DiskScanner.performScan(url: root, state: state)
        #expect(tree.children.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ScanEngineTests`
Expected: FAIL — `ScanState`/`DiskScanner` not defined.

- [ ] **Step 3: Implement `ScanProgress`**

`Sources/DiscScannerCore/ScanProgress.swift`:

```swift
public struct ScanProgress: Sendable, Equatable {
    public var filesScanned = 0
    public var directoriesScanned = 0
    public var totalBytes: Int64 = 0
    public var accessDeniedCount = 0
    public var currentPath = ""

    public init() {}
}
```

- [ ] **Step 4: Implement `ScanState`**

`Sources/DiscScannerCore/ScanState.swift`:

```swift
import Foundation

/// Shared mutable state of one scan run. A single lock guards both the
/// progress counters and the MutableNode tree; workers take it briefly per
/// directory, snapshots take it for the duration of the copy.
final class ScanState: @unchecked Sendable {
    private let lock = NSLock()
    private var progress = ScanProgress()
    private var root: MutableNode?
    private var cancelled = false
    private var finished = false

    func setRoot(_ node: MutableNode) {
        lock.withLock { root = node }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func markFinished() {
        lock.withLock { finished = true }
    }

    var isFinished: Bool {
        lock.withLock { finished }
    }

    /// Runs `body` with the lock held. Tree mutation must happen inside.
    func mutate<T>(_ body: (inout ScanProgress) -> T) -> T {
        lock.withLock { body(&progress) }
    }

    func progressSnapshot() -> ScanProgress {
        lock.withLock { progress }
    }

    func treeSnapshot() -> FileNode? {
        lock.withLock { root?.snapshot() }
    }
}
```

- [ ] **Step 5: Implement `DiskScanner` traversal**

`Sources/DiscScannerCore/DiskScanner.swift`:

```swift
import Foundation

public final class DiskScanner: @unchecked Sendable {
    let state = ScanState()

    public init() {}

    public func cancel() {
        state.cancel()
    }

    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    /// Blocking parallel scan. Returns the final (or partial, if cancelled)
    /// snapshot tree. Runs directories as work items on a concurrent queue.
    static func performScan(url: URL, state: ScanState) -> FileNode {
        let root = MutableNode(
            name: url.lastPathComponent,
            path: url.path,
            isDirectory: true,
            parent: nil
        )
        state.setRoot(root)
        let queue = DispatchQueue(
            label: "DiscScanner.traversal",
            qos: .userInitiated,
            attributes: .concurrent
        )
        let group = DispatchGroup()
        scanDirectory(root, state: state, queue: queue, group: group)
        group.wait()
        state.markFinished()
        return state.treeSnapshot() ?? root.snapshot()
    }

    private static func scanDirectory(
        _ node: MutableNode,
        state: ScanState,
        queue: DispatchQueue,
        group: DispatchGroup
    ) {
        group.enter()
        queue.async {
            defer { group.leave() }
            guard !state.isCancelled else { return }

            let url = URL(fileURLWithPath: node.path, isDirectory: true)
            let entries: [URL]
            do {
                entries = try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: resourceKeys,
                    options: []
                )
            } catch {
                state.mutate { progress in
                    node.isAccessDenied = true
                    progress.accessDeniedCount += 1
                }
                return
            }

            var subdirectories: [MutableNode] = []
            state.mutate { progress in
                progress.directoriesScanned += 1
                progress.currentPath = node.path
                for entry in entries {
                    let values = try? entry.resourceValues(forKeys: Set(resourceKeys))
                    let isSymlink = values?.isSymbolicLink ?? false
                    let isDirectory = !isSymlink && (values?.isDirectory ?? false)
                    let child = MutableNode(
                        name: entry.lastPathComponent,
                        path: entry.path,
                        isDirectory: isDirectory,
                        parent: node
                    )
                    node.children.append(child)
                    if isDirectory {
                        subdirectories.append(child)
                    } else {
                        let size = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
                        child.allocatedSize = size
                        progress.filesScanned += 1
                        progress.totalBytes += size
                        var ancestor: MutableNode? = node
                        while let current = ancestor {
                            current.allocatedSize += size
                            ancestor = current.parent
                        }
                    }
                }
            }
            for subdirectory in subdirectories {
                scanDirectory(subdirectory, state: state, queue: queue, group: group)
            }
        }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter ScanEngineTests`
Expected: PASS (3 tests). If `aggregatesSizesBottomUpAndSkipsSymlinks` fails on size equality, check the filesystem is APFS; adjust only the slack bound, never the engine, unless the engine is provably wrong.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add parallel directory traversal with bottom-up size aggregation"
```

---

### Task 4: Live scan stream (`DiskScanner.scan` AsyncStream)

**Files:**
- Create: `Sources/DiscScannerCore/ScanEvent.swift`
- Modify: `Sources/DiscScannerCore/DiskScanner.swift` (add `scan(url:interval:)`)
- Test: `Tests/DiscScannerCoreTests/ScanStreamTests.swift`

**Interfaces:**
- Consumes: `DiskScanner.performScan`, `ScanState`, `ScanProgress`, `FileNode`.
- Produces:
  - `public enum ScanEvent: Sendable` — `case progress(ScanProgress)`, `case snapshot(FileNode)`, `case finished(FileNode)`.
  - `public func scan(url: URL, interval: TimeInterval = 0.25) -> AsyncStream<ScanEvent>` on `DiskScanner`. Emits batched `.progress` + `.snapshot` every `interval` while scanning, then a final `.progress` and exactly one `.finished`, then finishes the stream. Cancelling the consuming task cancels the scan (partial tree is still delivered via `.finished`).

- [ ] **Step 1: Write the failing test**

`Tests/DiscScannerCoreTests/ScanStreamTests.swift`:

```swift
import Testing
import Foundation
@testable import DiscScannerCore

struct ScanStreamTests {
    /// 40 directories x 50 files x 4 KiB — large enough that a 10 ms
    /// snapshot interval fires several times before the scan completes.
    private func makeLargeFixture() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("scan-stream-\(UUID().uuidString)")
        for directoryIndex in 0..<40 {
            let dir = root.appendingPathComponent("dir\(directoryIndex)")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for fileIndex in 0..<50 {
                try Data(repeating: 1, count: 4_096)
                    .write(to: dir.appendingPathComponent("f\(fileIndex).bin"))
            }
        }
        return root
    }

    @Test func streamsSnapshotsAndProgressBeforeFinishing() async throws {
        let root = try makeLargeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        var sawSnapshotBeforeFinish = false
        var sawProgress = false
        var finishedTree: FileNode?

        let scanner = DiskScanner()
        for await event in scanner.scan(url: root, interval: 0.01) {
            switch event {
            case .snapshot:
                if finishedTree == nil { sawSnapshotBeforeFinish = true }
            case .progress(let progress):
                if progress.filesScanned > 0 { sawProgress = true }
            case .finished(let tree):
                finishedTree = tree
            }
        }

        #expect(sawSnapshotBeforeFinish)
        #expect(sawProgress)
        #expect(finishedTree?.children.count == 40)
        #expect(finishedTree?.allocatedSize == Int64(40 * 50 * 4_096))
    }
}
```

If this test is ever flaky because the scan finishes before the first tick, increase the fixture to 100 directories — do not weaken the assertions.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScanStreamTests`
Expected: FAIL — `scan(url:interval:)` / `ScanEvent` not defined.

- [ ] **Step 3: Implement `ScanEvent`**

`Sources/DiscScannerCore/ScanEvent.swift`:

```swift
public enum ScanEvent: Sendable {
    case progress(ScanProgress)
    case snapshot(FileNode)
    case finished(FileNode)
}
```

- [ ] **Step 4: Add `scan(url:interval:)` to `DiskScanner`**

Add to `Sources/DiscScannerCore/DiskScanner.swift`:

```swift
    /// Starts a scan and returns a stream of batched events. A timer flushes
    /// progress + a full snapshot tree every `interval`; on completion the
    /// exact final tree is delivered via `.finished`. Terminating the stream
    /// (e.g. by cancelling the consuming task) cancels the scan.
    public func scan(url: URL, interval: TimeInterval = 0.25) -> AsyncStream<ScanEvent> {
        let state = self.state
        return AsyncStream(bufferingPolicy: .bufferingNewest(16)) { continuation in
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now() + interval, repeating: interval)
            timer.setEventHandler {
                guard !state.isFinished else { return }
                continuation.yield(.progress(state.progressSnapshot()))
                if let tree = state.treeSnapshot() {
                    continuation.yield(.snapshot(tree))
                }
            }
            timer.resume()

            DispatchQueue.global(qos: .userInitiated).async {
                let finalTree = Self.performScan(url: url, state: state)
                timer.cancel()
                continuation.yield(.progress(state.progressSnapshot()))
                continuation.yield(.finished(finalTree))
                continuation.finish()
            }

            continuation.onTermination = { _ in
                state.cancel()
            }
        }
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test`
Expected: PASS (all tests so far).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: stream batched scan snapshots and progress via AsyncStream"
```

---

### Task 5: Squarified treemap layout

**Files:**
- Create: `Sources/DiscScannerCore/TreemapLayout.swift`
- Test: `Tests/DiscScannerCoreTests/TreemapLayoutTests.swift`

**Interfaces:**
- Consumes: nothing (pure geometry).
- Produces:
  - `public struct TreemapItem: Sendable, Equatable` — `id: String`, `weight: Double`, `init(id:weight:)`.
  - `public struct TreemapRect: Sendable, Equatable` — `id: String`, `rect: CGRect`, `init(id:rect:)`.
  - `public enum TreemapLayout` — `static func layout(items: [TreemapItem], in bounds: CGRect) -> [TreemapRect]` (squarified per Bruls et al.; drops non-positive weights; result areas proportional to weights; tiles do not overlap and stay within bounds).

- [ ] **Step 1: Write the failing tests**

`Tests/DiscScannerCoreTests/TreemapLayoutTests.swift`:

```swift
import Testing
import Foundation
@testable import DiscScannerCore

struct TreemapLayoutTests {
    private let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)

    private func makeItems(_ weights: [Double]) -> [TreemapItem] {
        weights.enumerated().map { TreemapItem(id: "item\($0.offset)", weight: $0.element) }
    }

    @Test func tilesFullAreaWithoutOverlap() {
        let rects = TreemapLayout.layout(items: makeItems([6, 6, 4, 3, 2, 2, 1]), in: bounds)
        #expect(rects.count == 7)

        let totalArea = rects.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        #expect(abs(totalArea - 240_000) < 1.0)

        let tolerantBounds = bounds.insetBy(dx: -0.5, dy: -0.5)
        for tile in rects {
            #expect(tolerantBounds.contains(tile.rect))
        }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].rect.intersection(rects[j].rect)
                let overlapArea = Double(max(0, overlap.width) * max(0, overlap.height))
                #expect(overlapArea < 1.0)
            }
        }
    }

    @Test func areasAreProportionalToWeights() {
        let rects = TreemapLayout.layout(items: makeItems([6, 6, 4, 3, 2, 2, 1]), in: bounds)
        let first = rects.first { $0.id == "item0" }!
        let area = Double(first.rect.width * first.rect.height)
        #expect(abs(area - 240_000.0 * 6.0 / 24.0) < 1.0)
    }

    @Test func dropsNonPositiveWeights() {
        let rects = TreemapLayout.layout(items: makeItems([5, 0, -1]), in: bounds)
        #expect(rects.count == 1)
        #expect(rects[0].id == "item0")
    }

    @Test func emptyInputProducesEmptyLayout() {
        #expect(TreemapLayout.layout(items: [], in: bounds).isEmpty)
        #expect(TreemapLayout.layout(items: makeItems([1]), in: .zero).isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TreemapLayoutTests`
Expected: FAIL — `TreemapLayout` not defined.

- [ ] **Step 3: Implement squarified layout**

`Sources/DiscScannerCore/TreemapLayout.swift`:

```swift
import Foundation
import CoreGraphics

public struct TreemapItem: Sendable, Equatable {
    public let id: String
    public let weight: Double

    public init(id: String, weight: Double) {
        self.id = id
        self.weight = weight
    }
}

public struct TreemapRect: Sendable, Equatable {
    public let id: String
    public let rect: CGRect

    public init(id: String, rect: CGRect) {
        self.id = id
        self.rect = rect
    }
}

/// Squarified treemap (Bruls, Huizing, van Wijk). Greedily fills rows along
/// the shorter side of the remaining rectangle while the worst aspect ratio
/// keeps improving.
public enum TreemapLayout {
    public static func layout(items: [TreemapItem], in bounds: CGRect) -> [TreemapRect] {
        let positive = items.filter { $0.weight > 0 }.sorted { $0.weight > $1.weight }
        let totalWeight = positive.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0, bounds.width > 0, bounds.height > 0 else { return [] }

        let scale = Double(bounds.width * bounds.height) / totalWeight
        let areas = positive.map { (id: $0.id, area: $0.weight * scale) }

        var result: [TreemapRect] = []
        var remaining = bounds
        var row: [(id: String, area: Double)] = []

        func worstAspect(_ candidate: [(id: String, area: Double)], side: Double) -> Double {
            guard side > 0, !candidate.isEmpty else { return .infinity }
            let total = candidate.reduce(0.0) { $0 + $1.area }
            guard total > 0 else { return .infinity }
            let thickness = total / side
            var worst = 0.0
            for item in candidate {
                let length = item.area / thickness
                worst = max(worst, max(length / thickness, thickness / length))
            }
            return worst
        }

        func flushRow() {
            let total = row.reduce(0.0) { $0 + $1.area }
            defer { row = [] }
            guard total > 0 else { return }
            if remaining.width >= remaining.height {
                // shorter side is the height: lay a vertical strip on the left
                let stripWidth = CGFloat(total / Double(remaining.height))
                var y = remaining.minY
                for item in row {
                    let height = CGFloat(item.area / Double(stripWidth))
                    result.append(TreemapRect(
                        id: item.id,
                        rect: CGRect(x: remaining.minX, y: y, width: stripWidth, height: height)
                    ))
                    y += height
                }
                remaining = CGRect(
                    x: remaining.minX + stripWidth,
                    y: remaining.minY,
                    width: remaining.width - stripWidth,
                    height: remaining.height
                )
            } else {
                // shorter side is the width: lay a horizontal strip on top
                let stripHeight = CGFloat(total / Double(remaining.width))
                var x = remaining.minX
                for item in row {
                    let width = CGFloat(item.area / Double(stripHeight))
                    result.append(TreemapRect(
                        id: item.id,
                        rect: CGRect(x: x, y: remaining.minY, width: width, height: stripHeight)
                    ))
                    x += width
                }
                remaining = CGRect(
                    x: remaining.minX,
                    y: remaining.minY + stripHeight,
                    width: remaining.width,
                    height: remaining.height - stripHeight
                )
            }
        }

        for item in areas {
            let side = Double(min(remaining.width, remaining.height))
            if row.isEmpty || worstAspect(row + [item], side: side) <= worstAspect(row, side: side) {
                row.append(item)
            } else {
                flushRow()
                row.append(item)
            }
        }
        flushRow()
        return result
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TreemapLayoutTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add squarified treemap layout algorithm"
```

---

### Task 6: FileDeleter (trash / permanent) + redundant-path pruning

**Files:**
- Create: `Sources/DiscScannerCore/FileDeleter.swift`
- Test: `Tests/DiscScannerCoreTests/FileDeleterTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public enum DeletionMethod: Sendable` — `case trash`, `case permanent`.
  - `public struct DeletionFailure: Sendable, Equatable` — `path: String`, `message: String`.
  - `public struct DeletionResult: Sendable` — `deletedPaths: [String]`, `failures: [DeletionFailure]`.
  - `public enum FileDeleter` — `static func delete(paths: [String], method: DeletionMethod) -> DeletionResult` (continues past per-item failures), `static func pruneRedundant(_ paths: Set<String>) -> [String]` (drops paths whose ancestor is also selected; returns sorted).

- [ ] **Step 1: Write the failing tests**

`Tests/DiscScannerCoreTests/FileDeleterTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FileDeleterTests`
Expected: FAIL — `FileDeleter` not defined.

- [ ] **Step 3: Implement `FileDeleter`**

`Sources/DiscScannerCore/FileDeleter.swift`:

```swift
import Foundation

public enum DeletionMethod: Sendable {
    case trash
    case permanent
}

public struct DeletionFailure: Sendable, Equatable {
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public struct DeletionResult: Sendable {
    public let deletedPaths: [String]
    public let failures: [DeletionFailure]

    public init(deletedPaths: [String], failures: [DeletionFailure]) {
        self.deletedPaths = deletedPaths
        self.failures = failures
    }
}

public enum FileDeleter {
    /// Deletes each path independently; one failure never aborts the rest.
    public static func delete(paths: [String], method: DeletionMethod) -> DeletionResult {
        var deleted: [String] = []
        var failures: [DeletionFailure] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            do {
                switch method {
                case .trash:
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                case .permanent:
                    try FileManager.default.removeItem(at: url)
                }
                deleted.append(path)
            } catch {
                failures.append(DeletionFailure(path: path, message: error.localizedDescription))
            }
        }
        return DeletionResult(deletedPaths: deleted, failures: failures)
    }

    /// Drops paths that are descendants of another selected path, so deleting
    /// a folder plus a file inside it never double-deletes.
    public static func pruneRedundant(_ paths: Set<String>) -> [String] {
        paths.filter { path in
            !paths.contains { other in
                other != path && path.hasPrefix(other + "/")
            }
        }
        .sorted()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FileDeleterTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add trash and permanent deletion with per-item error reporting"
```

---

### Task 7: TreePruner (post-deletion tree update)

**Files:**
- Create: `Sources/DiscScannerCore/TreePruner.swift`
- Test: `Tests/DiscScannerCoreTests/TreePrunerTests.swift`

**Interfaces:**
- Consumes: `FileNode`.
- Produces: `public enum TreePruner` — `static func removing(paths: Set<String>, from node: FileNode) -> FileNode?`. Returns nil if the node itself is removed; directory sizes are recomputed as the sum of remaining children (recursively); child order (size-descending) is preserved by re-sorting.

- [ ] **Step 1: Write the failing tests**

`Tests/DiscScannerCoreTests/TreePrunerTests.swift`:

```swift
import Testing
@testable import DiscScannerCore

struct TreePrunerTests {
    /// root(350) { sub(250) { b.bin(200), c.bin(50) }, a.bin(100) }
    private func makeTree() -> FileNode {
        FileNode(
            name: "root", path: "/root", isDirectory: true, allocatedSize: 350,
            children: [
                FileNode(
                    name: "sub", path: "/root/sub", isDirectory: true, allocatedSize: 250,
                    children: [
                        FileNode(name: "b.bin", path: "/root/sub/b.bin", isDirectory: false, allocatedSize: 200),
                        FileNode(name: "c.bin", path: "/root/sub/c.bin", isDirectory: false, allocatedSize: 50),
                    ]
                ),
                FileNode(name: "a.bin", path: "/root/a.bin", isDirectory: false, allocatedSize: 100),
            ]
        )
    }

    @Test func removesFileAndReaggregatesAncestorSizes() {
        let pruned = TreePruner.removing(paths: ["/root/sub/b.bin"], from: makeTree())
        #expect(pruned?.allocatedSize == 150)
        #expect(pruned?.find(path: "/root/sub")?.allocatedSize == 50)
        #expect(pruned?.find(path: "/root/sub/b.bin") == nil)
        #expect(pruned?.find(path: "/root/sub/c.bin") != nil)
    }

    @Test func removesDirectorySubtree() {
        let pruned = TreePruner.removing(paths: ["/root/sub"], from: makeTree())
        #expect(pruned?.allocatedSize == 100)
        #expect(pruned?.find(path: "/root/sub") == nil)
        #expect(pruned?.children.count == 1)
    }

    @Test func removingRootReturnsNil() {
        #expect(TreePruner.removing(paths: ["/root"], from: makeTree()) == nil)
    }

    @Test func resortsChildrenAfterRemoval() {
        // removing b.bin makes sub (50) smaller than a.bin (100)
        let pruned = TreePruner.removing(paths: ["/root/sub/b.bin"], from: makeTree())
        #expect(pruned?.children.map(\.name) == ["a.bin", "sub"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TreePrunerTests`
Expected: FAIL — `TreePruner` not defined.

- [ ] **Step 3: Implement `TreePruner`**

`Sources/DiscScannerCore/TreePruner.swift`:

```swift
import Foundation

public enum TreePruner {
    /// Rebuilds the snapshot tree without the given paths. Directory sizes
    /// become the sum of their remaining children so ancestors shrink
    /// accordingly; no rescan needed.
    public static func removing(paths: Set<String>, from node: FileNode) -> FileNode? {
        guard !paths.contains(node.path) else { return nil }
        guard node.isDirectory else { return node }

        let newChildren = node.children
            .compactMap { removing(paths: paths, from: $0) }
            .sorted { $0.allocatedSize > $1.allocatedSize }
        let newSize = newChildren.reduce(Int64(0)) { $0 + $1.allocatedSize }

        return FileNode(
            name: node.name,
            path: node.path,
            isDirectory: true,
            allocatedSize: newSize,
            isAccessDenied: node.isAccessDenied,
            children: newChildren
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS (entire suite).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add tree pruning with size re-aggregation after deletion"
```

---

### Task 8: App shell — AppState, ContentView, localization

**Files:**
- Modify: `Package.swift` (add resources to the executable target)
- Create: `Sources/DiscScanner/Resources/en.lproj/Localizable.strings`
- Create: `Sources/DiscScanner/Resources/de.lproj/Localizable.strings`
- Create: `Sources/DiscScanner/Localization.swift`
- Create: `Sources/DiscScanner/Format.swift`
- Create: `Sources/DiscScanner/AppState.swift`
- Create: `Sources/DiscScanner/ContentView.swift`
- Modify: `Sources/DiscScanner/DiscScannerApp.swift`

**Interfaces:**
- Consumes: `DiskScanner.scan(url:interval:)`, `ScanEvent`, `ScanProgress`, `FileNode`.
- Produces (used by Tasks 9–11):
  - `@MainActor @Observable final class AppState` — `root: FileNode?`, `progress: ScanProgress`, `isScanning: Bool`, `viewMode: ViewMode` (`enum ViewMode: String, CaseIterable, Identifiable { case list, treemap }`), `selection: Set<String>`, `treemapZoomPath: String?`, `startScan(url:)`, `cancelScan()`.
  - `func L(_ key: String) -> String` and `func L(_ key: String, _ args: CVarArg...) -> String`.
  - `enum Format` — `static func bytes(Int64) -> String`, `static func count(Int) -> String`.
  - `ContentView` with a `mainContent` placeholder that Task 9 replaces.
- Full localization table for ALL tasks is created here; later tasks only reference existing keys.

- [ ] **Step 1: Add resources to `Package.swift`**

Change the executable target to:

```swift
        .executableTarget(
            name: "DiscScanner",
            dependencies: ["DiscScannerCore"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
```

- [ ] **Step 2: Create the full string tables**

`Sources/DiscScanner/Resources/en.lproj/Localizable.strings`:

```c
"app.open" = "Open…";
"app.cancel" = "Cancel";
"view.list" = "List";
"view.treemap" = "Treemap";
"status.scanning" = "Scanning: %@";
"status.done" = "Scan complete";
"status.summary" = "%@ files · %@ folders · %@";
"banner.accessDenied" = "%@ folders could not be read. Grant Full Disk Access in System Settings → Privacy & Security to scan protected areas.";
"empty.prompt" = "Open a folder or volume to see what is using your disk space.";
"menu.showInFinder" = "Show in Finder";
"menu.delete" = "Delete…";
"delete.title" = "Delete %@ items (%@)?";
"delete.message" = "Moving to Trash can be undone. Permanent deletion cannot.";
"delete.trash" = "Move to Trash";
"delete.permanent" = "Delete Permanently";
"delete.failures.title" = "Some items could not be deleted";
"common.ok" = "OK";
"common.cancel" = "Cancel";
```

`Sources/DiscScanner/Resources/de.lproj/Localizable.strings`:

```c
"app.open" = "Öffnen…";
"app.cancel" = "Abbrechen";
"view.list" = "Liste";
"view.treemap" = "Treemap";
"status.scanning" = "Scanne: %@";
"status.done" = "Scan abgeschlossen";
"status.summary" = "%@ Dateien · %@ Ordner · %@";
"banner.accessDenied" = "%@ Ordner konnten nicht gelesen werden. Erteile „Festplattenvollzugriff“ in Systemeinstellungen → Datenschutz & Sicherheit, um geschützte Bereiche zu scannen.";
"empty.prompt" = "Öffne einen Ordner oder ein Volume, um zu sehen, was deinen Speicher belegt.";
"menu.showInFinder" = "Im Finder zeigen";
"menu.delete" = "Löschen…";
"delete.title" = "%@ Objekte löschen (%@)?";
"delete.message" = "Der Papierkorb lässt sich wiederherstellen, endgültiges Löschen nicht.";
"delete.trash" = "In den Papierkorb legen";
"delete.permanent" = "Endgültig löschen";
"delete.failures.title" = "Einige Objekte konnten nicht gelöscht werden";
"common.ok" = "OK";
"common.cancel" = "Abbrechen";
```

- [ ] **Step 3: Create helpers**

`Sources/DiscScanner/Localization.swift`:

```swift
import Foundation

func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, bundle: .module, comment: ""), arguments: args)
}
```

`Sources/DiscScanner/Format.swift`:

```swift
import Foundation

enum Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func count(_ value: Int) -> String {
        value.formatted()
    }
}
```

- [ ] **Step 4: Create `AppState`**

`Sources/DiscScanner/AppState.swift`:

```swift
import Foundation
import Observation
import DiscScannerCore

@MainActor
@Observable
final class AppState {
    enum ViewMode: String, CaseIterable, Identifiable {
        case list
        case treemap

        var id: String { rawValue }
    }

    var root: FileNode?
    var progress = ScanProgress()
    var isScanning = false
    var viewMode: ViewMode = .list
    var selection: Set<String> = []
    var treemapZoomPath: String?

    private var scanTask: Task<Void, Never>?

    func startScan(url: URL) {
        cancelScan()
        root = nil
        selection = []
        treemapZoomPath = nil
        progress = ScanProgress()
        isScanning = true
        let scanner = DiskScanner()
        scanTask = Task { [weak self] in
            for await event in scanner.scan(url: url) {
                guard let self else { return }
                switch event {
                case .progress(let progress):
                    self.progress = progress
                case .snapshot(let tree):
                    self.root = tree
                case .finished(let tree):
                    self.root = tree
                    self.isScanning = false
                }
            }
            self?.isScanning = false
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }
}
```

- [ ] **Step 5: Create `ContentView`**

`Sources/DiscScanner/ContentView.swift`:

```swift
import SwiftUI
import DiscScannerCore

struct ContentView: View {
    @Bindable var appState: AppState

    var body: some View {
        Group {
            if let root = appState.root {
                mainContent(root)
            } else {
                ContentUnavailableView(L("empty.prompt"), systemImage: "internaldrive")
            }
        }
        .frame(minWidth: 700, minHeight: 450)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .top, spacing: 0) {
            if appState.progress.accessDeniedCount > 0 {
                accessDeniedBanner
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
    }

    // Replaced with the real list/treemap views in Tasks 9 and 11.
    @ViewBuilder
    private func mainContent(_ root: FileNode) -> some View {
        Text(root.name)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(L("app.open"), systemImage: "folder") { openFolder() }
        }
        ToolbarItem {
            Picker(L("view.list"), selection: $appState.viewMode) {
                Text(L("view.list")).tag(AppState.ViewMode.list)
                Text(L("view.treemap")).tag(AppState.ViewMode.treemap)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        if appState.isScanning {
            ToolbarItem {
                ProgressView().controlSize(.small)
            }
            ToolbarItem {
                Button(L("app.cancel")) { appState.cancelScan() }
            }
        }
    }

    private var statusBar: some View {
        HStack {
            if appState.isScanning {
                Text(L("status.scanning", appState.progress.currentPath))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if appState.root != nil {
                Text(L("status.done"))
            }
            Spacer()
            Text(L(
                "status.summary",
                Format.count(appState.progress.filesScanned),
                Format.count(appState.progress.directoriesScanned),
                Format.bytes(appState.progress.totalBytes)
            ))
            .monospacedDigit()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var accessDeniedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(L("banner.accessDenied", Format.count(appState.progress.accessDeniedCount)))
            Spacer()
        }
        .font(.callout)
        .padding(8)
        .background(.yellow.opacity(0.15))
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("app.open")
        if panel.runModal() == .OK, let url = panel.url {
            appState.startScan(url: url)
        }
    }
}
```

- [ ] **Step 6: Replace `DiscScannerApp`**

`Sources/DiscScanner/DiscScannerApp.swift` (full replacement):

```swift
import SwiftUI

@main
struct DiscScannerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .onAppear {
                    // Makes the window come to front when run as a bare
                    // binary via `swift run` during development.
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
    }
}
```

- [ ] **Step 7: Build and verify tests still pass**

Run: `swift build && swift test`
Expected: build succeeds, all tests pass.

- [ ] **Step 8: Manual verification**

Run: `swift run`
Check: window appears with empty-state prompt; "Open…" shows a folder picker that also allows selecting volume roots; picking a folder (e.g. `~/Downloads`) shows the folder name, the status bar counts files/folders/bytes live while scanning, current path updates, Cancel stops the scan, the List/Treemap toggle switches (both still show the placeholder text). Quit with Cmd+Q.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add app shell with live scan progress and localization"
```

---

### Task 9: Tree list view

**Files:**
- Create: `Sources/DiscScanner/TreeListView.swift`
- Modify: `Sources/DiscScanner/ContentView.swift` (replace `mainContent`)

**Interfaces:**
- Consumes: `AppState` (`selection`, `viewMode`), `FileNode` (`outlineChildren`, `id`), `Format`, `L(_:)`.
- Produces: `struct TreeListView: View` with init `TreeListView(appState:root:)`. Context menu here has only "Show in Finder"; Task 10 adds the delete entry.

- [ ] **Step 1: Create `TreeListView`**

`Sources/DiscScanner/TreeListView.swift`:

```swift
import SwiftUI
import DiscScannerCore

struct TreeListView: View {
    @Bindable var appState: AppState
    let root: FileNode

    var body: some View {
        List(selection: $appState.selection) {
            ForEach(root.children) { child in
                TreeNodeView(node: child, parentSize: max(root.allocatedSize, 1))
            }
        }
        .contextMenu(forSelectionType: String.self) { paths in
            Button(L("menu.showInFinder")) { revealInFinder(paths) }
        }
    }

    private func revealInFinder(_ paths: Set<String>) {
        NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
    }
}

private struct TreeNodeView: View {
    let node: FileNode
    let parentSize: Int64

    var body: some View {
        if let children = node.outlineChildren {
            DisclosureGroup {
                ForEach(children) { child in
                    TreeNodeView(node: child, parentSize: max(node.allocatedSize, 1))
                }
            } label: {
                FileRowView(node: node, parentSize: parentSize)
            }
            .tag(node.id)
        } else {
            FileRowView(node: node, parentSize: parentSize)
                .tag(node.id)
        }
    }
}

private struct FileRowView: View {
    let node: FileNode
    let parentSize: Int64

    private var fraction: Double {
        min(1, Double(node.allocatedSize) / Double(parentSize))
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.path))
                .resizable()
                .frame(width: 16, height: 16)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            if node.isAccessDenied {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SizeBar(fraction: fraction)
            Text(Format.bytes(node.allocatedSize))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
        }
    }
}

private struct SizeBar: View {
    let fraction: Double

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(.quaternary)
            RoundedRectangle(cornerRadius: 2)
                .fill(.tint.opacity(0.6))
                .frame(width: max(2, 60 * fraction))
        }
        .frame(width: 60, height: 6)
    }
}
```

- [ ] **Step 2: Wire into `ContentView`**

Replace the `mainContent` function in `Sources/DiscScanner/ContentView.swift` with:

```swift
    @ViewBuilder
    private func mainContent(_ root: FileNode) -> some View {
        switch appState.viewMode {
        case .list:
            TreeListView(appState: appState, root: root)
        case .treemap:
            // Replaced with the real treemap in Task 11.
            Text(L("view.treemap"))
        }
    }
```

- [ ] **Step 3: Build and verify tests still pass**

Run: `swift build && swift test`
Expected: build succeeds, all tests pass.

- [ ] **Step 4: Manual verification**

Run: `swift run`
Check: scanning a folder fills the tree live (rows appear and sizes grow during the scan); children sorted largest-first; disclosure triangles expand directories; size bars are proportional to the parent; multi-select works (Cmd-click); right-click → "Show in Finder" reveals the item; locked folders show the lock icon.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add sortable tree list view with live updates and size bars"
```

---

### Task 10: Delete flow (dialog, deletion, pruning, error reporting)

**Files:**
- Modify: `Sources/DiscScanner/AppState.swift` (add deletion state + actions)
- Modify: `Sources/DiscScanner/ContentView.swift` (add dialog + failure alert)
- Modify: `Sources/DiscScanner/TreeListView.swift` (add delete menu entry)

**Interfaces:**
- Consumes: `FileDeleter.delete(paths:method:)`, `FileDeleter.pruneRedundant(_:)`, `TreePruner.removing(paths:from:)`, `DeletionMethod`, `DeletionFailure`, `DeletionResult`, `FileNode.find(path:)`.
- Produces (used by Task 11): on `AppState` — `pendingDeletePaths: [String]`, `showDeleteDialog: Bool`, `deletionFailures: [DeletionFailure]`, `showFailureAlert: Bool`, `pendingDeleteSize: Int64`, `requestDelete(paths: Set<String>)`, `performDelete(method: DeletionMethod)`.

- [ ] **Step 1: Extend `AppState`**

Add `import DiscScannerCore` is already present. Add these properties after `treemapZoomPath`:

```swift
    var pendingDeletePaths: [String] = []
    var showDeleteDialog = false
    var deletionFailures: [DeletionFailure] = []
    var showFailureAlert = false
```

Add these members after `cancelScan()`:

```swift
    var pendingDeleteSize: Int64 {
        guard let root else { return 0 }
        return pendingDeletePaths
            .compactMap { root.find(path: $0)?.allocatedSize }
            .reduce(0, +)
    }

    func requestDelete(paths: Set<String>) {
        guard !paths.isEmpty, !isScanning else { return }
        pendingDeletePaths = FileDeleter.pruneRedundant(paths)
        showDeleteDialog = true
    }

    func performDelete(method: DeletionMethod) {
        let paths = pendingDeletePaths
        pendingDeletePaths = []
        guard !paths.isEmpty else { return }
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                FileDeleter.delete(paths: paths, method: method)
            }.value
            applyDeletionResult(result)
        }
    }

    private func applyDeletionResult(_ result: DeletionResult) {
        if let root, !result.deletedPaths.isEmpty {
            self.root = TreePruner.removing(paths: Set(result.deletedPaths), from: root)
        }
        selection = []
        deletionFailures = result.failures
        showFailureAlert = !result.failures.isEmpty
    }
```

- [ ] **Step 2: Add dialog and alert to `ContentView`**

Append to the modifier chain of the outer `Group` in `body` (after the bottom `safeAreaInset`):

```swift
        .confirmationDialog(
            L(
                "delete.title",
                Format.count(appState.pendingDeletePaths.count),
                Format.bytes(appState.pendingDeleteSize)
            ),
            isPresented: $appState.showDeleteDialog,
            titleVisibility: .visible
        ) {
            Button(L("delete.trash")) { appState.performDelete(method: .trash) }
            Button(L("delete.permanent"), role: .destructive) {
                appState.performDelete(method: .permanent)
            }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(
                ([L("delete.message")] + appState.pendingDeletePaths.prefix(8))
                    .joined(separator: "\n")
            )
        }
        .alert(L("delete.failures.title"), isPresented: $appState.showFailureAlert) {
            Button(L("common.ok"), role: .cancel) {}
        } message: {
            Text(
                appState.deletionFailures
                    .prefix(5)
                    .map { "\($0.path): \($0.message)" }
                    .joined(separator: "\n")
            )
        }
```

- [ ] **Step 3: Add delete entry to the list context menu**

In `Sources/DiscScanner/TreeListView.swift`, extend the context menu to:

```swift
        .contextMenu(forSelectionType: String.self) { paths in
            Button(L("menu.showInFinder")) { revealInFinder(paths) }
            Button(L("menu.delete"), role: .destructive) { appState.requestDelete(paths: paths) }
        }
```

- [ ] **Step 4: Build and verify tests still pass**

Run: `swift build && swift test`
Expected: build succeeds, all tests pass.

- [ ] **Step 5: Manual verification**

Create throwaway data first:

```bash
mkdir -p /tmp/discscanner-manual/sub && dd if=/dev/zero of=/tmp/discscanner-manual/big.bin bs=1m count=50 && dd if=/dev/zero of=/tmp/discscanner-manual/sub/small.bin bs=1m count=5
```

Run: `swift run`, scan `/tmp/discscanner-manual`.
Check: select `big.bin` → right-click → "Delete…" shows the dialog with count and ~50 MB; "Move to Trash" removes the row, parent size shrinks by ~50 MB without rescan, file is in the Trash. Repeat with `sub` via "Delete Permanently" → folder gone from disk. Selecting a folder plus a file inside it deletes without an error alert (redundant path pruned). While a scan is running, "Delete…" does nothing.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add delete flow with trash and permanent options"
```

---

### Task 11: Treemap view with zoom and breadcrumb

**Files:**
- Create: `Sources/DiscScanner/TreemapView.swift`
- Modify: `Sources/DiscScanner/ContentView.swift` (replace treemap placeholder)

**Interfaces:**
- Consumes: `TreemapLayout.layout(items:in:)`, `TreemapItem`, `TreemapRect`, `AppState` (`selection`, `treemapZoomPath`, `requestDelete(paths:)`), `FileNode.find(path:)`, `L(_:)`.
- Produces: `struct TreemapView: View` with init `TreemapView(appState:root:)`.

- [ ] **Step 1: Create `TreemapView`**

`Sources/DiscScanner/TreemapView.swift`:

```swift
import SwiftUI
import DiscScannerCore

struct TreemapView: View {
    @Bindable var appState: AppState
    let root: FileNode

    /// The directory currently zoomed into. Falls back to the scan root when
    /// the stored path no longer resolves (e.g. after deletion or a fresh
    /// snapshot).
    private var zoomRoot: FileNode {
        guard
            let path = appState.treemapZoomPath,
            let node = root.find(path: path),
            node.isDirectory
        else { return root }
        return node
    }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumb
            GeometryReader { proxy in
                let bounds = CGRect(origin: .zero, size: proxy.size)
                let tiles = TreemapLayout.layout(items: items(for: zoomRoot), in: bounds)
                Canvas { context, _ in
                    for tile in tiles {
                        guard let node = zoomRoot.find(path: tile.id) else { continue }
                        draw(node: node, in: tile.rect, context: &context)
                    }
                }
                .gesture(tapGestures(tiles: tiles))
                .contextMenu {
                    Button(L("menu.showInFinder")) { revealSelection() }
                    Button(L("menu.delete"), role: .destructive) {
                        appState.requestDelete(paths: appState.selection)
                    }
                }
            }
        }
    }

    private func items(for node: FileNode) -> [TreemapItem] {
        node.children.map { TreemapItem(id: $0.path, weight: Double($0.allocatedSize)) }
    }

    private func draw(node: FileNode, in rect: CGRect, context: inout GraphicsContext) {
        let inset = rect.insetBy(dx: 1, dy: 1)
        guard inset.width > 0, inset.height > 0 else { return }
        let path = Path(roundedRect: inset, cornerRadius: 2)
        context.fill(path, with: .color(tileColor(for: node)))
        if appState.selection.contains(node.path) {
            context.stroke(path, with: .color(.accentColor), lineWidth: 2)
        }
        if inset.width > 60, inset.height > 16 {
            context.draw(
                Text(node.name).font(.caption2).foregroundStyle(.white),
                in: inset.insetBy(dx: 4, dy: 2)
            )
        }
    }

    private func tileColor(for node: FileNode) -> Color {
        if node.isAccessDenied { return .orange.opacity(0.7) }
        let base: Color = node.isDirectory ? .blue : .teal
        let variation = Double(abs(node.name.hashValue % 30)) / 100.0
        return base.opacity(0.55 + variation)
    }

    private func tapGestures(tiles: [TreemapRect]) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                guard
                    let id = hitTest(tiles, at: value.location),
                    let node = zoomRoot.find(path: id),
                    node.isDirectory
                else { return }
                appState.treemapZoomPath = node.path
            }
            .exclusively(before: SpatialTapGesture(count: 1)
                .onEnded { value in
                    if let id = hitTest(tiles, at: value.location) {
                        appState.selection = [id]
                    }
                }
            )
    }

    private func hitTest(_ tiles: [TreemapRect], at point: CGPoint) -> String? {
        tiles.first { $0.rect.contains(point) }?.id
    }

    private func revealSelection() {
        NSWorkspace.shared.activateFileViewerSelecting(
            appState.selection.map { URL(fileURLWithPath: $0) }
        )
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            let crumbs = breadcrumbNodes()
            ForEach(crumbs, id: \.path) { node in
                Button(node.name) {
                    appState.treemapZoomPath = node.path == root.path ? nil : node.path
                }
                .buttonStyle(.link)
                if node.path != crumbs.last?.path {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(6)
        .background(.bar)
    }

    private func breadcrumbNodes() -> [FileNode] {
        var nodes: [FileNode] = [root]
        let zoom = zoomRoot
        guard zoom.path != root.path else { return nodes }
        let relative = zoom.path.dropFirst(root.path.count)
            .split(separator: "/")
            .map(String.init)
        var currentPath = root.path
        var current = root
        for component in relative {
            currentPath += "/" + component
            guard let next = current.find(path: currentPath) else { break }
            nodes.append(next)
            current = next
        }
        return nodes
    }
}
```

- [ ] **Step 2: Wire into `ContentView`**

Replace the `mainContent` function in `Sources/DiscScanner/ContentView.swift` with:

```swift
    @ViewBuilder
    private func mainContent(_ root: FileNode) -> some View {
        switch appState.viewMode {
        case .list:
            TreeListView(appState: appState, root: root)
        case .treemap:
            TreemapView(appState: appState, root: root)
        }
    }
```

- [ ] **Step 3: Build and verify tests still pass**

Run: `swift build && swift test`
Expected: build succeeds, all tests pass.

- [ ] **Step 4: Manual verification**

Run: `swift run`, scan a folder with nested content (e.g. `~/Downloads`), switch to Treemap.
Check: tiles render proportional to sizes and update live during a scan; big items are labeled; single click selects (accent border, selection carries over to the list view); double-click a directory zooms in and the breadcrumb grows; breadcrumb buttons navigate back; right-click after selecting offers "Show in Finder" and "Delete…" (dialog from Task 10 appears); after deleting the zoomed folder itself, the view falls back to the scan root without crashing.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add treemap view with zoom and breadcrumb navigation"
```

---

### Task 12: App bundling (Makefile, Info.plist, README)

**Files:**
- Create: `Resources/Info.plist`
- Create: `Makefile`
- Create: `README.md`

**Interfaces:**
- Consumes: the built `DiscScanner` executable and its SwiftPM resource bundle `DiscScanner_DiscScanner.bundle` (localization from Task 8).
- Produces: `make app` → `build/DiscScanner.app` (ad-hoc signed), `make run` → builds and opens the app, `make test` → runs the suite.

- [ ] **Step 1: Create `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>DiscScanner</string>
	<key>CFBundleIdentifier</key>
	<string>dev.noidee.DiscScanner</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>DiscScanner</string>
	<key>CFBundleDisplayName</key>
	<string>DiscScanner</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
```

- [ ] **Step 2: Create `Makefile`**

(Recipe lines must be indented with tabs, not spaces.)

```make
APP_NAME := DiscScanner
BUILD_DIR := .build/release
APP_BUNDLE := build/$(APP_NAME).app

.PHONY: build test app run clean

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	if [ -d "$(BUILD_DIR)/$(APP_NAME)_$(APP_NAME).bundle" ]; then \
		cp -R "$(BUILD_DIR)/$(APP_NAME)_$(APP_NAME).bundle" $(APP_BUNDLE)/Contents/Resources/; \
	fi
	codesign --force --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

run: app
	open $(APP_BUNDLE)

clean:
	rm -rf .build build
```

- [ ] **Step 3: Create `README.md`**

```markdown
# DiscScanner

A small macOS app that scans a folder or volume recursively and shows where
disk space is used — as a size-sorted tree and as a treemap — with options to
move items to the Trash or delete them permanently.

## Requirements

- macOS 14+
- Xcode 16+ command line tools (Swift 6 toolchain)

## Build & Run

    make run        # builds build/DiscScanner.app and opens it
    make test       # runs the unit test suite
    swift run       # development run without bundling

## Full Disk Access

To scan protected areas (other users' folders, parts of the system volume),
grant the app Full Disk Access: System Settings → Privacy & Security →
Full Disk Access → add `build/DiscScanner.app`. Without it, unreadable
folders are marked with a lock icon and skipped.

## Notes

- Sizes are allocated-on-disk bytes, so totals can differ slightly from
  Finder's "logical" sizes.
- Deleting to Trash is undoable via the Finder; permanent deletion is not.
```

- [ ] **Step 4: Build the bundle and verify**

Run: `make app`
Expected: `build/DiscScanner.app` exists, `codesign --verify build/DiscScanner.app` passes, and the resource bundle is at `build/DiscScanner.app/Contents/Resources/DiscScanner_DiscScanner.bundle`.

- [ ] **Step 5: Manual verification**

Run: `make run`
Check: app launches from the bundle with its own Dock entry named "DiscScanner"; scanning and deleting work as in Tasks 9–11.

German localization check:

```bash
build/DiscScanner.app/Contents/MacOS/DiscScanner -AppleLanguages '(de)'
```

Check: toolbar shows "Öffnen…", status bar and delete dialog are German.

Optional: grant Full Disk Access to `build/DiscScanner.app`, scan `/` and confirm the access-denied banner count drops on a rescan.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "build: add app bundling via Makefile and Info.plist"
```

---

## Final Verification (after all tasks)

- [ ] `swift test` — entire suite green.
- [ ] `make run` — scan `~/` in the app: tree fills live, progress counts up, Cancel works.
- [ ] Delete a throwaway file via Trash AND a throwaway folder permanently; sizes re-aggregate without rescan.
- [ ] Treemap: zoom in/out via double-click and breadcrumb.
- [ ] German run via `-AppleLanguages '(de)'`.
- [ ] `git log --oneline` — conventional commits only.
