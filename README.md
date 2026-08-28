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

## Note on rebuilds and Full Disk Access

The app is ad-hoc signed, so every `make app` produces a binary macOS treats
as a *new* app for privacy (TCC) purposes. If Full Disk Access stops working
after a rebuild even though the toggle looks enabled: remove the app from the
Full Disk Access list (or toggle it off and on again), re-add
`build/DiscScanner.app`, and restart the app. Grants also only take effect
after an app restart.
