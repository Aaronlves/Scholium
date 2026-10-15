import Foundation

/// A presentation owns cold reader work from parsing through measured WebKit
/// readiness. Existing pages and their in-place updates never enter this queue.
@MainActor
final class AgentChatReaderPreparation {
    struct Reader: Hashable {
        let presentationID: UUID
        let id: String
        let instance: UUID
    }
    struct Permit {
        let reader: Reader
        let acquisitionID: UUID
    }
    private struct Request {
        let id: UUID
        let reader: Reader
        let continuation: CheckedContinuation<Permit?, Never>
    }
    static let concurrentReaders = 2
    private var presentationID: UUID?
    private var active: [Reader: UUID] = [:]
    private var pending: [Request] = []
    private var isScrolling = false
    private var pumpScheduled = false

    func begin(_ id: UUID) {
        guard presentationID != id else { return }
        end()
        presentationID = id
    }

    func end() {
        presentationID = nil
        isScrolling = false
        active = [:]
        let requests = pending
        pending = []
        requests.forEach { $0.continuation.resume(returning: nil) }
    }

    func setScrolling(_ scrolling: Bool) {
        isScrolling = scrolling
        if !scrolling { schedulePump() }
    }

    func acquire(_ reader: Reader) async -> Permit? {
        guard !Task.isCancelled, reader.presentationID == presentationID else { return nil }
        let requestID = UUID()
        if active[reader] != nil {
            // A newer source task inherits the same native reader's slot.
            // Its predecessor's cancellation cannot release this acquisition.
            active[reader] = requestID
            return Permit(reader: reader, acquisitionID: requestID)
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pending.append(Request(id: requestID, reader: reader, continuation: continuation))
                schedulePump()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelRequest(requestID) }
        }
    }

    func complete(_ reader: Reader) {
        guard active.removeValue(forKey: reader) != nil else { return }
        schedulePump()
    }

    func remove(_ reader: Reader) {
        active.removeValue(forKey: reader)
        let removed = pending.filter { $0.reader == reader }
        pending.removeAll { $0.reader == reader }
        removed.forEach { $0.continuation.resume(returning: nil) }
        schedulePump()
    }

    func releaseUnstarted(_ permit: Permit) {
        guard active[permit.reader] == permit.acquisitionID else { return }
        active.removeValue(forKey: permit.reader)
        schedulePump()
    }

    private func cancelRequest(_ id: UUID) {
        if let index = pending.firstIndex(where: { $0.id == id }) {
            pending.remove(at: index).continuation.resume(returning: nil)
        } else if let reader = active.first(where: { $0.value == id })?.key {
            releaseUnstarted(Permit(reader: reader, acquisitionID: id))
        }
    }

    private func schedulePump() {
        guard !pumpScheduled else { return }
        pumpScheduled = true
        // Admit outside the current renderer callback, one request per work
        // item, instead of synchronously starting the entire waiting set.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pumpScheduled = false
            self.pump()
        }
    }

    private func pump() {
        guard presentationID != nil, !isScrolling,
            active.count < Self.concurrentReaders, !pending.isEmpty else { return }
        let request = pending.removeFirst()
        guard request.reader.presentationID == presentationID else {
            request.continuation.resume(returning: nil)
            schedulePump()
            return
        }
        active[request.reader] = request.id
        request.continuation.resume(returning: Permit(reader: request.reader, acquisitionID: request.id))
        if active.count < Self.concurrentReaders { schedulePump() }
    }
}
