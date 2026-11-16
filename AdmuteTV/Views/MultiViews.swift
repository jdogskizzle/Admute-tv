import AVFoundation
import SwiftUI

/// The Multi-view tab: pick a main channel and side channels (one per tuner), then start.
struct MultiSetupView: View {
    @EnvironmentObject var model: AppModel
    @State private var slots: [String?] = MultiController.saved
    @State private var picking: Slot?
    @State private var running: MultiController?

    struct Slot: Identifiable { let id: Int }

    private var count: Int { min(6, max(2, model.tuners ?? 2)) }

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(0..<count, id: \.self) { i in
                    Button { picking = Slot(id: i) } label: { slotRow(i) }
                        .buttonStyle(LiftStyle())
                }
                Button {
                    MultiController.saved = (0..<count).map { slot($0) }
                    running = MultiController(model: model, count: count)
                } label: {
                    Label("Start multi-view", systemImage: "rectangle.split.2x2.fill").frame(width: 500)
                }
                .disabled(slot(0) == nil)
                .padding(.top, 16)
            }
            .frame(width: 1000)
            VStack(alignment: .leading, spacing: 18) {
                Text("How it works").font(.headline)
                Group {
                    Text("One channel per tuner at once. The main channel is big and has the sound.")
                    Text("When it goes to a commercial break, the sound and the big picture move to a side channel that isn't in a break, and come back the moment the game does.")
                    Text("Side channels in a break are hidden until it ends.")
                    Text("While watching, click a channel to make it the main one or change it. Menu leaves.")
                }
                .font(.callout).foregroundStyle(.secondary)
                if model.tuners == nil {
                    Label("The proxy doesn't know how many tuners there are, so this shows 2. Set TUNER_COUNT on the admute service.",
                          systemImage: "info.circle")
                        .font(.callout).foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: 700, alignment: .leading)
        }
        .padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $picking) { s in
            ChannelPicker(allowNone: s.id > 0, current: slot(s.id)) { num in
                set(s.id, num)
                picking = nil
            }
        }
        .fullScreenCover(item: $running) { c in
            MultiView(controller: c).environmentObject(model)
        }
        .onChange(of: running == nil) { _, closed in if closed { slots = MultiController.saved } }
    }

    private func slot(_ i: Int) -> String? { i < slots.count ? slots[i] : nil }

    private func set(_ i: Int, _ num: String?) {
        while slots.count <= i { slots.append(nil) }
        if let num, let j = slots.firstIndex(of: num), j != i { slots[j] = slots[i] }   // trade places
        slots[i] = num
        MultiController.saved = slots
    }

    private func slotRow(_ i: Int) -> some View {
        let ch = slot(i).flatMap { model.channel($0) }
        return HStack(spacing: 26) {
            Text(i == 0 ? "Main" : "Side \(i)").font(.headline).frame(width: 130, alignment: .leading)
            if let ch {
                ChannelLogo(channel: ch, size: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(ch.num)  \(ch.name)").font(.caption.weight(.semibold)).opacity(0.7)
                    Text(ch.now?.title ?? "").font(.callout).lineLimit(1)
                }
            } else {
                Text(i == 0 ? "Pick a channel" : "None").font(.callout).opacity(0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26).padding(.vertical, 18)
        .frame(height: 100)
    }
}

/// A list of channels to pick from.
struct ChannelPicker: View {
    @EnvironmentObject var model: AppModel
    let allowNone: Bool
    let current: String?
    let pick: (String?) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if allowNone {
                    Button { pick(nil) } label: {
                        Text("None").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(24)
                    }
                    .buttonStyle(LiftStyle())
                }
                ForEach(model.channels) { ch in
                    Button { pick(ch.num) } label: {
                        HStack(spacing: 24) {
                            ChannelLogo(channel: ch, size: 50)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(ch.num)  \(ch.name)").font(.caption.weight(.semibold)).opacity(0.7)
                                Text(ch.now?.title ?? "No guide information").font(.headline).lineLimit(1)
                            }
                            Spacer()
                            if ch.num == current { Image(systemName: "checkmark") }
                        }
                        .padding(20)
                    }
                    .buttonStyle(LiftStyle())
                }
            }
            .padding(60)
        }
        .frame(width: 1100)
    }
}

/// The multi-view itself, full screen.
struct MultiView: View {
    @ObservedObject var controller: MultiController
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var acting: Tile?
    @State private var picking: Tile?

