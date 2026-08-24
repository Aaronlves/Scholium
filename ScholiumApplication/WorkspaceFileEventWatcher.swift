import ScholiumContracts
import Foundation
import ScholiumCore

/// Immutable state exposed to the native C callback. The continuation is the
/// only cross-queue capability; all stream ownership remains in the actor.
private final class WorkspaceFSEventCallbackContext: Sendable {
    let rootURL: URL
    let continuation: AsyncStream<VaultWatchEvent>.Continuation

    init(
        rootURL: URL,
        continuation: AsyncStream<VaultWatchEvent>.Continuation
    ) {
        self.rootURL = rootURL
        self.continuation = continuation
    }
}

/// One pending native invalidation is sufficient: authoritative filesystem
/// state is always reread before publication. If the callback queue outruns the
/// pooled consumer, replace the newest slot with a reconciliation requirement
/// rather than retaining an incomplete path delta.
enum WorkspaceWatchEventBuffer {
    static func makeStream() -> (
        stream: AsyncStream<VaultWatchEvent>,
        continuation: AsyncStream<VaultWatchEvent>.Continuation
    ) {
        AsyncStream<VaultWatchEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    static func yield(
        _ event: VaultWatchEvent,
        to continuation: AsyncStream<VaultWatchEvent>.Continuation
    ) {
        guard case .dropped(let displaced) = continuation.yield(event) else {
            return
        }
        continuation.yield(.reconciliationRequired(
            sequence: max(displaced.sequence, event.sequence),
            rootChanged: displaced.rootChanged || event.rootChanged
        ))
    }
}

enum WorkspaceFileEventWatcherError: LocalizedError, Sendable {
    case rootUnavailable(String)
    case streamUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .rootUnavailable(let path):
            "The vault root is unavailable: \(path)"
        case .streamUnavailable(let path):
            "Scholium could not start native file observation for \(path)."
        }
    }
}

