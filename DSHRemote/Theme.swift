import SwiftUI

/// Semantic asset colors resolve automatically for the current system appearance.
enum Theme {
    static let bg = Color("ThemeBackground")
    static let sidebar = Color("ThemeSidebar")
    static let card = Color("ThemeCard")
    static let raised = Color("ThemeRaised")
    static let code = Color("ThemeCode")
    static let accent = Color("ThemeAccent")
    static let text = Color("ThemeText")
    static let muted = Color("ThemeMuted")
    static let onAccent = Color("ThemeOnAccent")
    static let warning = Color("ThemeWarning")
    static let stroke = Color("ThemeStroke")
    static let faint = Color("ThemeFaint")
    static let mono = Font.caption.monospaced()
    static let monoSmall = Font.caption.monospaced()

    enum Radius {
        static let card: CGFloat = 16
        static let bubble: CGFloat = 19
        static let control: CGFloat = 12
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
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.stroke, lineWidth: 0.75) }
    }
}

struct StatusDot: View {
    let active: Bool
    var body: some View {
        Circle().fill(active ? Theme.accent : Theme.muted)
            .frame(width: 5, height: 5).accessibilityHidden(true)
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
            .font(.caption).lineLimit(1).truncationMode(.middle).foregroundStyle(Theme.muted)
    }
}
