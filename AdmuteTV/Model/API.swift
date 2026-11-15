import Foundation

// The admute studio's API, as the web Watch tab uses it:
//   GET  api/channels                    the channels with what's on now and next
//   GET  api/watch/<num>/live.m3u8       a channel live as HLS (muted, DELAY behind)
//   GET  api/recaps                      game recaps and their clips
//   GET  api/recap/<name>/<file>.mp4     one recap clip
//   POST login                           formlogin's sign-in form; answers with a session cookie

// MARK: - What the studio sends

struct Program: Decodable, Hashable {
    let title: String
    let subtitle: String?
    let desc: String?
    let start: Double
    let stop: Double

    var startDate: Date { Date(timeIntervalSince1970: start) }
    var stopDate: Date { Date(timeIntervalSince1970: stop) }

    func progress(at now: Date = .now) -> Double {
        guard stop > start else { return 0 }
        return min(1, max(0, (now.timeIntervalSince1970 - start) / (stop - start)))
    }

    /// ("tampa bay buccaneers", "chicago bears") from a guide subtitle like "Tampa Bay Buccaneers at Chicago Bears".
    var teams: [String]? {
        guard let s = subtitle?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        for sep in [" at ", " vs. ", " vs "] {
            if let r = s.range(of: sep) {
                let a = s[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
                let b = s[r.upperBound...].trimmingCharacters(in: .whitespaces)
                if !a.isEmpty && !b.isEmpty { return [a.lowercased(), b.lowercased()] }
            }
        }
        return nil
    }
}

struct Channel: Decodable, Identifiable, Hashable {
    let num: String
    let name: String
    let logo: String?
    let now: Program?
    let next: Program?
    let open: Bool?
    let mutedNow: Bool?

    var id: String { num }
    var logoURL: URL? { logo.flatMap { $0.isEmpty ? nil : URL(string: $0) } }
    var isMuted: Bool { mutedNow ?? false }

    enum CodingKeys: String, CodingKey {
        case num, name, logo, now, next, open
        case mutedNow = "muted_now"
    }
}

struct ChannelList: Decodable {
    let configured: Bool?
    let channels: [Channel]?
    let delaySeconds: Double?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case configured, channels, error
        case delaySeconds = "delay_seconds"
    }
}

struct RecapClip: Decodable, Identifiable, Hashable {
    let id: String
    let kind: String?
    let level: Int
    let when: String?
    let score: String?      // the score after the play
    let text: String?       // what happened
    let situation: String?  // the set-up: "CHI ball · 3rd & 8 at CHI 44"
    let before: String?     // the score before the play
    let seconds: Double
    let file: String

    /// What can be shown before the play has been watched.
    var setup: String { situation ?? kind ?? "Play" }

    enum CodingKeys: String, CodingKey {
        case id, kind, level, when, score, text, situation, before, seconds, file
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 2
        when = try c.decodeIfPresent(String.self, forKey: .when)
        score = try c.decodeIfPresent(String.self, forKey: .score)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        situation = try c.decodeIfPresent(String.self, forKey: .situation)
        before = try c.decodeIfPresent(String.self, forKey: .before)
        seconds = try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
        file = try c.decode(String.self, forKey: .file)
    }
}

struct Recap: Decodable, Identifiable, Hashable {
    let name: String
    let title: String
    let teams: [String]?
    let live: Bool
    let updated: Double
    let clips: [RecapClip]

    var id: String { name }
    var displayTitle: String { teams.map { "\($0[0]) at \($0[1])" } ?? title }

    /// Level 1: scores, turnovers and missed kicks. Level 2: every key play.
    func clips(level: Int) -> [RecapClip] { clips.filter { $0.level <= level } }

    func matches(_ program: Program?) -> Bool {
        guard let t = program?.teams, let mine = teams, mine.count == 2 else { return false }
        return mine[0].lowercased() == t[0] && mine[1].lowercased() == t[1]
    }
}

func runtime(_ clips: [RecapClip]) -> String {
    let s = Int(clips.reduce(0) { $0 + $1.seconds }.rounded())
    return String(format: "%d:%02d", s / 60, s % 60)
}

// MARK: - Errors

enum APIError: LocalizedError {
    case notSignedIn
    case wrongPassword
    case tooManyAttempts
    case notAdmute
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in."
        case .wrongPassword: return "Wrong username or password. (If the studio has no password yet, set one there first.)"
        case .tooManyAttempts: return "Too many failed attempts. Try again in a few minutes."
        case .notAdmute: return "That address didn't answer like the admute studio. Use the address you open the studio at in a browser."
        case .http(let code): return "The studio answered with an error (\(code))."
        }
    }
}

