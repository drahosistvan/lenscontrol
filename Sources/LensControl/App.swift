import SwiftUI

@main
struct LensControlApp: App {
    static let windowID = "main"

    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView(presentation: .popover)
                .environment(delegate.model)
        } label: {
            MenuBarLabel()
                .environment(delegate.model)
        }
        .menuBarExtraStyle(.window)

        // Same panel as a floating window, for keeping it beside a call all session.
        Window("LensControl", id: Self.windowID) {
            ContentView(presentation: .window)
                .environment(delegate.model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
    }
}

/// The aperture glyph, dimmed while the camera was last seen missing.
struct MenuBarLabel: View {
    @Environment(CameraModel.self) private var model

    var body: some View {
        Image(nsImage: model.connection == .noCamera ? MenuBarIcon.dimmed : MenuBarIcon.normal)
    }
}

/// Owns the model so the camera session can be closed cleanly on quit —
/// otherwise the camera is left with USB live view running.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = CameraModel()

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
