import Foundation

struct ExecutionActivity: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case reasoning, tool }
    enum Phase: String, Codable, Sendable { case running, completed, failed }

    let kind: Kind
    var name: String?
    var arguments: String?
    var phase: Phase

    var title: String {
        if kind == .reasoning { return "思考" }
        switch name {
        case "bash", "pwsh": return "运行命令"
        case "read": return "读取文件"
        case "write": return "写入文件"
        case "edit": return "编辑文件"
        case "glob": return "查找文件"
        case "grep": return "搜索文件内容"
        case "read_image": return "读取图片"
        case "web_search": return "网页搜索"
        case "web_fetch": return "读取网页"
        case "job_output": return "读取任务输出"
        case "job_kill": return "取消后台任务"
        case "present": return "展示文件"
        default: return name ?? "执行结果"
        }
    }

    var symbol: String {
        if kind == .reasoning { return "atom" }
        switch name {
        case "bash", "pwsh": return "terminal"
        case "job_output", "job_kill": return "list.bullet.rectangle"
        case "read", "write", "edit": return "doc.text"
        case "grep", "glob", "web_search", "web_fetch": return "magnifyingglass"
        default: return "chevron.left.forwardslash.chevron.right"
        }
    }

    var argumentValues: [String: Any] {
        guard let arguments, let data = arguments.data(using: .utf8) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    var summary: String {
        let values = argumentValues
        for key in ["description", "file_path", "path", "job_id", "query", "url", "command"] {
            if let text = values[key] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return Self.singleLine(text)
            }
        }
        return name ?? "查看输出"
    }

    var input: String {
        let values = argumentValues
        if let command = values["command"] as? String { return command }
        guard !values.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]) else { return arguments ?? "" }
        return String(decoding: data, as: UTF8.self)
    }

    func summary(output: String) -> String {
        if name?.hasPrefix("/") == true, phase != .running, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Self.singleLine(output)
        }
        if name == "job_kill", phase == .completed, output.contains("requested cancellation of job ") {
            return summary + " · 已请求取消"
        }
        return summary
    }

    func settledPhase(output: String) -> Phase {
        guard phase == .completed, name == "bash" || name == "pwsh",
              let line = output.split(whereSeparator: \.isNewline).last?.trimmingCharacters(in: .whitespaces) else { return phase }
        // DSH appends these terminal status markers after stdout/stderr.
        if line.hasPrefix("[exit code: "), line.hasSuffix("]"),
           let code = Int(line.dropFirst(12).dropLast()), code != 0 { return .failed }
        if line.hasPrefix("[killed by signal: ") || line.hasPrefix("[timed out after ") { return .failed }
        return phase
    }

    static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