// MARK: - Client

struct Session: Codable, Equatable {
    var name: String
    var value: String
}

final class API {
    let base: URL          // the studio's address, ending in "/"
    var session: Session?

    init(base: URL, session: Session?) {
        self.base = base
        self.session = session
    }

    /// "tv.example.com/admute" -> https://tv.example.com/admute/
    static func normalize(_ text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        if !s.hasSuffix("/") { s += "/" }
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url
    }

    func url(_ path: String) -> URL {
        URL(string: path, relativeTo: base)!.absoluteURL
    }

    private static func seg(_ s: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    func liveURL(_ num: String) -> URL { url("api/watch/\(Self.seg(num))/live.m3u8") }
    func clipURL(_ recap: String, _ file: String) -> URL { url("api/recap/\(Self.seg(recap))/\(Self.seg(file))") }

    /// The session cookie for AVPlayer (AVURLAssetHTTPCookiesKey): it sends these with the
    /// playlist and every piece.
    var cookies: [HTTPCookie] {
        guard let s = session, let host = base.host else { return [] }
        let path = base.path.isEmpty ? "/" : base.path
        var props: [HTTPCookiePropertyKey: Any] = [.name: s.name, .value: s.value, .domain: host, .path: path]
        if base.scheme == "https" { props[.secure] = "TRUE" }
        return HTTPCookie(properties: props).map { [$0] } ?? []
    }

    private func request(_ path: String) -> URLRequest {
        var r = URLRequest(url: url(path))
        r.httpShouldHandleCookies = false
        if let s = session { r.setValue("\(s.name)=\(s.value)", forHTTPHeaderField: "Cookie") }
        return r
    }

    func get<T: Decodable>(_ path: String, as: T.Type = T.self, timeout: TimeInterval = 15) async throws -> T {
        var r = request(path)
        r.timeoutInterval = timeout
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw APIError.notSignedIn }
        guard code == 200 else { throw code == 404 ? APIError.notAdmute : APIError.http(code) }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.notAdmute }
    }

    func channels() async throws -> ChannelList { try await get("api/channels") }
    func recaps() async throws -> [Recap] { try await get("api/recaps") }

    /// Asks for a channel's playlist without playing it, so the studio keeps converting it
    /// (it stops 20 s after the last request). Used while a recap plays, so going back to
    /// live is instant.
    func keepWarm(_ num: String) async {
        var r = request("api/watch/\(Self.seg(num))/live.m3u8")
        r.timeoutInterval = 40
        _ = try? await URLSession.shared.data(for: r)
    }

    /// formlogin's sign-in form. Returns the session cookie from its redirect.
    func signIn(username: String, password: String) async throws -> Session {
        var r = URLRequest(url: url("login"))
        r.httpMethod = "POST"
        r.httpShouldHandleCookies = false
        r.timeoutInterval = 20
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = "username=\(Self.form(username))&password=\(Self.form(password))".data(using: .utf8)
        let (_, resp) = try await URLSession.shared.data(for: r, delegate: NoRedirect())
        guard let http = resp as? HTTPURLResponse else { throw APIError.notAdmute }
        switch http.statusCode {
        case 401: throw APIError.wrongPassword
        case 429: throw APIError.tooManyAttempts
        case 300..<400: break
        case 404: throw APIError.notAdmute
        default: throw APIError.http(http.statusCode)
        }
        let header = http.value(forHTTPHeaderField: "Set-Cookie") ?? ""
        guard let s = Self.sessionCookie(header) else { throw APIError.notAdmute }
        return s
    }

    /// The "<app>_session=<value>" pair out of a Set-Cookie header.
    static func sessionCookie(_ header: String) -> Session? {
        for part in header.split(separator: ";") + header.split(separator: ",") {
            let kv = part.trimmingCharacters(in: .whitespaces)
            guard let eq = kv.firstIndex(of: "=") else { continue }
            let name = String(kv[..<eq]), value = String(kv[kv.index(after: eq)...])
            if name.hasSuffix("_session") && !value.isEmpty { return Session(name: name, value: value) }
        }
        return nil
    }

    private static func form(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return (s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s)
    }
}

/// Stops at formlogin's 303 so the session cookie can be read from it.
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
