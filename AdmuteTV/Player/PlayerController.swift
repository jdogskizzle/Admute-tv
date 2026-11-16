import AVKit
import Combine
import SwiftUI

/// The full-screen player: a channel live, or a game's recap played clip after clip.
///
/// It's the system player (AVPlayerViewController), so the Siri Remote works as people expect:
/// click to pause, swipe down for the info panel, Menu to go back to the guide. Added to it:
/// - a "Channels" tab in the info panel (swipe down) to change channel without leaving,
///   or "Plays" during a recap,
/// - "Catch up" / "Next play" / "Back to live" buttons in the transport bar,
/// - channel up/down from a TV remote's channel buttons (or previous/next play in a recap),
/// - an overlay: "Tuning…" while the delay builds up, "Ad muted" during a muted break, and in
///   a recap the play's set-up first and its result only in the last seconds (no spoilers).
@MainActor
final class PlayerController: NSObject, ObservableObject, AVPlayerViewControllerDelegate {
    struct Run {
        let recap: Recap
        let level: Int
        var clips: [RecapClip]
        var i: Int
        let back: String?   // the channel to go back to afterwards
    }

    enum Mode {
        case idle
        case live(String)
        case recap(Run)
    }

    struct Card: Equatable {
        enum Kind { case setup, result }
        let kind: Kind
        let title: String
        let detail: String
    }

    @Published private(set) var mode: Mode = .idle
    @Published private(set) var tuning: String?
    @Published private(set) var failure: String?
    @Published private(set) var card: Card?
    @Published private(set) var adBreak = false
    @Published private(set) var seen: Set<String> = []   // recap plays already shown

    let player = AVPlayer()
    let model: AppModel
    private let vc = AVPlayerViewController()
    private var itemObservers: [NSKeyValueObservation] = []
    private var playerObserver: NSKeyValueObservation?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var poll: Task<Void, Never>?
    private var warm: Task<Void, Never>?
    private var subs: Set<AnyCancellable> = []
    private var samples: [(at: Date, muted: Bool)] = []
    private var liveBreaks: ChannelBreaks?
    private var lastLive: String?
    private var shownProgram: String?
    private var overlay: OverlayHost?
    private var menuSignature: [[String]] = []

    /// How far the picture is behind what the proxy is sending: the player stays 6 s from the
    /// newest piece, and pieces are 2 s, plus encoding.
    private let behind: TimeInterval = 9

    var liveNum: String? { if case .live(let n) = mode { return n }; return nil }
    var run: Run? { if case .recap(let r) = mode { return r }; return nil }

