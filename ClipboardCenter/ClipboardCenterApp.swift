import SwiftUI

// MARK: - App Entry Point
// The app uses @NSApplicationDelegateAdaptor to bridge SwiftUI with AppKit,
// allowing us to manage the NSStatusItem and NSPopover from the AppDelegate.

@main
struct ClipboardCenterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We use a Settings scene as a placeholder — the real UI lives in the NSPopover.
        // A MenuBarExtra could be used on macOS 13+, but NSPopover gives us full
        // control over sizing, animations, and dismissal behavior.
        Settings {
            EmptyView()
        }
    }
}
