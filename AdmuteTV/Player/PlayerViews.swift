import SwiftUI

/// Drawn over the picture (under the system's controls); never takes focus.
struct PlayerOverlay: View {
    @ObservedObject var controller: PlayerController
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            if let message = controller.failure ?? controller.tuning {
                tuningPanel(message, failed: controller.failure != nil)
            }
            VStack {
                HStack {
                    Spacer()
                    if controller.adBreak {
                        Badge(text: "Ad muted", icon: "speaker.slash.fill", color: Theme.muted)
                            .transition(.opacity)
                    }
                }
                Spacer()
                if let card = controller.card {
                    lowerThird(card).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 90).padding(.vertical, 60)
        }
        .animation(.easeInOut(duration: 0.3), value: controller.card)
        .animation(.easeInOut(duration: 0.3), value: controller.adBreak)
    }

    private func tuningPanel(_ message: String, failed: Bool) -> some View {
        let ch = controller.liveNum.flatMap { model.channel($0) }
        return VStack(spacing: 28) {
            if let ch { ChannelLogo(channel: ch, size: 120) }
            if let p = ch?.now {
                Text(p.title).font(.title2.bold())
                if let s = p.subtitle, !s.isEmpty { Text(s).foregroundStyle(.secondary) }
            }
            HStack(spacing: 16) {
                if !failed { ProgressView() }
                Text(message).font(.headline)
            }
            if !failed {
                Text("The picture starts once the \(Int(model.delay)) s ad-muting delay has built up.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(60)
        .frame(maxWidth: 1100)
        .background(RoundedRectangle(cornerRadius: 36).fill(.ultraThinMaterial))
    }

    private func lowerThird(_ card: PlayerController.Card) -> some View {
        HStack(spacing: 24) {
            RoundedRectangle(cornerRadius: 3).fill(card.kind == .result ? Theme.accent : Color.white.opacity(0.6))
                .frame(width: 6)
            VStack(alignment: .leading, spacing: 8) {
                Text(card.title).font(.title3.bold())
                if !card.detail.isEmpty {
                    Text(card.detail).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 32).padding(.vertical, 22)
        .frame(maxWidth: 1200, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The info panel's "Channels" tab (swipe down while watching): change channel in place.
struct ChannelsTab: View {
    @ObservedObject var controller: PlayerController
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 40) {
                    ForEach(model.channels) { ch in
                        Button { controller.playLive(ch.num) } label: { tile(ch) }
                            .buttonStyle(LiftStyle())
                            .id(ch.num)
                    }
                }
                .padding(.horizontal, 90).padding(.vertical, 40)
            }
            .onAppear { if let n = controller.liveNum { scroll.scrollTo(n, anchor: .center) } }
        }
    }

    private func tile(_ ch: Channel) -> some View {
        let on = controller.liveNum == ch.num
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                ChannelLogo(channel: ch, size: 50)
                Spacer()
                if on { Badge(text: "Watching") } else if ch.isMuted { Badge(text: "Ad break", color: Theme.muted) }
            }
            Text("\(ch.num)  \(ch.name)").font(.caption).foregroundStyle(.secondary)
            Text(ch.now?.title ?? "No guide information").font(.headline).lineLimit(1)
            if let p = ch.now { ProgressLine(value: p.progress(at: model.now), height: 5) }
        }
        .padding(24)
        .frame(width: 420, height: 230, alignment: .topLeading)
    }
}

/// The info panel's "Plays" tab during a recap. Plays not watched yet show only their set-up.
struct PlaysTab: View {
    @ObservedObject var controller: PlayerController

    var body: some View {
        if let run = controller.run {
            ScrollViewReader { scroll in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 40) {
                        ForEach(Array(run.clips.enumerated()), id: \.element.id) { i, c in
                            Button { controller.jump(to: i) } label: { tile(c, i: i, current: i == run.i) }
                                .buttonStyle(LiftStyle())
                                .id(i)
                        }
                    }
                    .padding(.horizontal, 90).padding(.vertical, 40)
                }
                .onAppear { scroll.scrollTo(run.i, anchor: .center) }
            }
        }
    }

    private func tile(_ c: RecapClip, i: Int, current: Bool) -> some View {
        let watched = controller.seen.contains(c.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(c.when ?? "").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                if current { Badge(text: "Now") }
            }
            Text(watched ? (c.text ?? c.setup) : c.setup).font(.headline).lineLimit(3)
            Spacer(minLength: 0)
            Text(watched ? (c.score ?? "") : (c.before ?? "")).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 440, height: 230, alignment: .topLeading)
    }
}
