import SwiftUI

enum Theme {
    static let accent = Color(red: 0.88, green: 0.47, blue: 0.36)   // the studio's accent
    static let panel = Color.white.opacity(0.08)
    static let panelFocused = Color.white.opacity(0.92)
    static let muted = Color(red: 0.95, green: 0.62, blue: 0.25)
}

/// A channel's logo, or its number when it has none (or it doesn't load).
struct ChannelLogo: View {
    let channel: Channel
    var size: CGFloat = 80

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.16).fill(Color.white.opacity(0.1))
            if let url = channel.logoURL {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFit().padding(size * 0.12)
                    } else {
                        number
                    }
                }
            } else {
                number
            }
        }
        .frame(width: size * 1.5, height: size)
    }

    private var number: some View {
        Text(channel.num).font(.system(size: size * 0.32, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
    }
}

struct ProgressLine: View {
    let value: Double
    var height: CGFloat = 6
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(tint).frame(width: max(height, g.size.width * value))
            }
        }
        .frame(height: height)
    }
}

struct Badge: View {
    let text: String
    var icon: String? = nil
    var color: Color = Theme.accent

    var body: some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.9)))
        .foregroundStyle(.black)
    }
}

/// "7:00 – 10:30 PM"
func timeRange(_ p: Program) -> String {
    let f = Date.FormatStyle(date: .omitted, time: .shortened)
    return "\(p.startDate.formatted(f)) – \(p.stopDate.formatted(f))"
}

func minutesLeft(_ p: Program, now: Date) -> String {
    let m = Int(((p.stop - now.timeIntervalSince1970) / 60).rounded(.up))
    if m <= 0 { return "Ending" }
    return m >= 60 ? "\(m / 60) h \(m % 60) min left" : "\(m) min left"
}

/// A focusable row or tile: lifts and lights up under focus, like the system's own.
struct LiftStyle: ButtonStyle {
    var corner: CGFloat = 20

    func makeBody(configuration: Configuration) -> some View {
        Body(configuration: configuration, corner: corner)
    }

    struct Body: View {
        let configuration: Configuration
        let corner: CGFloat
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .foregroundStyle(focused ? Color.black : Color.white)
                .background(RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(focused ? Theme.panelFocused : Theme.panel))
                .scaleEffect(configuration.isPressed ? 0.98 : (focused ? 1.04 : 1))
                .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 24, y: 12)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}