    var body: some View {
        GeometryReader { g in
            let frames = layout(g.size)
            ZStack(alignment: .topLeading) {
                Color.black
                ForEach(controller.tiles) { t in
                    let on = controller.shown.contains { $0 === t }
                    let r = frames[t.id] ?? .zero
                    Button { act(on: t) } label: {
                        TileView(tile: t, controller: controller, big: controller.focus === t)
                    }
                    .buttonStyle(TileStyle())
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX, y: r.midY)
                    .opacity(on ? 1 : 0)
                    .disabled(!on)
                }
                if !controller.hidden.isEmpty {
                    Text("\(controller.hidden.joined(separator: ", ")) hidden during a break")
                        .font(.caption).foregroundStyle(.secondary)
                        .position(x: g.size.width / 2, y: g.size.height - 30)
                }
            }
            .animation(.easeInOut(duration: 0.45), value: controller.shown.map(\.id))
            .animation(.easeInOut(duration: 0.45), value: controller.focus?.id)
        }
        .ignoresSafeArea()
        .confirmationDialog(acting.flatMap { $0.num }.map { "\($0) \(model.channel($0)?.name ?? "")" } ?? "",
                            isPresented: Binding(get: { acting != nil }, set: { if !$0 { acting = nil } }),
                            presenting: acting) { t in
            if t !== controller.main {
                Button("Make it the main channel") { controller.makeMain(t) }
            }
            Button("Change channel…") { picking = t }
            if t !== controller.main {
                Button("Remove", role: .destructive) { controller.set(t, to: nil) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $picking) { t in
            ChannelPicker(allowNone: t !== controller.main, current: t.num) { num in
                controller.set(t, to: num)
                picking = nil
            }
        }
        .onExitCommand { leave() }
        .onDisappear { controller.stop() }
    }

    private func act(on t: Tile) {
        if t.num == nil { picking = t } else { acting = t }
    }

    private func leave() {
        controller.stop()
        dismiss()
    }

    /// The big tile on the left, the rest in a column on the right, all 16:9. Hidden ones
    /// keep a spot (invisible) so they slide back in.
    private func layout(_ size: CGSize) -> [UUID: CGRect] {
        let pad: CGFloat = 60, gap: CGFloat = 30
        let w = size.width - 2 * pad, h = size.height - 2 * pad
        var out: [UUID: CGRect] = [:]
        guard let f = controller.focus else { return out }
        let others = controller.shown.filter { $0 !== f }
        let wf = others.isEmpty ? w : (w - gap) * 0.7
        let hf = min(h, wf * 9 / 16)
        let fw = hf * 16 / 9
        out[f.id] = CGRect(x: pad + (others.isEmpty ? (w - fw) / 2 : 0), y: pad + (h - hf) / 2, width: fw, height: hf)
        let n = CGFloat(max(1, others.count))
        let colW = w - gap - wf
        let hs = min(colW * 9 / 16, (h - gap * (n - 1)) / n)
        let ws = hs * 16 / 9
        var y = pad + (h - (n * hs + gap * (n - 1))) / 2
        for o in others {
            out[o.id] = CGRect(x: pad + wf + gap, y: y, width: ws, height: hs)
            y += hs + gap
        }
        for t in controller.tiles where out[t.id] == nil {
            out[t.id] = CGRect(x: pad + w - ws, y: pad + h - hs, width: ws, height: hs)
        }
        return out
    }
}

struct TileView: View {
    @ObservedObject var tile: Tile
    @ObservedObject var controller: MultiController
    @EnvironmentObject var model: AppModel
    let big: Bool

    var body: some View {
        let ch = tile.num.flatMap { model.channel($0) }
        ZStack(alignment: .bottomLeading) {
            Color.black
            VideoLayer(player: tile.player)
            if let m = tile.message ?? (tile.num == nil ? "Pick a main channel" : nil) {
                Text(m).font(big ? .headline : .caption).multilineTextAlignment(.center).padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let num = tile.num {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text("\(num)  \(ch?.name ?? "")").fontWeight(.bold)
                        if tile === controller.main { Badge(text: "Main") }
                        if big { Badge(text: "Sound", icon: "speaker.wave.2.fill", color: .green) }
                        if controller.inBreak(tile) != nil {
                            Badge(text: "Break" + (controller.breakLeft(tile).map { " \($0)s" } ?? ""), color: Theme.muted)
                        }
                    }
                    if big, let p = ch?.now {
                        Text(p.subtitle.map { "\(p.title) · \($0)" } ?? p.title).opacity(0.8).lineLimit(1)
                    }
                }
                .font(big ? .callout : .caption2)
                .padding(big ? 24 : 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: big ? 20 : 14, style: .continuous))
    }
}

/// A tile under focus gets an outline instead of the usual white platter, so the picture shows.
struct TileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TileBody(configuration: configuration)
    }

    struct TileBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: focused ? 6 : 0))
                .scaleEffect(configuration.isPressed ? 0.99 : (focused ? 1.015 : 1))
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// An AVPlayer's picture, without the system player's controls (several play at once here).
struct VideoLayer: UIViewRepresentable {
    let player: AVPlayer

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.backgroundColor = .black
        v.playerLayer.videoGravity = .resizeAspect
        v.playerLayer.player = player
        return v
    }

    func updateUIView(_ v: PlayerView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }
}
