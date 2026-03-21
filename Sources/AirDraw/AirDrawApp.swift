import SwiftUI

@main
struct AirDrawApp: App {

    var body: some Scene {
        WindowGroup("AirDraw — Рисование в воздухе") {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Рисунок") {
                Button("Отменить (Cmd+Z)") { }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Очистить холст") { }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
    }
}
