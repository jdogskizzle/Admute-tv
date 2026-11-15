import SwiftUI

/// First run (or signed out): the studio's address and its sign-in. The password isn't kept;
/// the session lasts 30 days. Typing works with the on-screen keyboard or an iPhone nearby.
struct ConnectView: View {
    @EnvironmentObject var model: AppModel
    let initialError: String?

    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 14) {
                Image(systemName: "speaker.slash.circle.fill").font(.system(size: 110)).foregroundStyle(Theme.accent)
                Text("admute").font(.system(size: 76, weight: .bold, design: .rounded))
                Text("Live TV with the ads muted. Sign in with your admute studio.")
                    .font(.title3).foregroundStyle(.secondary)
            }
            VStack(spacing: 24) {
                TextField("Studio address, e.g. home.example.com/admute", text: $server)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                TextField("Username", text: $username)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(width: 1000)

            if let e = error ?? initialError {
                Text(e).font(.callout).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 1000)
            }
            Button {
                Task { await connect() }
            } label: {
                HStack(spacing: 16) {
                    if busy { ProgressView() }
                    Text(busy ? "Signing in…" : "Sign in")
                }
                .frame(width: 400)
            }
            .disabled(busy || server.isEmpty)
        }
        .onAppear {
            if server.isEmpty { server = model.server }
            if username.isEmpty { username = model.username }
        }
    }

    private func connect() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await model.connect(server: server, username: username, password: password)
            password = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}
