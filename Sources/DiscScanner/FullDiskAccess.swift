import AppKit
import Foundation

/// Heuristic Full Disk Access detection. macOS offers no official API, so we
/// probe TCC-protected locations; any successful read means FDA is granted.
/// A false negative only re-shows the startup hint, never blocks the app.
enum FullDiskAccess {
    static var isGranted: Bool {
        let probes = [
            NSHomeDirectory() + "/Library/Safari",
            "/Library/Application Support/com.apple.TCC/TCC.db",
        ]
        for path in probes {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                if (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil {
                    return true
                }
            } else if let handle = FileHandle(forReadingAtPath: path) {
                try? handle.close()
                return true
            }
        }
        return false
    }

    static func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
