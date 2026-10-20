import SwiftUI

enum Theme {
    static let bg = Color(red: 0.035, green: 0.047, blue: 0.075)
    static let card = Color(red: 0.072, green: 0.091, blue: 0.130)
    static let raised = Color(red: 0.103, green: 0.127, blue: 0.177)
    static let code = Color(red: 0.046, green: 0.062, blue: 0.097)
    static let accent = Color(red: 0.40, green: 0.92, blue: 0.78)
    static let violet = Color(red: 0.64, green: 0.61, blue: 0.97)
    static let text = Color(red: 0.92, green: 0.95, blue: 0.99)
    static let muted = Color(red: 0.55, green: 0.62, blue: 0.73)
    static let onAccent = Color(red: 0.035, green: 0.15, blue: 0.13)
    static let warning = Color(red: 1, green: 0.70, blue: 0.39)
    static let stroke = Color.white.opacity(0.075)
    static let faint = Color.white.opacity(0.045)
    static let mono = Font.caption.monospaced()
    static let monoSmall = Font.caption.monospaced()

    enum Radius {
        static let card: CGFloat = 22
        static let bubble: CGFloat = 20
        static let control: CGFloat = 14
    }

    enum Space {
        static let screen: CGFloat = 22
        static let row: CGFloat = 16
    }
}

extension View {
    func card(radius: CGFloat = Theme.Radius.card, inset: CGFloat? = nil) -> some View {
        padding(inset ?? 0)
            .background(Theme.card, in: .rect(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.stroke) }
    }
}

struct StatusDot: View {
    let active: Bool

    var body: some View {
        Circle()
            .fill(active ? Theme.accent : Theme.muted)
            .frame(width: 6, height: 6)
            .padding(4)
            .background((active ? Theme.accent : Theme.muted).opacity(0.10), in: .circle)
            .accessibilityHidden(true)
    }
}

func compactRelative(_ date: Date) -> String {
    let seconds = -date.timeIntervalSinceNow
    if seconds < 60 { return "刚刚" }
    if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
    if seconds < 86400 { return "\(Int(seconds / 3600)) 小时前" }
    let days = Int(seconds / 86400)
    if days == 1 { return "昨天" }
    if days < 7 { return "\(days) 天前" }
    return date.formatted(date: .abbreviated, time: .omitted)
}

struct PathLabel: View {
    let path: String

    var body: some View {
        Label(path, systemImage: "folder")
            .font(.caption.monospaced())
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(Theme.muted)
    }
}
