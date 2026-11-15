import SwiftUI

/// Every game's recap. Plays are listed by their set-up only, so nothing gives a result away.
struct RecapsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.recaps.isEmpty {
            ContentUnavailableView("No recaps yet", systemImage: "sportscourt",
                                   description: Text("Recaps of football games are made while they're recorded, and show up here as plays happen."))
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 34) {
                    ForEach(model.recaps) { r in row(r) }
                }
                .padding(.vertical, 30).padding(.horizontal, 30)
            }
        }
    }

    private func row(_ r: Recap) -> some View {
        let key = r.clips(level: 1), all = r.clips(level: 2)
        let on = r.live ? model.channel(for: r) : nil
        return HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    Text(r.displayTitle).font(.title3.bold()).lineLimit(1)
                    if r.live { Badge(text: "LIVE", color: .red) }
                }
                Text("\(all.count) plays · \(runtime(all))\(on.map { " · on \($0.num) \($0.name) now" } ?? "")")
                    .font(.callout).foregroundStyle(.secondary)
                Text(Date(timeIntervalSince1970: r.updated).formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if !key.isEmpty {
                Button { Watch.recap(r, level: 1, model: model) } label: {
                    Label("Scores & turnovers · \(runtime(key))", systemImage: "backward.circle")
                }
            }
            Button { Watch.recap(r, level: 2, model: model) } label: {
                Label("All highlights · \(runtime(all))", systemImage: "list.bullet.rectangle")
            }
        }
        .padding(30)
        .background(RoundedRectangle(cornerRadius: 24).fill(Theme.panel))
    }
}
