import Foundation

enum SlashCommand {
    // A trailing space means the user has moved on to arguments. Do not trim it.
    static func suggestionQuery(in text: String) -> String? {
        let line = String(text.drop(while: { $0.isWhitespace }))
        guard line.range(of: #"^/[a-zA-Z0-9_-]*$"#, options: .regularExpression) != nil else { return nil }
        return String(line.dropFirst()).lowercased()
    }

    /// Match DSH's command grammar; paths such as /tmp/file stay ordinary text.
    static func name(in text: String) -> String? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = line.range(of: #"^/[a-z][a-z0-9_-]*(?=$|[\t\n\r ])"#, options: .regularExpression) else { return nil }
        return String(line[range].dropFirst())
    }
}