    init(model: AppModel) {
        self.model = model
        super.init()
        vc.player = player
        vc.delegate = self
        vc.appliesPreferredDisplayCriteriaAutomatically = true   // match the TV to 60 Hz if it can
        vc.loadViewIfNeeded()

        let overlay = OverlayHost(rootView: AnyView(PlayerOverlay(controller: self).environmentObject(model)))
        self.overlay = overlay
        overlay.gone = { [weak self] in
            // dismissed with Menu (the delegate call below may not come on every tvOS version)
            if self?.vc.presentingViewController == nil { self?.teardown() }
        }
        overlay.view.backgroundColor = .clear
        overlay.view.isUserInteractionEnabled = false
        overlay.view.translatesAutoresizingMaskIntoConstraints = false
        vc.addChild(overlay)
        if let host = vc.contentOverlayView {
            host.addSubview(overlay.view)
            NSLayoutConstraint.activate([
                overlay.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                overlay.view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                overlay.view.topAnchor.constraint(equalTo: host.topAnchor),
                overlay.view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            ])
        }
        overlay.didMove(toParent: vc)

        let presses: [(UIPress.PressType, Int)] = [(.pageUp, -1), (.pageDown, 1)]
        for (type, step) in presses {
            let g = UITapGestureRecognizer(target: self, action: step < 0 ? #selector(channelUp) : #selector(channelDown))
            g.allowedPressTypes = [NSNumber(value: type.rawValue)]
            vc.view.addGestureRecognizer(g)
        }

        playerObserver = player.observe(\.timeControlStatus) { [weak self] p, _ in
            let playing = p.timeControlStatus == .playing
            Task { @MainActor in if playing { self?.tuning = nil } }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t.seconds) }
        }
        // the guide moves on, recaps grow: keep the panel and buttons current
        model.$channels.combineLatest(model.$recaps)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.modelChanged() }
            .store(in: &subs)
    }

    func present() {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let p = top?.presentedViewController { top = p }
        top?.present(vc, animated: true)
    }

    // MARK: - live

    func playLive(_ num: String) {
        guard let api = model.api else { return }
        stopRecap()
        mode = .live(num)
        lastLive = num
        failure = nil
        card = nil
        samples = []
        liveBreaks = nil
        adBreak = false
        let ch = model.channel(num)
        tuning = "Tuning \(num) \(ch?.name ?? "")…"
        let item = AVPlayerItem(asset: AVURLAsset(url: api.liveURL(num), options: [AVURLAssetHTTPCookiesKey: api.cookies]))
        item.automaticallyPreservesTimeOffsetFromLive = true
        item.configuredTimeOffsetFromLive = CMTime(value: 6, timescale: 1)
        item.externalMetadata = Self.metadata(ch)
        shownProgram = ch?.now?.title
        observe(item) { [weak self] in
            self?.tuning = nil
            self?.failure = "\(num) didn't start. Every tuner may be busy; pick it again in Channels to retry."
        }
        player.replaceCurrentItem(with: item)
        player.play()
        startPolling(num)
        updateChrome()
    }

    @objc private func channelUp() { step(-1) }
    @objc private func channelDown() { step(1) }

    private func step(_ by: Int) {
        switch mode {
        case .live(let n): if let c = model.neighbour(of: n, by: by) { playLive(c.num) }
        case .recap: next(by)
        case .idle: break
        }
    }

    /// The proxy's mute state, polled while a channel plays, shown when the picture gets there.
    private func startPolling(_ num: String) {
        poll?.cancel()
        poll = Task { [weak self] in
            while !Task.isCancelled {
                await self?.model.refresh(recaps: false)
                guard let self, self.liveNum == num else { return }
                self.samples.append((.now, self.model.channel(num)?.isMuted ?? false))
                self.samples.removeAll { $0.at < Date.now.addingTimeInterval(-60) }
                if let api = self.model.api, let b = try? await api.breaks(), self.liveNum == num {
                    self.liveBreaks = b.channels?[num]
                }
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    // MARK: - recaps

    func startRecap(_ recap: Recap, level: Int) {
        let clips = recap.clips(level: level)
        guard !clips.isEmpty else { return }
        // afterwards: the game's channel if it's still on, else whatever was on before
        let back = (recap.live ? model.channel(for: recap)?.num : nil) ?? liveNum ?? lastLive
        poll?.cancel()
        adBreak = false
        tuning = nil
        failure = nil
        seen = []
        mode = .recap(Run(recap: recap, level: level, clips: clips, i: -1, back: back))
        if let back, let api = model.api {
            // keep the channel converting, so going back is instant
            warm?.cancel()
            warm = Task {
                while !Task.isCancelled {
                    await api.keepWarm(back)
                    try? await Task.sleep(for: .seconds(8))
                }
            }
        }
        next(1)
    }

    func next(_ by: Int) {
        guard var r = run else { return }
        // a live game's recap grows while it plays
        if let fresh = model.recaps.first(where: { $0.name == r.recap.name }) {
            let have = Set(r.clips.map(\.id))
            r.clips += fresh.clips(level: r.level).filter { !have.contains($0.id) }
        }
        if r.i >= 0 && r.i < r.clips.count { seen.insert(r.clips[r.i].id) }
        r.i = max(0, r.i + by)
        mode = .recap(r)
        if r.i >= r.clips.count { return endRecap() }
        play(clipAt: r.i)
    }

    func jump(to i: Int) {
        guard var r = run, r.clips.indices.contains(i) else { return }
        if r.i >= 0 && r.i < r.clips.count { seen.insert(r.clips[r.i].id) }
        r.i = i
        mode = .recap(r)
        play(clipAt: i)
    }

    private func play(clipAt i: Int) {
        guard let r = run, let api = model.api else { return }
        let c = r.clips[i]
        let item = AVPlayerItem(asset: AVURLAsset(url: api.clipURL(r.recap.name, c.file),
                                                  options: [AVURLAssetHTTPCookiesKey: api.cookies]))
        item.externalMetadata = Self.metadata(title: "Recap · \(r.recap.displayTitle)",
                                              subtitle: "Play \(i + 1) of \(r.clips.count) · \(c.when ?? "")",
                                              description: c.setup)
        observe(item) { [weak self] in self?.next(1) }   // a broken clip: skip it
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.next(1) }
        }
        card = nil
        player.replaceCurrentItem(with: item)
        player.play()
        updateChrome()
    }

    func endRecap() {
        let back = run?.back
        stopRecap()
        if let back { playLive(back) } else { close() }
    }

    private func stopRecap() {
        warm?.cancel()
        warm = nil
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = nil
        if run != nil { card = nil }
    }

    // MARK: - overlay

    private func tick(_ t: Double) {
        if let r = run, r.clips.indices.contains(r.i) {
            let c = r.clips[r.i]
            let d = player.currentItem?.duration.seconds
            let length = (d?.isFinite == true ? d! : c.seconds)
            if t < 5 {
                card = Card(kind: .setup, title: c.setup, detail: [c.when, c.before].compactMap { $0 }.joined(separator: "   "))
            } else if length > 0 && t >= length - 3 {
                card = Card(kind: .result, title: c.text ?? c.setup, detail: c.score ?? "")
            } else {
                card = nil
            }
        } else if liveNum != nil {
            if let b = liveBreaks, let now = player.currentItem?.currentDate() {
                // the studio stamps each piece with when the proxy sent it: exact
                adBreak = b.at(now.timeIntervalSince1970) != nil
            } else {
                // an older studio: the proxy's mute state, shifted by about how far behind we are
                let then = Date.now.addingTimeInterval(-behind)
                adBreak = samples.last(where: { $0.at <= then })?.muted ?? false
            }
        }
    }

    // MARK: - chrome (info panel tab, transport bar buttons)

    private func modelChanged() {
        if let n = liveNum, let ch = model.channel(n), ch.now?.title != shownProgram {
            shownProgram = ch.now?.title
            player.currentItem?.externalMetadata = Self.metadata(ch)
        }
        updateChrome()
    }

    private func updateChrome() {
        let title = run != nil ? "Plays" : "Channels"
        if vc.customInfoViewControllers.first?.title != title {
            let tab: UIViewController = run != nil
                ? UIHostingController(rootView: PlaysTab(controller: self).environmentObject(model))
                : UIHostingController(rootView: ChannelsTab(controller: self).environmentObject(model))
            tab.title = title
            tab.preferredContentSize = CGSize(width: 0, height: 360)
            vc.customInfoViewControllers = [tab]
        }

        var items: [UIMenuElement] = []
        if let r = run {
            items.append(UIAction(title: "Previous play", image: UIImage(systemName: "backward.end.fill")) { [weak self] _ in self?.next(-1) })
            items.append(UIAction(title: "Next play", image: UIImage(systemName: "forward.end.fill")) { [weak self] _ in self?.next(1) })
            items.append(UIAction(title: r.back != nil ? "Back to live" : "Close recap",
                                  image: UIImage(systemName: r.back != nil ? "dot.radiowaves.left.and.right" : "xmark")) { [weak self] _ in self?.endRecap() })
        } else if let n = liveNum, let rec = model.recap(for: model.channel(n)) {
            let key = rec.clips(level: 1), all = rec.clips(level: 2)
            var catchUp: [UIMenuElement] = []
            if !key.isEmpty {
                catchUp.append(UIAction(title: "Scores & turnovers · \(runtime(key))") { [weak self] _ in self?.startRecap(rec, level: 1) })
            }
            catchUp.append(UIAction(title: "All highlights · \(runtime(all))") { [weak self] _ in self?.startRecap(rec, level: 2) })
            items.append(UIMenu(title: "Catch up", image: UIImage(systemName: "backward.circle"), children: catchUp))
        }
        if let n = liveNum {
            // this channel becomes the multi-view's main one, and keeps its tuner (no retuning wait)
            items.append(UIAction(title: "Multi-view", image: UIImage(systemName: "rectangle.split.2x2")) { [weak self] _ in
                guard let self else { return }
                let model = self.model
                self.close { model.startMulti(main: n) }
            })
        }
        // only when they change: replacing them would close a menu the viewer has open
        let mine: [[String]] = [[liveNum ?? run?.recap.name ?? ""]]
        let signature = mine + items.map { e in [e.title] + ((e as? UIMenu)?.children.map(\.title) ?? []) }
        if signature != menuSignature {
            menuSignature = signature
            vc.transportBarCustomMenuItems = items
        }
    }

    // MARK: - item status

    private func observe(_ item: AVPlayerItem, failed: @escaping @MainActor () -> Void) {
        itemObservers = [item.observe(\.status) { [weak self] it, _ in
            guard it.status == .failed else { return }
            Task { @MainActor in
                guard self?.player.currentItem === it else { return }
                failed()
            }
        }]
    }

    // MARK: - metadata (the info panel's title and description)

    private static func metadata(_ ch: Channel?) -> [AVMetadataItem] {
        guard let ch else { return [] }
        let p = ch.now
        var desc = p?.desc ?? ""
        if let n = ch.next {
            desc += (desc.isEmpty ? "" : "\n\n") + "Next at \(n.startDate.formatted(date: .omitted, time: .shortened)): \(n.title)"
        }
        return metadata(title: p?.title ?? "\(ch.num) \(ch.name)",
                        subtitle: [p?.subtitle, "\(ch.num) \(ch.name)"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                        description: desc)
    }

    private static func metadata(title: String, subtitle: String, description: String) -> [AVMetadataItem] {
        func item(_ id: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let m = AVMutableMetadataItem()
            m.identifier = id
            m.value = value as NSString
            m.extendedLanguageTag = "und"
            return m.copy() as! AVMetadataItem
        }
        var out = [item(.commonIdentifierTitle, title)]
        if !subtitle.isEmpty { out.append(item(.iTunesMetadataTrackSubTitle, subtitle)) }
        if !description.isEmpty { out.append(item(.commonIdentifierDescription, description)) }
        return out
    }

    // MARK: - leaving

    func close(then: (() -> Void)? = nil) {
        vc.dismiss(animated: true) { [weak self] in
            self?.teardown()
            then?()
        }
    }

    nonisolated func playerViewControllerDidEndDismissalTransition(_ playerViewController: AVPlayerViewController) {
        MainActor.assumeIsolated { teardown() }
    }

    /// Lets the tuner go: the studio stops converting 20 s after the last request.
    private func teardown() {
        guard Watch.current === self else { return }
        poll?.cancel()
        warm?.cancel()
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        if let t = timeObserver { player.removeTimeObserver(t) }
        timeObserver = nil
        subs.removeAll()
        player.pause()
        player.replaceCurrentItem(with: nil)
        mode = .idle
        // the overlay and tabs hold this controller: let it go
        vc.customInfoViewControllers = []
        vc.transportBarCustomMenuItems = []
        overlay?.view.removeFromSuperview()
        overlay?.removeFromParent()
        overlay = nil
        Watch.current = nil
        Task { await model.refresh() }
    }
}

/// The overlay's host, which also says when the player has gone away.
final class OverlayHost: UIHostingController<AnyView> {
    var gone: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        gone?()
    }
}

/// Opens the player (one at a time) from anywhere in the app.
@MainActor
enum Watch {
    static var current: PlayerController?

    static func live(_ num: String, model: AppModel) {
        controller(model).playLive(num)
    }

    static func recap(_ recap: Recap, level: Int, model: AppModel) {
        controller(model).startRecap(recap, level: level)
    }

    private static func controller(_ model: AppModel) -> PlayerController {
        if let c = current { return c }
        let c = PlayerController(model: model)
        current = c
        c.present()
        return c
    }
}
