import ScholiumContracts
import SwiftUI

struct AgentChatQuestionForm: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let questions: [AgentChatQuestion]
  @Binding var answers: [String: AgentChatQuestionAnswer]
  let isSubmitting: Bool
  let failure: String?
  var toolContext: String? = nil
  var technicalDetail: String? = nil
  let reply: () -> Void
  let skip: () -> Void

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
              Text("Operation Details", bundle: .module).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          ForEach(questions) { question in
            GroupBox {
              AgentChatQuestionField(
                question: question, isReadOnly: isSubmitting,
                answer: Binding(
                  get: { answers[question.id] }, set: { answers[question.id] = $0 })
              )
              .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.frame(maxHeight: 320)
      if isSubmitting {
        if let failure {
          Text(failure).font(.caption).foregroundStyle(.secondary)
        } else {
          HStack(spacing: 8) {
            if reduceMotion {
              Image(systemName: "ellipsis").accessibilityHidden(true)
            } else {
              ProgressView().controlSize(.small).accessibilityHidden(true)
            }
            Text("Waiting for Confirmation…", bundle: .module).font(.caption).foregroundStyle(.secondary)
          }
        }
      } else {
        HStack {
          Button(action: skip) {
            if toolContext != nil { Text("Stop Turn", bundle: .module) } else { Text("Skip", bundle: .module) }
          }
          Spacer(minLength: 0)
          Button(action: reply) { Text("Reply", bundle: .module) }
            .disabled(questions.contains { answers[$0.id]?.value(for: $0) == nil })
        }
      }
    }.padding()
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("scholium.chat.questions")
  }
}

private struct AgentChatQuestionField: View {
  private enum Choice: Hashable {
    case option(String)
    case other
  }
  let question: AgentChatQuestion
  let isReadOnly: Bool
  @Binding var answer: AgentChatQuestionAnswer?
  private var selection: Binding<Choice?> {
    Binding(
      get: {
        switch answer {
        case .option(let value): .option(value)
        case .text: .other
        case nil: nil
        }
      },
      set: { value in
        switch value {
        case .option(let label): answer = .option(label)
        case .other: answer = .text("")
        case nil: answer = nil
        }
      })
  }
  private var text: Binding<String> {
    Binding(get: { if case .text(let value) = answer { value } else { "" } }, set: { answer = .text($0) })
  }
  private var showsText: Bool {
    if question.options.isEmpty { return true }
    if case .text = answer { return true }
    return false
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(question.prompt).font(.body).fixedSize(horizontal: false, vertical: true)
      if isReadOnly {
        if question.isSecret {
          Text("Answer Hidden", bundle: .module).foregroundStyle(.secondary)
        } else if let value = answer?.value(for: question) {
          Text(value).textSelection(.enabled)
        }
      } else {
        if !question.options.isEmpty {
          Picker(question.prompt, selection: selection) {
            ForEach(question.options, id: \.label) { option in
              VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                if !option.description.isEmpty { Text(option.description).font(.caption).foregroundStyle(.secondary) }
              }.fixedSize(horizontal: false, vertical: true).tag(Optional(Choice.option(option.label)))
            }
            if question.allowsOther { Text("Write an Answer", bundle: .module).tag(Optional(Choice.other)) }
          }.pickerStyle(.radioGroup).labelsHidden()
        }
        if showsText {
          if question.isSecret {
            SecureField(text: text) { Text("Your Answer", bundle: .module) }
          } else {
            TextField(text: text, axis: .vertical) { Text("Your Answer", bundle: .module) }.lineLimit(2...5)
          }
        }
      }
    }.accessibilityElement(children: .contain)
  }
}
