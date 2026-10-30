import Foundation

enum SlashCommand {
    /// Match DSH's command grammar; paths such as /tmp/file stay ordinary text.
    static func name(in text: String) -> String? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = line.range(of: #"^/[a-z][a-z0-9_-]*(?=$|[\t\n\r ])"#, options: .regularExpression) else { return nil }
        return String(line[range].dropFirst())
    }
}
