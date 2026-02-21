import SwiftUI
import AppKit

@main
struct GraphAlfredApp: App {
    @StateObject private var viewModel = GraphViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 1080, minHeight: 760)
                .onAppear {
                    // `NSApp` can be nil during `App` init; activate once the app is running.
                    let app = NSApplication.shared
                    app.setActivationPolicy(.regular)
                    app.activate(ignoringOtherApps: true)
                }
        }
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    viewModel.undoLastAction()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!viewModel.canUndo)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    viewModel.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("Graph") {
                Button("New Note") {
                    viewModel.createNote()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Auto Align") {
                    Task {
                        await viewModel.autoAlign()
                    }
                }
            }

            CommandMenu("Search") {
                Button("Quick Search (Window)") {
                    viewModel.showSearch()
                }
                .keyboardShortcut(viewModel.settings.inAppSearchShortcut.keyEquivalent, modifiers: [.command])

                Button("Global Hotkey: \(viewModel.settings.globalSearchHotKey.title)") {}
                    .disabled(true)
            }
        }
    }
}
