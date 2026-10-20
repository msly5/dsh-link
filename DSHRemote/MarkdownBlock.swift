import Foundation

struct MarkdownBlock: Identifiable, Equatable {
    enum Content: Equatable {
        case paragraph(String)
        case heading(level: Int, text: String)
        case code(language: String, text: String)
        case listItem(marker: String, text: String, indent: Int)
        case quote(String)
        case table(headers: [String], rows: [[String]])
        case divider
    }

    let id: Int
    let content: Content

    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0
        while index < lines.count {
            let start = index
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { index += 1; continue }
            if let fence = fenceStart(trimmed) {
                index += 1
                var code: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.count >= fence.count,
                       candidate.allSatisfy({ $0 == fence.character }) { index += 1; break }
                    code.append(lines[index])
                    index += 1
                }
                blocks.append(.init(id: start, content: .code(language: fence.language, text: code.joined(separator: "\n"))))
                continue
            }
            if index + 1 < lines.count, let headers = tableCells(line), isTableSeparator(lines[index + 1], columns: headers.count) {
                index += 2
                var rows: [[String]] = []
                while index < lines.count, let cells = tableCells(lines[index]) {
                    rows.append(Array((cells + Array(repeating: "", count: headers.count)).prefix(headers.count)))
                    index += 1
                }
                blocks.append(.init(id: start, content: .table(headers: headers, rows: rows)))
                continue
            }
            if let heading = heading(trimmed) {
                blocks.append(.init(id: start, content: .heading(level: heading.level, text: heading.text)))
                index += 1
                continue
            }
            if isDivider(trimmed) {
                blocks.append(.init(id: start, content: .divider)); index += 1; continue
            }
            if trimmed.hasPrefix(">") {
                var quote: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(String(lines[index].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.init(id: start, content: .quote(quote.joined(separator: "\n"))))
                continue
            }
            if let item = listItem(line) {
                blocks.append(.init(id: start, content: .listItem(marker: item.marker, text: item.text, indent: item.indent)))
                index += 1
                continue
            }
            var paragraph = [line]
            index += 1
            while index < lines.count {
                let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                if candidate.isEmpty || fenceStart(candidate) != nil || heading(candidate) != nil
                    || isDivider(candidate) || candidate.hasPrefix(">") || listItem(lines[index]) != nil { break }
                if index + 1 < lines.count, let cells = tableCells(lines[index]), isTableSeparator(lines[index + 1], columns: cells.count) { break }
                paragraph.append(lines[index]); index += 1
            }
            blocks.append(.init(id: start, content: .paragraph(paragraph.joined(separator: "\n"))))
        }
        return blocks
    }

    private static func fenceStart(_ line: String) -> (character: Character, count: Int, language: String)? {
        guard let first = line.first, first == "`" || first == "~" else { return nil }
        let prefix = line.prefix { $0 == first }
        guard prefix.count >= 3 else { return nil }
        return (first, prefix.count, String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces))
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)).trimmingCharacters(in: .whitespaces))
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first, ["-", "*", "_"].contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func listItem(_ line: String) -> (marker: String, text: String, indent: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let indent = min(line.prefix { $0 == " " || $0 == "\t" }.count / 2, 6)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return ("•", String(trimmed.dropFirst(2)), indent)
        }
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty, let punctuation = trimmed.dropFirst(digits.count).first,
              punctuation == "." || punctuation == ")", trimmed.dropFirst(digits.count + 1).first == " " else { return nil }
        return (String(digits) + String(punctuation), String(trimmed.dropFirst(digits.count + 2)), indent)
    }

    private static func isTableSeparator(_ line: String, columns: Int) -> Bool {
        guard let cells = tableCells(line), cells.count == columns else { return false }
        return cells.allSatisfy { cell in
            let body = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return body.count >= 3 && body.allSatisfy { $0 == "-" }
        }
    }

    private static func tableCells(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }
        var cells: [String] = []
        var cell = ""
        var escaped = false
        var ticks = 0
        for character in trimmed {
            if escaped {
                if character != "|" { cell.append("\\") }
                cell.append(character)
                escaped = false
            } else if character == "\\" { escaped = true }
            else if character == "`" { ticks += 1; cell.append(character) }
            else if character == "|", ticks.isMultiple(of: 2) { cells.append(cell); cell = "" }
            else { cell.append(character) }
        }
        if escaped { cell.append("\\") }
        cells.append(cell)
        if cells.first?.isEmpty == true { cells.removeFirst() }
        if cells.last?.isEmpty == true { cells.removeLast() }
        guard !cells.isEmpty else { return nil }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
