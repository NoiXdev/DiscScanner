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
        .commands {
            // Next to "About DiscScanner", where a Mac app keeps this.
            CommandGroup(after: .appInfo) {
                Button(L("update.check")) {
                    appState.checkForUpdates(force: true)
                }
                .disabled(appState.isCheckingForUpdates)
            }
        }
    }
}
