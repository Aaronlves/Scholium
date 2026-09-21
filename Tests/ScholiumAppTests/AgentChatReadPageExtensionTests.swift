import Testing

@testable import ScholiumApp

@Suite("Chat read page extension admission")
@MainActor
struct AgentChatReadPageExtensionTests {
    @Test("Only interaction telemetry may omit the current reply fingerprint")
    func fingerprintBypassIsLimitedToInteractionTelemetry() {
        let pageExtension = AgentChatReadPageExtension()

        #expect(pageExtension.acceptsMessageWithoutCurrentFingerprint(type: "replyInteraction"))
        for type in [
            "replyLayout", "replyNoteContext", "replySelectionContext", "replyQuote",
        ] {
            #expect(!pageExtension.acceptsMessageWithoutCurrentFingerprint(type: type))
        }
    }
}
