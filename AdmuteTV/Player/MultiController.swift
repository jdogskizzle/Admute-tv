import AVFoundation
import Combine
import SwiftUI

/// Multi-view: one channel per tuner at once. The main channel has the sound. When it goes to
/// a commercial break, the sound and the big spot move to a side channel that isn't in one,
/// and go back to the main channel as soon as its break ends. Side channels in a break are
/// hidden (still playing, so they come back at once).
///
/// Breaks come from the studio (api/breaks) as clock times when viewers reach them, and the
/// studio stamps each piece of the stream with the same clock (EXT-X-PROGRAM-DATE-TIME), so
/// AVPlayerItem.currentDate() says whether what a tile shows right now is inside a break.
@MainActor
final class MultiController: ObservableObject, Identifiable {
    /// Shorter mutes (and sponsor lines) don't move the sound.
    static let breakLong: Double = 15

    let id = UUID()
    let model: AppModel
    @Published private(set) var tiles: [Tile] = []
    @Published private(set) var focus: Tile?
    @Published private(set) var shown: [Tile] = []

    private var loops: [Task<Void, Never>] = []
    private var stopped = false

    static var saved: [String?] {
        get { (UserDefaults.standard.string(forKey: "multi") ?? "").split(separator: ",", omittingEmptySubsequences: false).map { $0.isEmpty ? nil : String($0) } }
        set { UserDefaults.standard.set(newValue.map { $0 ?? "" }.joined(separator: ","), forKey: "multi") }
    }

    init(model: AppModel, count: Int) {
        self.model = model
        tiles = (0..<count).map { _ in Tile() }
        let pick = Self.saved
        for (i, t) in tiles.enumerated() where i < pick.count {
            if let n = pick[i], model.channel(n) != nil { t.num = n }
        }
        // every channel is named before any is asked for, so none stops another
        for t in tiles where t.num != nil { load(t) }
        decide()
        loops.append(Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshBreaks()
                try? await Task.sleep(for: .seconds(2))
            }
        })
        loops.append(Task { [weak self] in
            while !Task.isCancelled {
                self?.decide()
                try? await Task.sleep(for: .milliseconds(500))
            }
        })
    }

    var main: Tile? { tiles.first }
    private var keep: [String] { tiles.compactMap(\.num) }

    // MARK: - choosing channels

    func set(_ tile: Tile, to num: String?) {
        if let num, let other = tiles.first(where: { $0 !== tile && $0.num == num }) {
            return swap(tile, other)   // already on: trade places
        }
        tile.num = num
        load(tile)
        save()
        decide()
    }

    func makeMain(_ tile: Tile) {
        guard let m = main, tile !== m else { return }
        swap(m, tile)
    }

    /// Trades the players themselves (no retuning): the order is what's main and what's side.
    private func swap(_ a: Tile, _ b: Tile) {
        guard let i = tiles.firstIndex(where: { $0 === a }), let j = tiles.firstIndex(where: { $0 === b }) else { return }
        tiles.swapAt(i, j)
        focus = nil
        save()
        decide()
    }

    private func save() { Self.saved = tiles.map(\.num) }

    private func load(_ t: Tile) {
        t.breaks = nil
        t.failed = false
        guard let num = t.num, let api = model.api else {
            t.player.replaceCurrentItem(with: nil)
            t.message = nil
            return
        }
        t.message = "Tuning \(num)…"
        let item = AVPlayerItem(asset: AVURLAsset(url: api.liveURL(num, keep: keep),
                                                  options: [AVURLAssetHTTPCookiesKey: api.cookies]))
        item.automaticallyPreservesTimeOffsetFromLive = true
        item.configuredTimeOffsetFromLive = CMTime(value: 6, timescale: 1)
        item.preferredMaximumResolution = CGSize(width: 1280, height: 720)   // until it's the big one
        t.watch(item)
        t.player.replaceCurrentItem(with: item)
        t.player.play()
    }

    private func refreshBreaks() async {
        guard let api = model.api, let d = try? await api.breaks(), !stopped else { return }
        for t in tiles { t.breaks = t.num.flatMap { d.channels?[$0] } }
    }

    // MARK: - who has the sound

    func inBreak(_ t: Tile) -> (start: Double, end: Double?)? {
        guard t.num != nil, let p = t.playhead else { return nil }
        return t.breaks?.at(p, minLength: Self.breakLong)
    }

    /// Seconds left in a tile's break, when its end is known.
    func breakLeft(_ t: Tile) -> Int? {
        guard let b = inBreak(t), let e = b.end, let p = t.playhead else { return nil }
        return max(0, Int((e - p).rounded()))
    }

    private func watchable(_ t: Tile) -> Bool { t.num != nil && !t.failed && inBreak(t) == nil }

    func decide() {
        guard !stopped, let m = main else { return }
        let sides = tiles.dropFirst().filter { $0.num != nil }
        let f: Tile
        if m.num != nil && !m.failed && inBreak(m) == nil {
            f = m   // main is back: it takes over, whatever the sides are doing
        } else if let cur = focus, cur !== m, watchable(cur) {
            f = cur
        } else {
            f = sides.first(where: watchable) ?? (m.num != nil ? m : (sides.first ?? m))
        }
        focus = f
        shown = tiles.filter { $0 === f || ($0.num != nil && ($0 === m || inBreak($0) == nil)) }
        for t in tiles {
            let big = t === f
            if t.player.isMuted == big { t.player.isMuted = !big }
            let res = big ? CGSize.zero : CGSize(width: 1280, height: 720)   // zero: no limit
            if let item = t.player.currentItem, item.preferredMaximumResolution != res {
                item.preferredMaximumResolution = res
            }
        }
        objectWillChange.send()   // break countdowns
    }

    /// The channels hidden during their breaks, for the note at the bottom.
    var hidden: [String] { tiles.filter { t in t.num != nil && !shown.contains { $0 === t } }.compactMap(\.num) }

    /// Lets the tuners go: the studio stops converting 20 s after the last request.
    func stop() {
        guard !stopped else { return }
        stopped = true
        loops.forEach { $0.cancel() }
        for t in tiles {
            t.player.pause()
            t.player.replaceCurrentItem(with: nil)
        }
    }
}

/// One channel in the multi-view.
@MainActor
final class Tile: ObservableObject, Identifiable {
    let id = UUID()
    let player = AVPlayer()
    @Published var num: String?
    @Published var message: String?
    var failed = false
    var breaks: ChannelBreaks?
    private var statusObserver: NSKeyValueObservation?
    private var playObserver: NSKeyValueObservation?

    init() {
        player.isMuted = true
        playObserver = player.observe(\.timeControlStatus) { [weak self] p, _ in
            let playing = p.timeControlStatus == .playing
            Task { @MainActor in
                if playing { self?.message = nil; self?.failed = false }
            }
        }
    }

    /// The clock time of what this tile shows now, from the stream's stamps.
    var playhead: Double? { player.currentItem?.currentDate()?.timeIntervalSince1970 }

    func watch(_ item: AVPlayerItem) {
        statusObserver = item.observe(\.status) { [weak self] it, _ in
            guard it.status == .failed else { return }
            Task { @MainActor in
                guard let self, self.player.currentItem === it else { return }
                self.failed = true
                self.message = "\(self.num ?? "") stopped (maybe no free tuner). Pick it again to retry."
            }
        }
    }
}
