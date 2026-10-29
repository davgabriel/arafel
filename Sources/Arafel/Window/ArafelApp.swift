import AppKit
import SwiftUI

@main
struct ArafelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var studio = Studio()

    var body: some Scene {
        Window("Arafel", id: "main") {
            ContentView(studio: studio)
                .onAppear { delegate.studio = studio }
        }
        .windowStyle(.hiddenTitleBar)
        // Without these, relaunching after the window was closed shows no window at all.
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .defaultSize(width: 1280, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { studio.openPanel() }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Export…") { studio.exportPanel() }.keyboardShortcut("e").disabled(!studio.canExport)
            }
            CommandGroup(after: .pasteboard) {
                Button(Library.deleteTitle(max(1, studio.deleteTargets.count))) {
                    // While typing a color, ⌘⌫ erases the line there, as in any text field.
                    if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.deleteToBeginningOfLine(nil) } else { studio.deleteCommand() }
                }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(studio.deleteTargets.isEmpty)
            }
            CommandGroup(after: .toolbar) {
                Button("Invert") { studio.look.invert.toggle() }.keyboardShortcut("i").disabled(!studio.hasPhoto)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var studio: Studio?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    /// Quit (closing the window quits too) waits for an export being written. Blocking, not `.terminateLater`:
    /// a quit from inside a main-queue block would never see the export's completion, also a main-queue block.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { studio?.finishExport() }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { studio?.saveNow() }
    }
}
