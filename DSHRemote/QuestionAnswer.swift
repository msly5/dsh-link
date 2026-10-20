import Foundation

struct QuestionAnswer: Identifiable, Equatable {
    let id: String
    var selected: [String] = []
    var custom = ""

    func isComplete(for question: UserQuestion) -> Bool {
        let valid = selected.allSatisfy { question.options.contains($0) }
        let hasCustom = !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return valid && Set(selected).count == selected.count
            && (question.multiSelect || (selected.count <= 1 && !(hasCustom && !selected.isEmpty)))
            && (!selected.isEmpty || hasCustom)
    }

    var payload: [String: Any] {
        var value: [String: Any] = ["id": id, "selected": selected]
        let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { value["custom"] = trimmed }
        return value
    }
}
