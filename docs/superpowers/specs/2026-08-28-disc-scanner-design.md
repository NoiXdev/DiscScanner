# DiscScanner — Design Spec

Date: 2026-08-28
Status: Approved (pending user review of this document)

## Overview

DiscScanner is a small native macOS app (Swift/SwiftUI, min. macOS 14) that
recursively scans a user-selected folder or an entire volume, shows where disk
space is used (large folders and files), and lets the user delete items —
either to the Trash or permanently.

## Goals

- Pick any folder or volume and scan it recursively.
- Find large folders/files quickly; UI updates **live while the scan runs**.
- Two views: sortable tree list (primary) and squarified treemap.
- Delete selected items to Trash (default) or permanently (with warning).
- Localized UI: English base, German localization.

## Non-Goals

- No cross-platform support (macOS only).
- No duplicate-file detection, no scheduled scans, no persistence of results.
- No App Store distribution / notarization pipeline (local personal tool).

## Project Setup

- Swift Package (SwiftPM) with an executable target plus a bundling script
  (`make app`) that produces `DiscScanner.app` — fully CLI-buildable, no
  `.xcodeproj`. The package can still be opened in Xcode if desired.
- Targets:
  - `DiscScannerCore` (library): scan engine, tree model, treemap layout,
    delete operations. Fully unit-testable, no UI imports.
  - `DiscScanner` (executable): SwiftUI app, views, view models.
  - `DiscScannerCoreTests`: unit tests.
- Localization via string catalog (English base, German translation); fall
  back to classic `.strings` files if SwiftPM tooling gets in the way.

## Scan Engine (DiscScannerCore)

### Data model

- `FileNode`: a reference type (class) so tree nodes have stable identity:
  `name`, `url`, `isDirectory`, `allocatedSize` (aggregated for directories),
  `children`, `isAccessDenied` flag, weak `parent`.
- Sizes use `totalFileAllocatedSize` (actual on-disk usage; falls back to
  `fileAllocatedSize`/`fileSize` where unavailable).

### Concurrency & traversal

- Parallel traversal using a worker pool (Swift Concurrency `TaskGroup`,
  bounded to roughly `ProcessInfo.activeProcessorCount` workers). Each worker
  takes a directory off a shared work queue, reads its entries with
  `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:)`, creates
  child nodes, and enqueues subdirectories.
- Directory sizes aggregate bottom-up; a directory's displayed size grows as
  descendants are discovered (running totals propagated up the parent chain).
- Symlinks are recorded but not followed (no cycles, no double-counting).
- Unreadable directories (permissions) are marked `isAccessDenied` and
  skipped; the scan continues.
- Cancellation: cooperative — workers check `Task.isCancelled`; Cancel button
  stops the scan and keeps the partial tree.

### Live UI updates

- The engine never pushes per-file events to the UI. Instead it maintains the
  growing tree behind a lock and publishes **batched snapshots ~4×/second**
  (a coalescing timer flushes "dirty" state to the main actor).
- Published progress: files seen, directories seen, total bytes so far,
  current path (for a status line).
- The tree view renders from the latest snapshot, so folders appear and sizes
  count up live during the scan. Sorting by size re-applies on each batch.
- After scan completion a final flush guarantees the UI shows the exact end
  state.

## UI (SwiftUI)

### Shell

- Toolbar: "Open…" (folder/volume picker via `NSOpenPanel` — volumes are
  chosen by picking their root), view toggle (List / Treemap), Cancel button
  and progress indicator while scanning, status bar with files/bytes counters.
- If scanning system areas yields many access-denied entries, show a hint
  banner explaining how to grant Full Disk Access in System Settings.

### Tree list view (primary)

- Expandable directory tree, children sorted by size descending.
- Per row: icon (folder/file via `NSWorkspace` icon), name, formatted size,
  percentage bar relative to the parent, access-denied marker where relevant.
- Multi-selection; context menu: "Show in Finder", "Delete…".

### Treemap view

- Squarified treemap drawn with SwiftUI `Canvas` from the current tree
  (updates live with the same batched snapshots).
- Click selects; double-click zooms into a directory; breadcrumb path at the
  top navigates back up.
- Same context-menu actions as the list.

## Deletion

- "Delete…" (from either view, multi-selection supported) opens a
  confirmation dialog listing the affected paths and their total size, with
  two explicit choices:
  - **Move to Trash** (default) — `NSWorkspace.recycle` /
    `FileManager.trashItem`.
  - **Delete Permanently** (destructive style, extra warning text,
    irreversible) — `FileManager.removeItem`.
- After deletion, removed nodes are pruned from the in-memory tree and
  ancestor sizes are re-aggregated locally — no full rescan.
- Per-item failures (permissions, SIP-protected paths) are collected and
  shown in a result alert; remaining items are still processed.

## Error Handling

- Scan: unreadable entries → flagged and skipped, never abort the scan.
- Delete: per-item error reporting as above.
- Picker/permission edge cases: clear message plus the Full Disk Access hint.

## Testing

- Unit tests (Swift Testing) in `DiscScannerCoreTests`:
  - Size aggregation over a temp fixture directory tree (known file sizes),
    including symlink non-following and access-denied marking.
  - Treemap layout: squarified algorithm produces non-overlapping rects that
    tile the input area, ordered by size.
  - Deletion logic on temp directories: trash + permanent paths, tree pruning
    and size re-aggregation, partial-failure behavior.
- UI itself is verified manually (run the app, scan a folder, delete a test
  file).
