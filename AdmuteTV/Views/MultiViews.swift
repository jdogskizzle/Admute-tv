import AVFoundation
import SwiftUI

/// The Multi-view tab: pick a main channel and side channels (one per tuner), then start.
struct MultiSetupView: View {
    @EnvironmentObject var model: AppModel
    @State private var slots: [String?] = MultiController.saved
    @State private var picking: Slot?
    @AppStorage("multiPip") private var pip = false

    struct Slot: Identifiable { let id: Int }

    private var count: Int { model.multiCount }

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(0..<count, id: \.self) { i in
                    Button { picking = Slot(id: i) } label: { slotRow(i) }
                        .buttonStyle(LiftStyle())
                }
                Toggle("Picture in picture", isOn: $pip)
                    .padding(.top, 10)
                Button {
                    MultiController.saved = (0..<count).map { slot($0) }
                    model.startMulti(main: nil)
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
                    Text("While watching, move with the remote to pick a channel and click it to make it the main one, change it, add another or switch layout. Menu leaves.")
                    Text("You can also start it from a channel you're watching: in the player's controls, or Multi-view in the guide.")
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
        .onChange(of: model.multi == nil) { _, closed in if closed { slots = MultiController.saved } }
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
///
/// Two layouts: side by side (the big channel on the left, the others in a column on the
/// right, together as wide as the screen) or picture in picture (the big channel full
/// screen, the others small in the corner). The remote moves a selection between them; the
/// selection and the channels' names show only while the remote is being used.
struct MultiView: View {
    @ObservedObject var controller: MultiController
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("multiPip") private var pip = false
    @State private var selected: Slot?
    @State private var awake = true
    @State private var sleeper: Task<Void, Never>?
    @State private var acting: Tile?
    @State private var picking: Tile?

    enum Slot: Hashable {
        case tile(UUID)
        case add
    }

    var body: some View {
        GeometryReader { g in
            let frames = layout(g.size)
            Button { press() } label: {
                ZStack(alignment: .topLeading) {
                    Color.black
                    ForEach(controller.tiles) { t in
                        let r = frames[.tile(t.id)] ?? .zero
                        let picked = awake && selected == .tile(t.id)
                        TileView(tile: t, controller: controller, big: controller.focus === t, picked: picked)
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                            .opacity(isShown(t) ? 1 : 0)
                            .zIndex(controller.focus === t ? 0 : 1)
                    }
                    if let r = frames[.add] {
                        AddTile(picked: selected == .add)
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                            .zIndex(2)
                            .transition(.opacity)
                    }
                    if awake && !controller.hidden.isEmpty {
                        Text("\(controller.hidden.joined(separator: ", ")) hidden during a break")
                            .font(.caption).foregroundStyle(.secondary)
                            .position(x: g.size.width / 2, y: g.size.height - 30)
                            .zIndex(3)
                    }
                }
                .frame(width: g.size.width, height: g.size.height)
            }
            .buttonStyle(Bare())
            .onMoveCommand { move($0, frames) }
            .animation(.easeInOut(duration: 0.45), value: controller.shown.map(\.id))
            .animation(.easeInOut(duration: 0.45), value: controller.focus?.id)
            .animation(.easeInOut(duration: 0.3), value: awake)
            .animation(.easeInOut(duration: 0.45), value: pip)
        }
        .ignoresSafeArea()
        .confirmationDialog(acting.flatMap { $0.num }.map { "\($0) \(model.channel($0)?.name ?? "")" } ?? "",
                            isPresented: Binding(get: { acting != nil }, set: { if !$0 { acting = nil; wake() } }),
                            presenting: acting) { t in
            if t !== controller.main {
                Button("Make it the main channel") { controller.makeMain(t) }
            }
            Button("Change channel…") { picking = t }
            if let free = controller.freeTile {
                Button("Add a channel…") { picking = free }
            }
            if t !== controller.main {
                Button("Remove", role: .destructive) { controller.set(t, to: nil) }
            }
            Button(pip ? "Side by side" : "Picture in picture") { pip.toggle() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $picking, onDismiss: wake) { t in
            ChannelPicker(allowNone: t !== controller.main, current: t.num) { num in
                controller.set(t, to: num)
                picking = nil
            }
        }
        .onPlayPauseCommand { wake() }
        .onExitCommand { leave() }
        .onAppear { wake() }
        .onDisappear { controller.stop() }
    }

    // MARK: - remote

    private func wake() {
        awake = true
        if selected == nil || !visible.contains(selected!) {
            selected = controller.focus.map { .tile($0.id) }
        }
        sleeper?.cancel()
        sleeper = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled && acting == nil && picking == nil { awake = false }
        }
    }

    private func press() {
        guard awake else { return wake() }   // the first click just brings the selection back
        wake()
        switch selected {
        case .add: picking = controller.freeTile
        case .tile(let id):
            if let t = controller.tiles.first(where: { $0.id == id }) {
                if t.num == nil { picking = t } else { acting = t }
            }
        case nil: break
        }
    }

    /// To the nearest tile in that direction (by their centres), so it works the same in
    /// both layouts, where the small tiles may sit on top of the big one.
    private func move(_ d: MoveCommandDirection, _ frames: [Slot: CGRect]) {
        let wasAwake = awake
        wake()
        guard wasAwake, let cur = selected, let r = frames[cur] else { return }
        let c = CGPoint(x: r.midX, y: r.midY)
        var best: (Slot, CGFloat)?
        for s in visible where s != cur {
            guard let f = frames[s] else { continue }
            let dx = f.midX - c.x, dy = f.midY - c.y
            let v: (along: CGFloat, across: CGFloat)
            switch d {
            case .right: v = (dx, dy)
            case .left: v = (-dx, dy)
            case .down: v = (dy, dx)
            case .up: v = (-dy, dx)
            @unknown default: continue
            }
            let along = v.along, across = v.across
            guard along > 1 else { continue }
            let cost = along + 2 * abs(across)
            if best == nil || cost < best!.1 { best = (s, cost) }
        }
        if let b = best { selected = b.0 }
    }

    private func leave() {
        controller.stop()
        dismiss()
    }

    // MARK: - layout

    private func isShown(_ t: Tile) -> Bool { controller.shown.contains { $0 === t } }

    /// What can be selected: the shown tiles, and "Add channel" while a tuner is free.
    private var visible: [Slot] {
        var out = controller.shown.map { Slot.tile($0.id) }
        if awake && controller.freeTile != nil { out.append(.add) }
        return out
    }

    private func layout(_ size: CGSize) -> [Slot: CGRect] {
        let w = size.width, h = size.height, gap: CGFloat = 12
        var out: [Slot: CGRect] = [:]
        guard let f = controller.focus else { return out }
        let others = controller.shown.filter { $0 !== f }
        let small = others.map { Slot.tile($0.id) } + (awake && controller.freeTile != nil ? [Slot.add] : [])

        if pip || small.isEmpty {
            // the big one fills the width; the rest small in the bottom-right corner, going up
            let hf = min(h, w * 9 / 16)
            out[.tile(f.id)] = CGRect(x: 0, y: (h - hf) / 2, width: w, height: hf)
            let ws = w / 4.5, hs = ws * 9 / 16, margin: CGFloat = 50
            for (i, s) in small.enumerated() {
                let col = CGFloat(i / 4), row = CGFloat(i % 4)
                out[s] = CGRect(x: w - margin - ws - col * (ws + gap), y: h - margin - hs - row * (hs + gap),
                                width: ws, height: hs)
            }
        } else {
            // side by side: the column as wide as fits its tiles (up to 30%), the big one the rest
            let n = CGFloat(small.count)
            let ws = min(w * 0.3, (h - gap * (n - 1)) / n * 16 / 9)
            let wf = w - gap - ws
            let hf = min(h, wf * 9 / 16)
            out[.tile(f.id)] = CGRect(x: 0, y: (h - hf) / 2, width: wf, height: hf)
            let hs = ws * 9 / 16
            var y = (h - (n * hs + gap * (n - 1))) / 2
            for s in small {
                out[s] = CGRect(x: w - ws, y: y, width: ws, height: hs)
                y += hs + gap
            }
        }
        // hidden ones (in a break) wait, invisible, where the column ends
        let spare = out.values.filter { $0.width < w * 0.5 }.max { $0.minY < $1.minY }
            ?? CGRect(x: w * 0.75, y: h * 0.75, width: w * 0.25, height: w * 0.25 * 9 / 16)
        for t in controller.tiles where out[.tile(t.id)] == nil { out[.tile(t.id)] = spare }
        return out
    }
}

struct TileView: View {
    @ObservedObject var tile: Tile
    @ObservedObject var controller: MultiController
    @EnvironmentObject var model: AppModel
    let big: Bool
    let picked: Bool

    var body: some View {
        let ch = tile.num.flatMap { model.channel($0) }
        ZStack(alignment: .bottomLeading) {
            Color.black
            VideoLayer(player: tile.player)
            if let m = tile.message {
                Text(m).font(big ? .headline : .caption).multilineTextAlignment(.center).padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.4))
            }
            // only on the selected one, only while the remote is in use
            if picked, let num = tile.num {
                HStack(spacing: 10) {
                    Text("\(num)  \(ch?.name ?? "")").fontWeight(.bold)
                    if tile === controller.main { Badge(text: "Main") }
                    if big { Image(systemName: "speaker.wave.2.fill") }
                    if controller.inBreak(tile) != nil {
                        Badge(text: "Break" + (controller.breakLeft(tile).map { " \($0)s" } ?? ""), color: Theme.muted)
                    }
                }
                .font(big ? .callout : .caption2)
                .padding(big ? 24 : 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                .transition(.opacity)
            }
        }
        .overlay(Rectangle().strokeBorder(Theme.accent, lineWidth: picked ? 6 : 0))
    }
}

/// Where another channel can go while a tuner is free.
struct AddTile: View {
    let picked: Bool

    var body: some View {
        ZStack {
            Color.white.opacity(picked ? 0.25 : 0.1)
            Label("Add channel", systemImage: "plus").font(.callout.weight(.semibold))
        }
        .overlay(Rectangle().strokeBorder(Theme.accent, lineWidth: picked ? 6 : 0))
    }
}

/// No focus look at all: the multi-view draws its own selection.
struct Bare: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
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
