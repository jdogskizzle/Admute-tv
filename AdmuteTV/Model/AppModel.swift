import Foundation
import SwiftUI

/// The app's state: where the studio is, whether we're signed in, and the channels and
/// recaps it lists (refreshed every 15 seconds while the app is open).
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case starting
        case connect(error: String?)   // no studio yet, or signed out
        case ready
    }

    @Published private(set) var phase: Phase = .starting
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var recaps: [Recap] = []
    @Published private(set) var delay: Double = 30
    @Published private(set) var tuners: Int?      // nil: the proxy doesn't know (TUNER_COUNT unset)
    @Published private(set) var problem: String?   // the studio is up but the proxy isn't, etc.
    @Published private(set) var now: Date = .now   // ticks, for progress bars
    @Published var multi: MultiController?          // the multi-view, while it's open

    private(set) var api: API?
    private var loop: Task<Void, Never>?

    var server: String { Store.server ?? "" }
    var username: String { Store.username ?? "" }

    func start() async {
        guard let s = Store.server, let base = API.normalize(s) else {
            phase = .connect(error: nil)
            return
        }
        let api = API(base: base, session: Store.session(for: base.absoluteString))
        do {
            try await load(api)
            self.api = api
            phase = .ready
            run()
        } catch APIError.notSignedIn {
            phase = .connect(error: nil)
        } catch {
            phase = .connect(error: error.localizedDescription)
        }
    }

    /// Signs in (or just checks the address, when the studio has sign-in turned off).
    func connect(server: String, username: String, password: String) async throws {
        guard let base = API.normalize(server) else { throw APIError.notAdmute }
        let api = API(base: base, session: nil)
        do {
            try await load(api)   // sign-in off
        } catch APIError.notSignedIn {
            api.session = try await api.signIn(username: username, password: password)
            try await load(api)
        }
        Store.server = base.absoluteString
        Store.username = username
        Store.setSession(api.session, for: base.absoluteString)
        self.api = api
        phase = .ready
        run()
    }

    func signOut() {
        loop?.cancel()
        if let api { Store.setSession(nil, for: api.base.absoluteString) }
        api = nil
        channels = []
        recaps = []
        phase = .connect(error: nil)
    }

    func refresh(recaps withRecaps: Bool = true) async {
        guard let api else { return }
        do {
            try await load(api, recaps: withRecaps)
        } catch APIError.notSignedIn {
            signOut()
            phase = .connect(error: "The studio signed this Apple TV out. Sign in again.")
        } catch {
            problem = "Can't reach the studio: \(error.localizedDescription)"
        }
    }

    private func load(_ api: API, recaps withRecaps: Bool = true) async throws {
        let list = try await api.channels()
        channels = list.channels ?? []
        delay = list.delaySeconds ?? delay
        tuners = list.tuners ?? tuners
        if list.configured == false {
            problem = "The studio has no LIVE_URL set, so it can't show live TV."
        } else if let e = list.error {
            problem = "The studio can't reach the admute proxy: \(e)"
        } else {
            problem = nil
        }
        if withRecaps { recaps = (try? await api.recaps()) ?? recaps }
        now = .now
    }

    private func run() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await self?.refresh()
            }
        }
    }

    // MARK: - lookups

    func channel(_ num: String) -> Channel? { channels.first { $0.num == num } }

    /// The recap of the game a channel is showing now.
    func recap(for channel: Channel?) -> Recap? {
        guard let p = channel?.now else { return nil }
        return recaps.first { $0.matches(p) }
    }

    /// The channel showing a recap's game now, if it's still on.
    func channel(for recap: Recap) -> Channel? {
        channels.first { recap.matches($0.now) }
    }

    // MARK: - multi-view

    /// One spot per tuner (2 when the proxy can't tell).
    var multiCount: Int { min(6, max(2, tuners ?? 2)) }

    /// Opens the multi-view; `main` (the channel being watched, say) becomes its main channel.
    func startMulti(main: String?) {
        var s = MultiController.saved
        while s.count < multiCount { s.append(nil) }
        if let main {
            if let j = s.firstIndex(of: main) { s.swapAt(0, j) } else { s[0] = main }
        }
        MultiController.saved = s
        multi = MultiController(model: self, count: multiCount)
    }

    func neighbour(of num: String, by step: Int) -> Channel? {
        guard !channels.isEmpty else { return nil }
        let i = channels.firstIndex { $0.num == num } ?? 0
        return channels[(i + step % channels.count + channels.count) % channels.count]
    }
}
