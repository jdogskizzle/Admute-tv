import SwiftUI

/// The guide: channels down the left, what's on the focused one on the right. Click a channel
/// to watch it; move right for "Catch up" when its game has a recap.
struct LiveView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("lastChannel") private var lastChannel = ""
    @FocusState private var focused: String?
    @State private var shown: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if let p = model.problem {
                Label(p, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(Theme.muted)
            }
            if model.channels.isEmpty {
                ContentUnavailableView("No channels", systemImage: "antenna.radiowaves.left.and.right",
                                       description: Text("The studio lists no channels. Check that the admute proxy is running and CHANNELS is set."))
            } else {
                HStack(alignment: .top, spacing: 70) {
                    guide.frame(width: 780)
                    detail(model.channel(shown ?? lastChannel) ?? model.channels.first)
                }
            }
        }
        .onChange(of: focused) { _, new in if let new { shown = new } }
    }

    // MARK: guide

    private var guide: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 22) {
                ForEach(model.channels) { ch in
                    Button { watch(ch.num) } label: { row(ch) }
                        .buttonStyle(LiftStyle())
                        .focused($focused, equals: ch.num)
                }
            }
            .padding(.vertical, 30).padding(.horizontal, 30)
        }
        .defaultFocus($focused, model.channel(lastChannel)?.num ?? model.channels.first?.num)
    }

    private func row(_ ch: Channel) -> some View {
        HStack(spacing: 26) {
            ChannelLogo(channel: ch, size: 64)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("\(ch.num)  \(ch.name)").font(.caption.weight(.semibold)).opacity(0.7)
                    if ch.isMuted { Image(systemName: "speaker.slash.fill").font(.caption).foregroundStyle(Theme.muted) }
                    if model.recap(for: ch) != nil { Image(systemName: "sportscourt.fill").font(.caption).opacity(0.7) }
                }
                Text(ch.now?.title ?? "No guide information").font(.headline).lineLimit(1)
                if let p = ch.now { ProgressLine(value: p.progress(at: model.now), height: 5) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26).padding(.vertical, 20)
        .frame(height: 130)
    }

    // MARK: detail

    @ViewBuilder
    private func detail(_ ch: Channel?) -> some View {
        if let ch {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 28) {
                    ChannelLogo(channel: ch, size: 90)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(ch.num)  \(ch.name)").font(.title3.weight(.semibold))
                        if ch.isMuted { Badge(text: "Ad break · muted", icon: "speaker.slash.fill", color: Theme.muted) }
                    }
                }
                if let p = ch.now {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(p.title).font(.system(size: 60, weight: .bold)).lineLimit(2)
                        if let s = p.subtitle, !s.isEmpty { Text(s).font(.title3).foregroundStyle(.secondary).lineLimit(2) }
                    }
                    HStack(spacing: 30) {
                        Text(timeRange(p))
                        Text(minutesLeft(p, now: model.now)).foregroundStyle(.secondary)
                    }
                    .font(.callout.monospacedDigit())
                    ProgressLine(value: p.progress(at: model.now), height: 8).frame(maxWidth: 700)
                    if let d = p.desc, !d.isEmpty {
                        Text(d).font(.callout).foregroundStyle(.secondary).lineLimit(4).frame(maxWidth: 900, alignment: .leading)
                    }
                } else {
                    Text("No guide information").font(.title2).foregroundStyle(.secondary)
                }
                if let n = ch.next {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("UP NEXT").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        Text("\(n.startDate.formatted(date: .omitted, time: .shortened))   \(n.title)").font(.callout)
                    }
                }
                Spacer(minLength: 0)
                actions(ch)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, 30)
        }
    }

    private func actions(_ ch: Channel) -> some View {
        HStack(spacing: 30) {
            Button { watch(ch.num) } label: { Label("Watch live", systemImage: "play.fill") }
            Button { lastChannel = ch.num; model.startMulti(main: ch.num) } label: {
                Label("Multi-view", systemImage: "rectangle.split.2x2")
            }
            if let r = model.recap(for: ch) {
                let key = r.clips(level: 1), all = r.clips(level: 2)
                if !key.isEmpty {
                    Button { recap(r, 1, ch) } label: { Label("Scores & turnovers · \(runtime(key))", systemImage: "backward.circle") }
                }
                Button { recap(r, 2, ch) } label: { Label("All highlights · \(runtime(all))", systemImage: "list.bullet.rectangle") }
            }
        }
    }

    private func watch(_ num: String) {
        lastChannel = num
        Watch.live(num, model: model)
    }

    private func recap(_ r: Recap, _ level: Int, _ ch: Channel) {
        lastChannel = ch.num
        Watch.recap(r, level: level, model: model)
    }
}
