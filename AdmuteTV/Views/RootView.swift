import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .starting:
                ProgressView("Connecting to the studio…")
            case .connect(let error):
                ConnectView(initialError: error)
            case .ready:
                TabView {
                    LiveView().tabItem { Label("Live TV", systemImage: "tv") }
                    MultiSetupView().tabItem { Label("Multi-view", systemImage: "rectangle.split.2x2") }
                    RecapsView().tabItem { Label("Recaps", systemImage: "sportscourt") }
                    SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
                }
            }
        }
        .task { await model.start() }
    }
}
