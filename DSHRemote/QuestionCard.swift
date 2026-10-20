import SwiftUI

struct QuestionCard: View {
    let prompt: QuestionPrompt
    let submitting: Bool
    let onSubmit: ([QuestionAnswer]) -> Void
    @State private var answers: [QuestionAnswer]

    init(prompt: QuestionPrompt, submitting: Bool, onSubmit: @escaping ([QuestionAnswer]) -> Void) {
        self.prompt = prompt
        self.submitting = submitting
        self.onSubmit = onSubmit
        _answers = State(initialValue: prompt.questions.map { QuestionAnswer(id: $0.id) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 9) {
                Image(systemName: "bubble.left.and.text.bubble.right").foregroundStyle(Theme.accent)
                Text("需要你的选择").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Spacer()
                Text("\(prompt.questions.count) 个问题").font(.caption).foregroundStyle(Theme.muted)
            }
            Divider().overlay(Theme.stroke)
            ForEach(Array(prompt.questions.enumerated()), id: \.element.id) { index, question in
                VStack(alignment: .leading, spacing: 10) {
                    Label(question.header ?? "问题 \(index + 1)", systemImage: "questionmark.bubble")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(question.question).font(.body.weight(.medium)).foregroundStyle(Theme.text)
                    if let detail = question.detail, !detail.isEmpty {
                        RichText(text: detail).font(.callout)
                    }
                    ForEach(question.options, id: \.self) { option in
                        Button { toggle(option, for: question) } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: selected(option, for: question)
                                      ? (question.multiSelect ? "checkmark.square.fill" : "largecircle.fill.circle")
                                      : (question.multiSelect ? "square" : "circle"))
                                Text(option).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.callout)
                            .padding(10)
                            .foregroundStyle(selected(option, for: question) ? Theme.accent : Theme.text)
                            .frame(minHeight: 44)
                            .background(selected(option, for: question) ? Theme.accent.opacity(0.08) : Theme.raised, in: .rect(cornerRadius: 13))
                            .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(selected(option, for: question) ? Theme.accent.opacity(0.35) : Theme.stroke) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected(option, for: question) ? .isSelected : [])
                    }
                    TextField("其他答案", text: customBinding(for: question), prompt: Text("补充或输入其他答案").foregroundStyle(Theme.muted), axis: .vertical)
                        .font(.callout)
                        .lineLimit(1...4)
                        .foregroundStyle(Theme.text)
                        .padding(13)
                        .background(Theme.code, in: .rect(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke) }
                }
            }
            Button {
                onSubmit(answers)
            } label: {
                HStack {
                    if submitting { ProgressView().tint(Theme.onAccent) }
                    Text(submitting ? "提交中…" : "提交全部答案")
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!complete || submitting)
        }
        .padding(18)
        .card()
        .overlay { RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.accent.opacity(0.20)) }
        .disabled(submitting)
    }

    private var complete: Bool {
        prompt.questions.allSatisfy { question in
            answers.contains { $0.id == question.id && $0.isComplete(for: question) }
        }
    }

    private func selected(_ option: String, for question: UserQuestion) -> Bool {
        answers.first { $0.id == question.id }?.selected.contains(option) ?? false
    }

    private func toggle(_ option: String, for question: UserQuestion) {
        guard let index = answers.firstIndex(where: { $0.id == question.id }) else { return }
        if answers[index].selected.contains(option) {
            answers[index].selected.removeAll { $0 == option }
        } else if question.multiSelect {
            answers[index].selected.append(option)
        } else {
            answers[index].selected = [option]
            answers[index].custom = ""
        }
    }

    private func customBinding(for question: UserQuestion) -> Binding<String> {
        Binding {
            answers.first { $0.id == question.id }?.custom ?? ""
        } set: { text in
            guard let index = answers.firstIndex(where: { $0.id == question.id }) else { return }
            answers[index].custom = text
            if !question.multiSelect, !text.isEmpty { answers[index].selected = [] }
        }
    }
}
