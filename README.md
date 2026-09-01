# DiscScanner

**See what is eating your disk space — a fast, native disk-usage scanner
for the Mac.**

Pick a folder or a whole volume and watch the results fill in live while
the scan runs: every folder and file sorted by size, as an expandable tree
or as a treemap. Found the space hog? Delete it right there — to the Trash,
or permanently.

## Features

- **Live scanning** — results appear while the scan is still running:
  the tree grows, sizes count up, and a status line shows elapsed time.
  Scanning a whole volume also shows percent done and a remaining-time
  estimate. Cancel any time and keep the partial result.
- **Details view** — the Finder's list view over scan data: sortable by
  size (the default), name, type or date, with disclosure triangles for
  what is below, a size bar per row, and a double-click to step into a
  folder. A breadcrumb walks back out.
- **Treemap view** — the classic mosaic: big files are big rectangles.
  Double-click zooms into a folder, a breadcrumb takes you back up.
- **Delete from the app** — single or multi-selection, with a clear
  choice between **Move to Trash** (undoable) and **Delete Permanently**
  (with a warning). Sizes update immediately, no rescan needed.
- **Reveal in Finder** from both views.
- **Chart** — the current folder as a pie, donut or bar chart, with free
  space in the picture for a whole volume. The legend lists share and
  size, and clicking a folder drills into it; a breadcrumb takes you back.
  Allocated or logical size, style, number of slices and grouping of
  loose files are all settings, and they are remembered.
- **Statistics tabs** — **Extensions** (what file types eat the disk),
  **Users** (which owner), **Age of Files** (what has not been touched in
  years) and **Top Files** (the biggest single files), each a sortable
  table.
- **Save scans and compare them** — keep a scan as a `.dscan` file and
  open it again later, in every tab. The **History** tab compares two of
  them — or a saved one against the scan on screen — and lists what grew,
  shrank, appeared and vanished, biggest change first.
- **Protected folders are handled gracefully** — anything unreadable is
  marked and skipped, never a crash or an aborted scan, with a hint on
  how to grant Full Disk Access for complete volume scans.
- **English and German** interface.

## Install

1. Download the latest DMG from the [releases page](https://github.com/NoiXdev/DiscScanner/releases).
2. Open it and drag **DiscScanner** into **Applications**.
3. Requires macOS 14 or newer. The app is signed and notarized.

## Full Disk Access

To scan protected areas (other users' folders, parts of the system
volume), grant the app Full Disk Access: **System Settings → Privacy &
Security → Full Disk Access** → add DiscScanner, then restart the app.
The app offers this at first launch, too. Without it, unreadable folders
are simply marked and skipped.

Note: a handful of system-protected folders remain unreadable even with
Full Disk Access — the scan summary counts them, and that is normal.

## Notes

- Sizes are allocated-on-disk bytes, so totals can differ slightly from
  the Finder's "logical" sizes. The chart and the statistics tables can
  show logical sizes instead.
- Saved scans live in `~/Library/Application Support/DiscScanner/Scans`.
  They keep the whole tree, so a full volume scan is a large file even
  compressed; delete the ones you no longer need in the History tab.
- Deleting to the Trash can be undone in the Finder; permanent deletion
  cannot.

## Building from source

Requires macOS 14+ and the Xcode 16+ command line tools.

    make run        # builds build/DiscScanner.app (ad-hoc signed) and opens it
    make test       # runs the unit test suite
    swift run       # development run without bundling

Release artifacts (signed, notarized, universal DMG) are produced by
`scripts/release` — maintainer credentials required; CI builds them from
tags automatically.

For development builds only: the ad-hoc signature changes on every
rebuild, so macOS treats each build as a new app for privacy (TCC)
purposes. If Full Disk Access stops applying after a rebuild, remove and
re-add the app in the Full Disk Access list, then restart it. Released
builds are Developer ID signed and keep their grants.

## License

[MIT](LICENSE)