/// Application-owned native observation for one vault root. The watcher is
/// established before the initial inventory and stopped deterministically by
/// its `WorkspaceHandle`; windows never own or replace this stream.
actor WorkspaceFileEventWatcher {
    nonisolated let rootURL: URL
    private let callbackQueue: DispatchQueue

    private var nativeStream: FSEventStreamRef?
    private var callbackContext: WorkspaceFSEventCallbackContext?
    private var continuation: AsyncStream<VaultWatchEvent>.Continuation?
    private var eventStream: AsyncStream<VaultWatchEvent>?

    init(rootURL: URL) {
        self.rootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        callbackQueue = DispatchQueue(
            label: "app.scholium.workspace-watcher.\(UUID().uuidString)",
            qos: .utility
        )
    }

    func start() throws -> AsyncStream<VaultWatchEvent> {
        if let eventStream { return eventStream }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: rootURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw WorkspaceFileEventWatcherError.rootUnavailable(rootURL.path)
        }

        let pair = WorkspaceWatchEventBuffer.makeStream()
        let contextOwner = WorkspaceFSEventCallbackContext(
            rootURL: rootURL,
            continuation: pair.continuation
        )
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(contextOwner).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<WorkspaceFSEventCallbackContext>
                    .fromOpaque(info)
                    .retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<WorkspaceFSEventCallbackContext>
                    .fromOpaque(info)
                    .release()
            },
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagWatchRoot
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, callbackInfo, eventCount, eventPaths, eventFlags, eventIDs in
                guard let callbackInfo else { return }
                let owner = Unmanaged<WorkspaceFSEventCallbackContext>
                    .fromOpaque(callbackInfo)
                    .takeUnretainedValue()
                let paths = Unmanaged<NSArray>.fromOpaque(eventPaths).takeUnretainedValue()
                guard eventCount <= paths.count else { return }

                var added: [String] = []
                var modified: [String] = []
                var deleted: [String] = []
                var requiresFullRescan = false
                var rootChanged = false
                var latestEventID: UInt64 = 0
                var sawRenamedMarkdownAddition = false
                var sawRenamedMarkdownDeletion = false

                for index in 0..<eventCount {
                    guard let fullPath = paths[index] as? String else { continue }
                    let flag = eventFlags[index]
                    latestEventID = max(latestEventID, eventIDs[index])
                    requiresFullRescan = requiresFullRescan
                        || (flag & UInt32(kFSEventStreamEventFlagMustScanSubDirs)) != 0
                        || (flag & UInt32(kFSEventStreamEventFlagUserDropped)) != 0
                        || (flag & UInt32(kFSEventStreamEventFlagKernelDropped)) != 0
                        || (flag & UInt32(kFSEventStreamEventFlagEventIdsWrapped)) != 0
                    rootChanged = rootChanged
                        || (flag & UInt32(kFSEventStreamEventFlagRootChanged)) != 0

                    let created = (flag & UInt32(kFSEventStreamEventFlagItemCreated)) != 0
                    let removed = (flag & UInt32(kFSEventStreamEventFlagItemRemoved)) != 0
                    let renamed = (flag & UInt32(kFSEventStreamEventFlagItemRenamed)) != 0
                    let isDirectory = (flag & UInt32(
                        kFSEventStreamEventFlagItemIsDir
                    )) != 0
                    // Directory events do not identify every descendant
                    // Markdown path, so treat them as intentionally coarse.
                    // This keeps empty-folder inventory correct without
                    // guessing a partial note delta.
                    requiresFullRescan = requiresFullRescan
                        || (isDirectory && (created || removed || renamed))

                    guard let relativePath = VaultPath.relativePath(
                        for: URL(fileURLWithPath: fullPath),
                        in: owner.rootURL
                    ), relativePath.lowercased().hasSuffix(".md") else {
                        continue
                    }
                    let changed = (flag & UInt32(kFSEventStreamEventFlagItemModified)) != 0
                    let metadataChanged =
                        (flag & UInt32(kFSEventStreamEventFlagItemChangeOwner)) != 0
                        || (flag & UInt32(kFSEventStreamEventFlagItemXattrMod)) != 0
                    let exists = FileManager.default.fileExists(atPath: fullPath)

                    if removed || (renamed && !exists) {
                        deleted.append(relativePath)
                        if renamed { sawRenamedMarkdownDeletion = true }
                    } else if created || (renamed && exists) {
                        added.append(relativePath)
                        if renamed { sawRenamedMarkdownAddition = true }
                    } else if changed || metadataChanged {
                        modified.append(relativePath)
                    }
                }

                // macOS may split one rename across separate native
                // callbacks. A callback containing only one side is coarse:
                // reconcile from descriptor-authorized authority so Scholium
                // never publishes a transient Added or Deleted generation.
                // When both sides arrive together, retain the precise delta.
                if sawRenamedMarkdownAddition != sawRenamedMarkdownDeletion {
                    requiresFullRescan = true
                }

                guard !added.isEmpty || !modified.isEmpty || !deleted.isEmpty
                        || requiresFullRescan || rootChanged else { return }
                WorkspaceWatchEventBuffer.yield(VaultWatchEvent(
                    added: added,
                    modified: modified,
                    deleted: deleted,
                    sequence: latestEventID,
                    requiresFullRescan: requiresFullRescan,
                    rootChanged: rootChanged
                ), to: owner.continuation)
            },
            &context,
            [rootURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            flags
        ) else {
            pair.continuation.finish()
            throw WorkspaceFileEventWatcherError.streamUnavailable(rootURL.path)
        }

        callbackContext = contextOwner
        continuation = pair.continuation
        eventStream = pair.stream
        nativeStream = stream
        FSEventStreamSetDispatchQueue(stream, callbackQueue)
        guard FSEventStreamStart(stream) else {
            stopNativeStream()
            pair.continuation.finish()
            callbackContext = nil
            continuation = nil
            eventStream = nil
            throw WorkspaceFileEventWatcherError.streamUnavailable(rootURL.path)
        }
        pair.continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.stop() }
        }
        return pair.stream
    }

    func stop() {
        let activeContinuation = continuation
        continuation = nil
        eventStream = nil
        stopNativeStream()
        callbackContext = nil
        activeContinuation?.finish()
    }

    private func stopNativeStream() {
        guard let nativeStream else { return }
        self.nativeStream = nil
        FSEventStreamStop(nativeStream)
        FSEventStreamInvalidate(nativeStream)
        // Invalidation prevents new delivery. Drain the dedicated queue before
        // releasing the stream so no callback can outlive its retained
        // FSEventStreamContext during rapid runtime replacement.
        callbackQueue.sync {}
        FSEventStreamRelease(nativeStream)
    }
}
