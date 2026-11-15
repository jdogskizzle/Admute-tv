import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            VStack(alignment: .leading, spacing: 30) {
                info("Studio", model.server)
                if !model.username.isEmpty { info("Signed in as", model.username) }
                info("Ad-muting delay", "\(Int(model.delay)) seconds behind live")
                info("Channels", "\(model.channels.count)")
                HStack(spacing: 30) {
                    Button { Task { await model.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    Button(role: .destructive) { model.signOut() } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }
                }
                .padding(.top, 20)
            }
            .frame(maxWidth: 800, alignment: .leading)
            VStack(alignment: .leading, spacing: 18) {
                Text("Remote").font(.headline)
                Group {
                    Text("Click a channel to watch it. Menu goes back to the guide.")
                    Text("While watching, swipe down for Channels (or Plays in a recap), and click the transport bar's buttons to catch up, skip plays or go back to live.")
                    Text("A TV remote's channel buttons change channel, or skip plays in a recap.")
                    Text("Captions: swipe down, then Subtitles.")
                }
                .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 800, alignment: .leading)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func info(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.title3)
        }
    }
}
