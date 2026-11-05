import AppKit
import Foundation

/// Runs the AppKit application with no storyboard and no SwiftUI app scene.
///
/// The window is a custom borderless `NSPanel` because it is a transient clipboard palette:
/// it should be keyable for the search field, float above normal work, and hide when the user
/// clicks elsewhere. A SwiftUI `WindowGroup` cannot give us that shape reliably.
public enum PasteApplication {
    @MainActor
    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
