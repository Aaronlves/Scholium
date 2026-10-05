import ScholiumContracts
import SwiftUI

struct AgentChatQuestionForm: View {
    let questions: [AgentChatQuestion]
    @Binding var answers: [String: AgentChatQuestionAnswer]
    let isSubmitting: Bool
    let failure: String?
    var canSubmit = true
    var toolContext: String? = nil
    var technicalDetail: String? = nil
    var stop: (() -> Void)? = nil
    let reply: () -> Void
    let skip: () -> Void
    @State private var questionIndex = 0

    private var currentQuestion: AgentChatQuestion? {
        questions.indices.contains(questionIndex) ? questions[questionIndex] : nil
    }

    private var hasCustomAnswer: Bool {
        guard let question = currentQuestion, case .text = answers[question.id] else { return false }
        return answers[question.id]?.value(for: question) != nil
    }

    private func advance() {
        guard !isSubmitting, let question = currentQuestion, answers[question.id]?.value(for: question) != nil else { return }
        if questionIndex + 1 < questions.count {
            questionIndex += 1
        } else if canSubmit && questions.allSatisfy({ answers[$0.id]?.value(for: $0) != nil }) {
            reply()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let toolContext {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tool Input Request", bundle: .module).font(.headline)
                    Text(verbatim: toolContext).font(.caption).foregroundStyle(.secondary)
                    if let technicalDetail {
                        DisclosureGroup {
                            ScrollView { Text(verbatim: technicalDetail).font(.caption.monospaced()).textSelection(.enabled) }.frame(
                                maxHeight: 100)
                        } label: {
                            Text("Details", bundle: .module).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.padding(.horizontal, 4)
            }
            AgentChatContentScroll {
                if let question = currentQuestion {
                    AgentChatQuestionField(
                        question: question, isReadOnly: isSubmitting,
                        isLast: questionIndex == questions.count - 1,
                        canAdvance: questionIndex < questions.count - 1 || canSubmit,
                        answer: Binding(get: { answers[question.id] }, set: { answers[question.id] = $0 }),
                        advance: advance
                    )
                    .id(question.id)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if isSubmitting { AgentChatSubmissionStatus(failure: failure) }
            if !isSubmitting, let failure {
                Text(failure).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if isSubmitting && failure != nil, let stop {
                    Button("End Turn", action: stop)
                        .accessibilityLabel(Text("End Turn", bundle: .module))
                }
                if questionIndex > 0 && !isSubmitting {
                    Button {
                        questionIndex -= 1
                    } label: {
                        Label {
                            Text("Previous Question", bundle: .module)
                        } icon: {
                            Image(systemName: "chevron.backward")
                        }
                    }.labelStyle(ScholiumSidebarActionLabelStyle())
                        .help(Text("Previous Question", bundle: .module))
                        .accessibilityLabel(Text("Previous Question", bundle: .module))
                }
                if !isSubmitting {
                    Button(action: skip) {
                        if toolContext != nil {
                            Label {
                                Text("Decline Request", bundle: .module)
                            } icon: {
                                Image(systemName: "xmark")
                            }
                        } else {
                            Label {
                                Text("Skip Questions", bundle: .module)
                            } icon: {
                                Image(systemName: "forward.end")
                            }
                        }
                    }.labelStyle(ScholiumSidebarActionLabelStyle())
                        .disabled(!canSubmit)
                        .accessibilityLabel(Text(toolContext != nil ? "Decline Request" : "Skip Questions", bundle: .module))
                        .help(
                            Text(
                                toolContext != nil
                                    ? "Decline this tool input request and stop the current turn."
                                    : "Skip all questions in this request without supplying answers.", bundle: .module))
                }
                Spacer(minLength: 0)
                if questions.count > 1 {
                    Text("Question \(questionIndex + 1) of \(questions.count)", bundle: .module)
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !isSubmitting, let question = currentQuestion, question.options.isEmpty || question.allowsOther {
                    Button(action: advance) {
                        AgentChatComposerIcon(content: .action(questionIndex == questions.count - 1 ? "arrow.up.circle.fill" : "arrow.right.circle.fill"))
                            .agentChatComposerControl()
                    }
                    .buttonStyle(ScholiumContentActionButtonStyle())
                    .agentChatComposerControl()
                    .help(Text(questionIndex == questions.count - 1 ? "Send Answer" : "Next Question", bundle: .module))
                    .accessibilityLabel(Text(questionIndex == questions.count - 1 ? "Send Answer" : "Next Question", bundle: .module))
                    .disabled(!hasCustomAnswer || (questionIndex == questions.count - 1 && !canSubmit))
                }
            }.buttonStyle(ScholiumContentActionButtonStyle()).controlSize(.regular)

        }
        .buttonStyle(.plain)
        .textFieldStyle(.roundedBorder)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.chat.questions")
    }
}

private struct AgentChatQuestionField: View {
    let question: AgentChatQuestion
    let isReadOnly: Bool
    let isLast: Bool
    let canAdvance: Bool
    @Binding var answer: AgentChatQuestionAnswer?
    let advance: () -> Void
    @AccessibilityFocusState private var promptIsFocused: Bool

    private var text: Binding<String> {
        Binding(get: { if case .text(let value) = answer { value } else { "" } }, set: { answer = .text($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question.prompt).font(.headline).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($promptIsFocused)
            if isReadOnly {
                if question.isSecret {
                    Text("Answer Hidden", bundle: .module).foregroundStyle(.secondary)
                } else if let value = answer?.value(for: question) {
                    Text(value).textSelection(.enabled)
                }
            } else {
                ForEach(question.options, id: \.label) { option in
                    Button {
                        answer = .option(option.label)
                        advance()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                if !option.description.isEmpty {
                                    Text(option.description).font(.caption).foregroundStyle(.secondary)
                                }
                            }.fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Image(systemName: answer == .option(option.label) ? "checkmark" : "chevron.forward")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ScholiumContentActionButtonStyle(restingRole: .primaryText))
                    .disabled(!canAdvance)
                    .accessibilityLabel(Text(verbatim: option.label))
                    .accessibilityValue(Text(verbatim: option.description))
                    .accessibilityAddTraits(answer == .option(option.label) ? .isSelected : [])
                    .help(Text(isLast ? "Send Answer" : "Next Question", bundle: .module))
                }
                if question.options.isEmpty || question.allowsOther {
                    Group {
                        if question.isSecret {
                            SecureField(text: text) { Text("Your Answer", bundle: .module) }
                        } else {
                            TextField(text: text, axis: .vertical) { Text("Your Answer", bundle: .module) }
                                .lineLimit(1...5)
                        }
                    }
                    .simultaneousGesture(TapGesture().onEnded { answer = .text(text.wrappedValue) })
                }
            }
        }
        .onAppear {
            promptIsFocused = true
        }
        .accessibilityElement(children: .contain)
    }
}
