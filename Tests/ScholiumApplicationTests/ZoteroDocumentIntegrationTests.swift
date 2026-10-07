import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Outbound Zotero document integration")
struct ZoteroDocumentIntegrationTests {
    private static let documentID = "synthetic-document"
    private static let transactionID = "synthetic-transaction"
    private static let first = ZoteroDocumentField(id: "field-first", code: "ITEM CSL_CITATION {\"vendor\":true}", text: "Manually edited visible text")

    @Test("Current object fields and opaque vendor strings use only the two fixed POST endpoints")
    func protocolShapeAndExactVendorStrings() async throws {
        let vendor = "\u{FEFF}<data style='author-date'>\r\nunknown &amp; 😀\n</data>"
        let code =
            "ITEM CSL_CITATION { \"citationID\":\"vendor-id\",\"properties\":{\"formattedCitation\":\"<i>Title</i>\",\"plainCitation\":\"Title\"},\"future\": [ 1, 2 ] }"
        let html = "<i>Title</i> &amp; text"
        let script = Script([
            integrationCallback("Application.getActiveDocument", document: false), integrationCallback("Document.getDocumentData"),
            integrationCallback("Document.getFields", .string("Http")), integrationCallback("Document.cursorInField", .string("Http")),
            integrationCallback("Document.setDocumentData", .string(vendor)), integrationCallback("Field.setCode", .string(Self.first.id), .string(code)),
            integrationCallback("Field.setText", .string(Self.first.id), .string(html), .bool(true)),
            integrationCallback(
                "Document.setBibliographyStyle", .integer(-720), .integer(720), .integer(240), .integer(0), .array([.integer(720)]), .integer(1)),
            integrationCallback("Document.complete"),
        ])
        let handler = SourceHandler(fields: [Self.first])
        let client = ZoteroDocumentIntegration(transport: { try await script.send($0) })
        let result = await client.run(
            transactionID: Self.transactionID, command: .addEditCitation, documentID: Self.documentID, authority: { .current },
            handler: { try await handler.handle($0) })
        #expect(result.status == .cleanedUp)
        #expect(result.remoteCleanupConfirmed)
        #expect(result.callbackCount == 9)
        let requests = await script.requests
        #expect(requests.count == 9)  // No response after Document.complete.
        #expect(requests.first?.url?.absoluteString == "http://127.0.0.1:23119/connector/document/execCommand")
        #expect(requests.dropFirst().allSatisfy { $0.url?.absoluteString == "http://127.0.0.1:23119/connector/document/respond" })
        #expect(requests.allSatisfy { $0.httpMethod == "POST" && $0.timeoutInterval == 3_600 })
        #expect(
            requests.allSatisfy {
                $0.value(forHTTPHeaderField: "Content-Type") == "application/json"
                    && $0.value(forHTTPHeaderField: "Accept") == "application/json"
                    && $0.value(forHTTPHeaderField: "Authorization") == nil
                    && $0.url?.query == nil && $0.url?.fragment == nil && $0.url?.user == nil
            })
        #expect(try json(requests[0]) == .object(["command": .string("addEditCitation"), "docId": .string(Self.documentID)]))
        #expect(
            try json(requests[1])
                == .object([
                    "documentID": .string(Self.documentID), "outputFormat": .string("html"), "supportedNotes": .array([]),
                    "processorName": .string("Scholium"), "supportsImportExport": .bool(false),
                    "supportsTextInsertion": .bool(false), "supportsCitationMerging": .bool(false),
                ]))
        #expect(try json(requests[3]) == .array([fieldJSON(Self.first)]))
        #expect(try json(requests[4]) == fieldJSON(Self.first))
        #expect(await handler.documentData == vendor)
        #expect(await handler.code == code)
        #expect(await handler.html == html)
        #expect(await handler.style == ZoteroBibliographyStyle(firstLineIndent: -720, indent: 720, lineSpacing: 240, entrySpacing: 0, tabStops: [720]))
    }

    @Test("Complete alone confirms cleanup without establishing citation acceptance")
    func completeIsNotSuccess() async throws {
        let script = Script([integrationCallback("Document.complete")])
        let client = ZoteroDocumentIntegration(transport: { try await script.send($0) })
        let result = await client.run(
            transactionID: Self.transactionID, command: .addEditCitation, documentID: Self.documentID, authority: { .current },
            handler: { _ in
                Issue.record("No callback should reach the source owner")
                return .none
            })
        #expect(result.status == .cleanedUp)
        #expect(result.remoteCleanupConfirmed)
        #expect(await script.requests.count == 1)
    }

    @Test("Installed Zotero passes Http to canInsertField before creating a TEMP field")
    func installedInsertionSignature() async throws {
        let inserted = ZoteroDocumentField(id: "new-field", code: "", text: "{Citation}")
        let script = Script([
            integrationCallback("Document.canInsertField", .string("Http")),
            integrationCallback("Document.cursorInField", .string("Http")),
            integrationCallback("Document.insertField", .string("Http"), .integer(0)),
            integrationCallback("Field.setCode", .string(inserted.id), .string("TEMP")),
            integrationCallback("Field.delete", .string(inserted.id)), integrationCallback("Document.complete"),
        ])
        let client = ZoteroDocumentIntegration(transport: { try await script.send($0) })
        let result = await client.run(
            transactionID: Self.transactionID, command: .addEditCitation, documentID: Self.documentID, authority: { .current },
            handler: { callback in
                switch callback {
                case .canInsertField: .boolean(true)
                case .cursorInField: .field(nil)
                case .insertField: .field(inserted)
                case .setFieldCode(_, "TEMP"), .deleteField: .none
                default: throw SyntheticFailure.privateSource
                }
            })
        #expect(result.status == .cleanedUp)
        #expect(result.remoteCleanupConfirmed)
        #expect(await script.requests.count == 6)
    }

    @Test("Busy belongs to another remote transaction and receives no respond request")
    func remoteBusy() async throws {
        let script = Script([.init(statusCode: 503, body: Data("busy".utf8))])
        let client = ZoteroDocumentIntegration(transport: { try await script.send($0) })
        let result = await client.run(
            transactionID: Self.transactionID, command: .refresh, documentID: Self.documentID, authority: { .current }, handler: { _ in .none })
        #expect(result.status == .busy)
        #expect(!result.remoteCleanupConfirmed)
        #expect(await script.requests.count == 1)
    }

    @Test("A pending human picker serializes local work and cancellation drains remotely")
    func cancelHumanWait() async throws {
        let wait = WaitPoint()
        let script = Script(
            [
                integrationCallback("Application.getActiveDocument", document: false),
                integrationCallback("Document.getFields", .string("Http")), integrationCallback("Document.activate"), integrationCallback("Document.complete"),
            ], waitAtRequest: 2, wait: wait)
        let handler = SourceHandler(fields: [Self.first])
        let client = ZoteroDocumentIntegration(transport: { try await script.send($0) })
        let pending = Task {
            await client.run(
                transactionID: Self.transactionID, command: .addEditCitation, documentID: Self.documentID, authority: { .current },
                handler: { try await handler.handle($0) })
        }
        await wait.untilEntered()
        let competing = await client.run(
            transactionID: "competing-transaction", command: .refresh, documentID: Self.documentID, authority: { .current }, handler: { _ in .none })
        #expect(competing.status == .busy)
        await client.cancelCurrentTransaction(transactionID: Self.transactionID)
        pending.cancel()  // Cancelling the caller does not cancel the outbound request.
        await wait.release()
        let result = await pending.value
        #expect(result.status == .cancelled)
        #expect(result.remoteCleanupConfirmed)
        #expect(await handler.callbacks.isEmpty)
        let requests = await script.requests
        #expect(requests.count == 4)
        #expect(try json(requests[2]).objectValue?["error"] == .string("Scholium Document Error"))
        #expect(try json(requests[3]).objectValue?["error"] == .string("Scholium Document Error"))
    }

    @Test("A second window's cancellation cannot revoke the active transaction")
    func foreignLocalCancellation() async throws {
        let wait = WaitPoint()
        let script = Script(
            [
                integrationCallback("Application.getActiveDocument", document: false),
                integrationCallback("Document.getFields", .string("Http")), integrationCallback("Document.complete"),
            ], waitAtRequest: 2, wait: wait)
        let handler = SourceHandler(fields: [Self.first])
        let client = ZoteroDocumentIntegration(transport: { try await script.send($0) })
        let pending = Task {
            await client.run(
                transactionID: Self.transactionID, command: .addEditCitation, documentID: Self.documentID,
                authority: { .current }, handler: { try await handler.handle($0) })
        }
        await wait.untilEntered()
        let competingID = "other-window-transaction"
        let competing = await client.run(
            transactionID: competingID, command: .refresh, documentID: Self.documentID,
            authority: { .current }, handler: { _ in .none })
        #expect(competing.status == .busy)
        await client.cancelCurrentTransaction(transactionID: competingID)
        await wait.release()
        let result = await pending.value
        #expect(result.status == .cleanedUp)
        #expect(result.remoteCleanupConfirmed)
        #expect(await handler.callbacks == [.getFields])
        let requests = await script.requests
        #expect(requests.count == 3)
        #expect(try json(requests[2]) == .array([fieldJSON(Self.first)]))
    }

    @Test("Document departure during a handler revokes authority and drains without later handler effects")
    func invalidatedDuringHandler() async throws {
        let authority = AuthorityState()
        let script = Script([
            integrationCallback("Document.getDocumentData"), integrationCallback("Document.getFields", .string("Http")),
            integrationCallback("Document.complete"),
        ])
        let client = ZoteroDocumentIntegration(transport: { try await script.send($0) })
        let result = await client.run(
            transactionID: Self.transactionID, command: .refresh, documentID: Self.documentID, authority: { await authority.value },
            handler: { callback in
                #expect(callback == .getDocumentData)
                await authority.set(.unavailable)
                return .string("Never published source")
            })
        #expect(result.status == .unavailable)
        #expect(result.remoteCleanupConfirmed)
        let requests = await script.requests
        #expect(requests.count == 3)
        #expect(try json(requests[1]).objectValue?["error"] == .string("Tab Not Available Error"))
        #expect(try json(requests[2]).objectValue?["error"] == .string("Tab Not Available Error"))
    }

    @Test(
        "Foreign, unsupported and malformed callbacks fail closed and still drain cleanup",
        arguments: [
            integrationCallback("Document.getDocumentData", .string("extra")),
            integrationCallback("Document.getDocumentData", documentID: "foreign-document"),
            integrationCallback("Field.setText", .string("foreign-field"), .string("bad"), .bool(true)),
            integrationCallback("Document.insertField", .string("Http"), .integer(1)),
            integrationCallback("Document.getFields", .string("ReferenceMark")),
            integrationCallback("Document.insertText", .string("unsupported")),
            integrationCallback("Document.convert", .array([]), .string("Http"), .array([])),
            integrationCallback("Document.setBibliographyStyle", .integer(0), .integer(0), .integer(240), .integer(0), .array([]), .integer(1)),
            integrationCallback("Document.setBibliographyStyle", .integer(0), .integer(0), .integer(0), .integer(0), .array([]), .integer(0)),
            integrationCallback("Document.setBibliographyStyle", .integer(0), .integer(0), .integer(-240), .integer(0), .array([]), .integer(0)),
            integrationCallback("Document.setBibliographyStyle", .integer(0), .integer(0), .integer(240), .integer(-1), .array([]), .integer(0)),
            .init(statusCode: 200, body: Data("{malformed json".utf8)),
        ])
    func refusedCallback(_ bad: ZoteroDocumentHTTPResponse) async throws {
        let script = Script([bad, integrationCallback("Document.complete")])
        let client = ZoteroDocumentIntegration(transport: { try await script.send($0) })
        let result = await client.run(
            transactionID: Self.transactionID, command: .refresh, documentID: Self.documentID, authority: { .current },
            handler: { _ in
                Issue.record("Invalid callback must not reach source owner")
                return .none
            })
        #expect(result.status == .failed)
        #expect(result.remoteCleanupConfirmed)
        let requests = await script.requests
        #expect(requests.count == 2)
        #expect(try json(requests[1]).objectValue?["error"] == .string("Scholium Document Error"))
    }

    @Test("Duplicate or incorrectly typed replies are refused before a field can gain authority")
    func refusedReply() async throws {
        for reply in [ZoteroDocumentReply.fields([Self.first, Self.first]), .string("incorrect reply")] {
            let script = Script([
                integrationCallback("Document.getFields", .string("Http")), integrationCallback("Field.setCode", .string(Self.first.id), .string("bad")),
                integrationCallback("Document.complete"),
            ])
            let client = ZoteroDocumentIntegration(transport: { try await script.send($0) })
            let result = await client.run(
                transactionID: Self.transactionID, command: .refresh, documentID: Self.documentID, authority: { .current },
                handler: { callback in
                    #expect(callback == .getFields)
                    return reply
                })
            #expect(result.status == .failed)
            #expect(result.remoteCleanupConfirmed)
            #expect(await script.requests.count == 3)
        }
    }

    @Test("New fields are declared once and deletion removes their callback authority")
    func fieldIdentityLifecycle() async throws {
        let inserted = ZoteroDocumentField(id: "new-field", code: "", text: "{Citation}")
        let script = Script([
            integrationCallback("Document.insertField", .string("Http"), .integer(0)),
            integrationCallback("Field.setCode", .string(inserted.id), .string("ITEM CSL_CITATION {}")),
            integrationCallback("Field.delete", .string(inserted.id)), integrationCallback("Field.setCode", .string(inserted.id), .string("foreign")),
            integrationCallback("Document.complete"),
        ])
        let client = ZoteroDocumentIntegration(transport: { try await script.send($0) })
        let result = await client.run(
            transactionID: Self.transactionID, command: .addEditCitation, documentID: Self.documentID, authority: { .current },
            handler: { callback in
                switch callback {
                case .insertField: return .field(inserted)
                case .setFieldCode(_, "ITEM CSL_CITATION {}"): return .none
                case .deleteField(let id) where id == inserted.id: return .none
                default:
                    Issue.record("A deleted field cannot authorize later callbacks")
                    return .none
                }
            })
        #expect(result.status == .failed)
        #expect(result.remoteCleanupConfirmed)
        #expect(await script.requests.count == 5)
    }

    @Test("Handler errors are sent without leaking source or error descriptions")
    func handlerFailurePrivacy() async throws {
        let script = Script([integrationCallback("Document.getDocumentData"), integrationCallback("Document.complete")])
        let client = ZoteroDocumentIntegration(transport: { try await script.send($0) })
        let result = await client.run(
            transactionID: Self.transactionID, command: .refresh, documentID: Self.documentID, authority: { .current },
            handler: { _ in throw SyntheticFailure.privateSource })
        #expect(result.status == .failed)
        #expect(result.remoteCleanupConfirmed)
        let payload = try json(await script.requests[1])
        #expect(payload.objectValue?["stack"] == nil)
        #expect(payload.objectValue?["message"] == .string("The citation transaction no longer has document authority."))
    }

    @Test("Foreign completion is never answered and cannot prove cleanup")
    func foreignCompletion() async throws {
        let script = Script([integrationCallback("Document.complete", documentID: "foreign")])
        let client = ZoteroDocumentIntegration(transport: { try await script.send($0) })
        let result = await client.run(
            transactionID: Self.transactionID, command: .refresh, documentID: Self.documentID, authority: { .current }, handler: { _ in .none })
        #expect(result.status == .unknown)
        #expect(!result.remoteCleanupConfirmed)
        #expect(await script.requests.count == 1)
    }

    @Test("Transport loss or unexpected HTTP status never retries or claims cleanup")
    func unknownTransportOutcome() async throws {
        for responses in [[integrationCallback("Application.getActiveDocument", document: false)], [.init(statusCode: 500, body: Data())]] {
            let script = Script(responses)
            let client = ZoteroDocumentIntegration(transport: { try await script.send($0) })
            let result = await client.run(
                transactionID: Self.transactionID, command: .refresh, documentID: Self.documentID, authority: { .current }, handler: { _ in .none })
            #expect(result.status == .unknown)
            #expect(!result.remoteCleanupConfirmed)
            #expect(result.message?.contains("restart Zotero") == true)
            #expect(await script.requests.count == responses.count + (responses[0].statusCode == 200 ? 1 : 0))
        }
    }

    @Test("Callback limit initiates an error-drain; exhausted drain reports explicit uncertainty")
    func callbackBoundAndCleanup() async throws {
        let commands = [integrationCallback("Document.activate"), integrationCallback("Document.activate"), integrationCallback("Document.complete")]
        let script = Script(commands)
        let client = ZoteroDocumentIntegration(transport: { try await script.send($0) }, maximumCallbacks: 1, maximumDrainCallbacks: 2)
        let result = await client.run(
            transactionID: Self.transactionID, command: .refresh, documentID: Self.documentID, authority: { .current }, handler: { _ in .none })
        #expect(result.status == .failed)
        #expect(result.remoteCleanupConfirmed)
        #expect(await script.requests.count == 3)
        let uncooperative = Script(Array(repeating: integrationCallback("Document.activate"), count: 8))
        let bounded = ZoteroDocumentIntegration(transport: { try await uncooperative.send($0) }, maximumCallbacks: 1, maximumDrainCallbacks: 2)
        let unknown = await bounded.run(
            transactionID: Self.transactionID, command: .refresh, documentID: Self.documentID, authority: { .current }, handler: { _ in .none })
        #expect(unknown.status == .unknown)
        #expect(!unknown.remoteCleanupConfirmed)
        #expect(await uncooperative.requests.count == 4)
    }

    @Test("Invalid identity and stale initial authority issue no outbound request")
    func initialAdmission() async throws {
        let script = Script([])
        let client = ZoteroDocumentIntegration(transport: { try await script.send($0) })
        let invalid = await client.run(
            transactionID: Self.transactionID, command: .refresh, documentID: "bad\nidentity", authority: { .current }, handler: { _ in .none })
        #expect(invalid.status == .failed)
        for transactionID in ["", "bad\nidentity", String(repeating: "x", count: 129)] {
            let invalidTransaction = await client.run(
                transactionID: transactionID, command: .refresh, documentID: Self.documentID,
                authority: { .current }, handler: { _ in .none })
            #expect(invalidTransaction.status == .failed)
        }
        let stale = await client.run(
            transactionID: Self.transactionID, command: .refresh, documentID: Self.documentID, authority: { .unavailable }, handler: { _ in .none })
        #expect(stale.status == .unavailable)
        #expect(await script.requests.isEmpty)
    }

    @Test("A manuscript with 500 fields permits the complete refresh callback sequence")
    func manyFields() async throws {
        let fields = (0..<500).map { ZoteroDocumentField(id: "field-\($0)", code: "ITEM CSL_CITATION {\"id\":\($0)}", text: "[\($0 + 1)]") }
        let updates = fields.flatMap { field in
            [
                integrationCallback("Field.setText", .string(field.id), .string(field.text), .bool(true)),
                integrationCallback("Field.setCode", .string(field.id), .string(field.code)),
            ]
        }
        let script = Script([integrationCallback("Document.getFields", .string("Http"))] + updates + [integrationCallback("Document.complete")])
        let client = ZoteroDocumentIntegration(transport: { try await script.send($0) })
        let result = await client.run(
            transactionID: Self.transactionID, command: .refresh, documentID: Self.documentID, authority: { .current },
            handler: { callback in
                switch callback {
                case .getFields: .fields(fields)
                case .setFieldCode, .setFieldText: .none
                default: throw SyntheticFailure.privateSource
                }
            })
        #expect(result.status == .cleanedUp)
        #expect(result.remoteCleanupConfirmed)
        #expect(result.callbackCount == 1_002)
        #expect(await script.requests.count == 1_002)
    }

    @Test("Oversized vendor strings are refused and their bytes never enter a respond payload")
    func vendorStringBound() async throws {
        let oversized = String(repeating: "x", count: 8 * 1_024 * 1_024 + 1)
        let script = Script([integrationCallback("Document.getDocumentData"), integrationCallback("Document.complete")])
        let client = ZoteroDocumentIntegration(transport: { try await script.send($0) })
        let result = await client.run(
            transactionID: Self.transactionID, command: .refresh, documentID: Self.documentID, authority: { .current }, handler: { _ in .string(oversized) })
        #expect(result.status == .failed)
        #expect(result.remoteCleanupConfirmed)
        #expect(await script.requests[1].httpBody?.count ?? 0 < 512)
    }

    @Test("Unsupported bibliography layout at the source owner drains as an error")
    func bibliographyOwnerRefusal() async throws {
        let script = Script([
            integrationCallback("Document.setBibliographyStyle", .integer(-720), .integer(720), .integer(240), .integer(0), .array([]), .integer(0)),
            integrationCallback("Document.complete"),
        ])
        let client = ZoteroDocumentIntegration(transport: { try await script.send($0) })
        let result = await client.run(
            transactionID: Self.transactionID, command: .addEditBibliography, documentID: Self.documentID, authority: { .current },
            handler: { callback in
                guard case .setBibliographyStyle = callback else {
                    Issue.record("Unexpected callback")
                    return .none
                }
                throw SyntheticFailure.privateSource
            })
        #expect(result.status == .failed)
        #expect(result.remoteCleanupConfirmed)
        #expect(await script.requests.count == 2)
    }

    private func json(_ request: URLRequest) throws -> MCPJSONValue { try JSONDecoder().decode(MCPJSONValue.self, from: #require(request.httpBody)) }
    private func fieldJSON(_ field: ZoteroDocumentField) -> MCPJSONValue {
        .object([
            "id": .string(field.id), "code": .string(field.code), "text": .string(field.text), "noteIndex": .integer(field.noteIndex),
            "adjacent": .bool(field.adjacent),
        ])
    }

    private enum SyntheticFailure: Error { case privateSource, noMoreResponses }

    private actor Script {
        private var responses: [ZoteroDocumentHTTPResponse]
        private let waitAtRequest: Int?
        private let wait: WaitPoint?
        private(set) var requests: [URLRequest] = []

        init(_ responses: [ZoteroDocumentHTTPResponse], waitAtRequest: Int? = nil, wait: WaitPoint? = nil) {
            self.responses = responses
            self.waitAtRequest = waitAtRequest
            self.wait = wait
        }

        func send(_ request: URLRequest) async throws -> ZoteroDocumentHTTPResponse {
            requests.append(request)
            if requests.count == waitAtRequest { await wait?.enter() }
            guard !responses.isEmpty else { throw SyntheticFailure.noMoreResponses }
            return responses.removeFirst()
        }
    }

    private actor SourceHandler {
        private let fields: [ZoteroDocumentField]
        private(set) var documentData = ""
        private(set) var code = ""
        private(set) var html = ""
        private(set) var style: ZoteroBibliographyStyle?
        private(set) var callbacks: [ZoteroDocumentCallback] = []

        init(fields: [ZoteroDocumentField]) { self.fields = fields }

        func handle(_ callback: ZoteroDocumentCallback) throws -> ZoteroDocumentReply {
            callbacks.append(callback)
            switch callback {
            case .getDocumentData: return .string(documentData)
            case .setDocumentData(let value):
                documentData = value
                return .none
            case .getFields: return .fields(fields)
            case .cursorInField: return .field(fields.first)
            case .setFieldCode(_, let value):
                code = value
                return .none
            case .setFieldText(_, let value):
                html = value
                return .none
            case .setBibliographyStyle(let value):
                style = value
                return .none
            default: throw SyntheticFailure.privateSource
            }
        }
    }

    private actor AuthorityState {
        private(set) var value = ZoteroDocumentAuthority.current
        func set(_ next: ZoteroDocumentAuthority) { value = next }
    }

    private actor WaitPoint {
        private var entered = false
        private var released = false
        private var enterWaiters: [CheckedContinuation<Void, Never>] = []
        private var releaseWaiter: CheckedContinuation<Void, Never>?

        func enter() async {
            entered = true
            enterWaiters.forEach { $0.resume() }
            enterWaiters.removeAll()
            if !released { await withCheckedContinuation { releaseWaiter = $0 } }
        }

        func untilEntered() async {
            if !entered { await withCheckedContinuation { enterWaiters.append($0) } }
        }

        func release() {
            released = true
            releaseWaiter?.resume()
            releaseWaiter = nil
        }
    }
}

private func integrationCallback(_ command: String, _ args: MCPJSONValue..., document: Bool = true, documentID: String = "synthetic-document")
    -> ZoteroDocumentHTTPResponse
{
    let payload = MCPJSONValue.object(["command": .string(command), "arguments": .array((document ? [.string(documentID)] : []) + args)])
    return .init(statusCode: 200, body: try! JSONEncoder().encode(payload))
}
