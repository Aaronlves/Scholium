import Foundation
import ScholiumCore

/// Immutable state exposed to the C callback. Keeping the continuation and
/// root here avoids unsafely reading actor-isolated state on FSEvents' queue.
private final class FSEventCallbackContext: @unchecked Sendable {
  let rootPath: String
  let continuation: AsyncStream<VaultWatchEvent>.Continuation

  init(rootPath: String, continuation: AsyncStream<VaultWatchEvent>.Continuation) {
    self.rootPath = rootPath
    self.continuation = continuation
  }
}

/// Owns an FSEventStream exactly once. Both explicit vault shutdown and
/// AsyncStream cancellation may race to clean up; the native pointer must
/// never be stopped, invalidated, or released twice.
private final class FSEventStreamLifecycle: @unchecked Sendable {
  private let lock = NSLock()
  private var stream: FSEventStreamRef?
  private var callbackContext: FSEventCallbackContext?

  init(stream: FSEventStreamRef, callbackContext: FSEventCallbackContext) {
    self.stream = stream
    self.callbackContext = callbackContext
  }

  func stopAndRelease() {
    lock.lock()
    let ownedStream = stream
    let ownedCallbackContext = callbackContext
    stream = nil
    callbackContext = nil
    lock.unlock()

    guard let ownedStream else { return }
    FSEventStreamStop(ownedStream)
    FSEventStreamInvalidate(ownedStream)
    FSEventStreamRelease(ownedStream)
    // Retain the unowned C callback context through native stream release,
    // then break the continuation/onTermination ownership cycle.
    withExtendedLifetime(ownedCallbackContext) {}
  }

  deinit { stopAndRelease() }
}

// MARK: - Vault I/O Errors

enum VaultError: LocalizedError {
  case notADirectory(URL)
  case notAnObsidianVault(URL)
  case noteNotFound(String)
  case pathOutsideVault(String)
  case writeError(String)
  case configParseError(String)

  var errorDescription: String? {
    switch self {
    case .notADirectory(let url):
      return "Not a directory: \(url.path)"
    case .notAnObsidianVault(let url):
      return "No .obsidian/config found at \(url.path) — not an Obsidian vault"
    case .noteNotFound(let path):
      return "Note not found: \(path)"
    case .pathOutsideVault(let path):
      return "Path is outside the vault: \(path)"
    case .writeError(let detail):
      return "Failed to write note: \(detail)"
    case .configParseError(let detail):
      return "Failed to parse .obsidian config: \(detail)"
    }
  }
}

// MARK: - Vault Service

/// Central file-system actor for an Obsidian vault.
///
/// Responsible for opening a vault, scanning .md files, watching for live changes via FSEvents,
/// and reading/writing individual notes. All mutable app state (indexes, version history, review
/// data) lives outside the vault in `~/Library/Application Support/Scholium/`.
///
/// - Important: This service **never** creates files inside the vault. Only the user's note
///   content is written back on explicit save.
actor VaultService {

  // MARK: Private State

  /// The vault root URL once opened.
  private var vaultURL: URL?
  /// Parsed `.obsidian/` configuration, if present.
  private var config: VaultConfig?
  private var vaultRole: VaultRole = .other

  /// Single owner for the active native stream. Cleanup is idempotent because
  /// explicit shutdown and AsyncStream cancellation can arrive in either order.
  private var eventStreamLifecycle: FSEventStreamLifecycle?

  /// Continuation for the watch stream — stored so we can resume/yield.
  private var watchContinuation: AsyncStream<VaultWatchEvent>.Continuation?

  /// FileManager instance.
  private let fm = FileManager.default

  // MARK: - Open Vault

  /// Establishes the watched root before the first inventory begins. The
  /// shared runtime starts FSEvents immediately after this call, then performs
  /// the initial scan and a post-scan reconciliation so edits made during open
  /// cannot fall into a blind window.
  func prepareForObservation(
    at url: URL,
    role: VaultRole? = nil
  ) throws -> VaultConfig {
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
      throw VaultError.notADirectory(url)
    }
    let obsidianDir = url.appendingPathComponent(".obsidian", isDirectory: true)
    let obsidianConfig = fm.fileExists(atPath: obsidianDir.path)
      ? parseObsidianConfig(at: obsidianDir)
      : nil
    let vaultConfig = VaultConfig(
      path: url,
      name: url.lastPathComponent,
      obsidianConfig: obsidianConfig
    )
    vaultURL = url
    if let role { vaultRole = role }
    config = vaultConfig
    return vaultConfig
  }

  /// Opens an Obsidian vault at `url`, reads `.obsidian/` configuration, and recursively
  /// scans all `.md` files into `Note` models.
  ///
  /// - Parameter url: The file URL of the vault root directory.
  /// - Returns: A tuple of all discovered `Note` instances and the parsed `VaultConfig`.
  /// - Throws: `VaultError` if the path is not a directory or has no `.obsidian/` folder,
  ///           or if the scan encounters a fatal I/O error.
  func openVault(
    at url: URL,
    role: VaultRole? = nil
  ) async throws -> (notes: [Note], config: VaultConfig) {
    let vaultCfg = try prepareForObservation(at: url, role: role)
    // Scan all .md files — two-pass for speed
    // Pass 1: fast path collection (instant)
    let fileEntries = await Task.detached(priority: .userInitiated) { () -> [(url: URL, relative: String)] in
      var entries: [(url: URL, relative: String)] = []
      let keys: [URLResourceKey] = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .isUbiquitousItemKey,
        .ubiquitousItemDownloadingStatusKey,
      ]
      guard let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      ) else { return entries }
      while let fileURL = enumerator.nextObject() as? URL {
        guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
        guard let relative = VaultPath.relativePath(for: fileURL, in: url) else {
          if values.isDirectory == true { enumerator.skipDescendants() }
          continue
        }
        if relative == "Set Aside" || relative.hasPrefix("Set Aside/")
            || relative == "Trash" || relative.hasPrefix("Trash/") {
          if values.isDirectory == true {
            enumerator.skipDescendants()
          }
          continue
        }
        guard fileURL.pathExtension.lowercased() == "md" else { continue }
        // A vault inventory must not follow a symlink outside the selected
        // root or index an unavailable cloud placeholder as an empty note.
        guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
        if values.isUbiquitousItem == true,
           values.ubiquitousItemDownloadingStatus != .current {
          continue
        }
        entries.append((fileURL, relative))
      }
      return entries
    }.value

    // Separate cached (unchanged) from files needing re-parse
    var notes: [Note] = []
    let toReparse = fileEntries

    // Pass 2: parse only changed/new files in concurrent batches
    if !toReparse.isEmpty {
    let batchSize = 30
    for batchStart in stride(from: 0, to: toReparse.count, by: batchSize) {
      let batch = Array(toReparse[batchStart..<min(batchStart + batchSize, toReparse.count)])
      let parsed = await withTaskGroup(of: Note?.self) { group in
        for entry in batch {
          group.addTask {
            guard let data = try? Data(contentsOf: entry.url, options: [.mappedIfSafe]),
                  let content = NoteDocument.decodeUTF8PreservingBOM(data) else { return nil }
            let parsed: (frontmatter: [String: FrontmatterValue], body: String)
            do {
              parsed = try await MarkdownEngine().parse(content)
            } catch {
              // Keep malformed files visible and byte-preserved. Diagnostics are
              // handled by the trust-first document layer; never rewrite these.
              parsed = (frontmatter: [:], body: content)
            }
            let fm = parsed.frontmatter
            let resources = try? entry.url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let mtime = resources?.contentModificationDate ?? Date()
            return Note(
              relativePath: entry.relative,
              frontmatter: fm,
              body: parsed.body,
              rawContent: content,
              vaultRole: await self.currentVaultRole(),
              fileModifiedAt: mtime
            )
          }
        }
        var results: [Note] = []
        for await note in group {
          if let n = note { results.append(n) }
        }
        return results
      }
      notes.append(contentsOf: parsed)
    }
    }

    // Cache rebuilding will be reintroduced as metadata-only after the
    // correctness gate; it must never become writable document state.

    return (notes, vaultCfg)
  }

  // MARK: - Watch Vault (FSEvents)

  /// Begins watching the vault directory for file-system changes using FSEvents.
  ///
  /// Returns an `AsyncStream` that yields `(added, modified, deleted)` tuples of relative paths
  /// whenever `.md` files are added, modified, or removed inside the vault.
  ///
  /// - Note: The stream handles coalesced FSEvents — multiple changes in a short window are
  ///   batched into a single emission.
  /// - Returns: A stream of change batches that consumers iterate over with `for await`.
  func watchVault() -> AsyncStream<VaultWatchEvent> {
    AsyncStream { continuation in
      // A caller should stop the prior watcher before requesting another one,
      // but make replacement safe and idempotent at this boundary too.
      eventStreamLifecycle?.stopAndRelease()
      eventStreamLifecycle = nil
      watchContinuation?.finish()
      self.watchContinuation = continuation

      guard let root = vaultURL else {
        continuation.finish()
        return
      }

      let pathsToWatch = [root.path] as NSArray
      let callbackContext = FSEventCallbackContext(
        rootPath: root.path,
        continuation: continuation
      )
      var context = FSEventStreamContext(
        version: 0,
        info: Unmanaged.passUnretained(callbackContext).toOpaque(),
        retain: nil,
        release: nil,
        copyDescription: nil
      )

      let flags: FSEventStreamCreateFlags = FSEventStreamCreateFlags(
        kFSEventStreamCreateFlagUseCFTypes |
        kFSEventStreamCreateFlagFileEvents |
        kFSEventStreamCreateFlagNoDefer
      )

      guard let stream = FSEventStreamCreate(
        kCFAllocatorDefault,
        {(
          _ streamRef: ConstFSEventStreamRef,
          clientCallBackInfo: UnsafeMutableRawPointer?,
          numEvents: Int,
          eventPaths: UnsafeMutableRawPointer,
          eventFlags: UnsafePointer<FSEventStreamEventFlags>,
          _ eventIds: UnsafePointer<FSEventStreamEventId>
        ) in
          guard let clientCallBackInfo else { return }
          let callbackContext = Unmanaged<FSEventCallbackContext>
            .fromOpaque(clientCallBackInfo)
            .takeUnretainedValue()
          let paths = Unmanaged<NSArray>.fromOpaque(eventPaths).takeUnretainedValue()
          guard numEvents <= paths.count else { return }

          var added: [String] = []
          var modified: [String] = []
          var deleted: [String] = []
          var requiresFullRescan = false
          var rootChanged = false
          var latestEventID: UInt64 = 0

          for i in 0..<numEvents {
            guard let fullPath = paths[i] as? String else { continue }
            let flag = eventFlags[i]
            latestEventID = max(latestEventID, eventIds[i])
            requiresFullRescan = requiresFullRescan
              || (flag & UInt32(kFSEventStreamEventFlagMustScanSubDirs)) != 0
              || (flag & UInt32(kFSEventStreamEventFlagUserDropped)) != 0
              || (flag & UInt32(kFSEventStreamEventFlagKernelDropped)) != 0
              || (flag & UInt32(kFSEventStreamEventFlagEventIdsWrapped)) != 0
            rootChanged = rootChanged
              || (flag & UInt32(kFSEventStreamEventFlagRootChanged)) != 0
            guard let path = VaultPath.relativePath(
              for: URL(fileURLWithPath: fullPath),
              in: URL(fileURLWithPath: callbackContext.rootPath, isDirectory: true)
            ) else { continue }
            // Only track .md files
            guard path.lowercased().hasSuffix(".md") else { continue }

            let itemCreated      = (flag & UInt32(kFSEventStreamEventFlagItemCreated)) != 0
            let itemModified     = (flag & UInt32(kFSEventStreamEventFlagItemModified)) != 0
            let itemRemoved      = (flag & UInt32(kFSEventStreamEventFlagItemRemoved)) != 0
            let itemRenamed      = (flag & UInt32(kFSEventStreamEventFlagItemRenamed)) != 0
            let itemInodeMeta    = ((flag & UInt32(kFSEventStreamEventFlagItemChangeOwner)) != 0)
                          || ((flag & UInt32(kFSEventStreamEventFlagItemXattrMod)) != 0)

            // Heuristic: rename + no file at path = deleted (source of rename)
            // New file at path + created flag = added
            let stillExists = FileManager.default.fileExists(atPath: fullPath)

            if itemRemoved || (itemRenamed && !stillExists) {
              deleted.append(path)
            } else if itemCreated || (itemRenamed && stillExists) {
              added.append(path)
            } else if itemModified || itemInodeMeta {
              modified.append(path)
            }
          }

          if !added.isEmpty || !modified.isEmpty || !deleted.isEmpty || requiresFullRescan || rootChanged {
            callbackContext.continuation.yield(VaultWatchEvent(
              added: added,
              modified: modified,
              deleted: deleted,
              sequence: latestEventID,
              requiresFullRescan: requiresFullRescan,
              rootChanged: rootChanged
            ))
          }
        },
        &context,
        pathsToWatch,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        1.0, // latency in seconds — coalesce rapid changes
        flags
      ) else {
        continuation.finish()
        return
      }

      let lifecycle = FSEventStreamLifecycle(
        stream: stream,
        callbackContext: callbackContext
      )
      self.eventStreamLifecycle = lifecycle
      FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
      guard FSEventStreamStart(stream) else {
        lifecycle.stopAndRelease()
        self.eventStreamLifecycle = nil
        self.watchContinuation = nil
        continuation.finish()
        return
      }

      continuation.onTermination = { @Sendable _ in
        lifecycle.stopAndRelease()
      }
    }
  }

  // MARK: - File Info

  /// Returns the filesystem modification date and file size for a note.
  ///
  /// - Parameter relativePath: Vault-relative path.
  /// - Returns: `(modified: Date, size: Int)` tuple, or `nil` if the file doesn't exist.
  func fileInfo(at relativePath: String) -> (modified: Date, size: Int)? {
    guard let root = vaultURL else { return nil }
    let fullURL = root.appendingPathComponent(relativePath)
    guard let attrs = try? fm.attributesOfItem(atPath: fullURL.path) else { return nil }
    let modified = attrs[.modificationDate] as? Date ?? Date()
    let size = attrs[.size] as? Int ?? 0
    return (modified, size)
  }

  // MARK: - Stop Watching

  /// Stops the active FSEvents stream and finishes the watch `AsyncStream`.
  func stopWatching() {
    let lifecycle = eventStreamLifecycle
    eventStreamLifecycle = nil
    let continuation = watchContinuation
    watchContinuation = nil
    continuation?.finish()
    lifecycle?.stopAndRelease()
  }

  // MARK: - Rescan

  /// Performs a full re-scan of all `.md` files in the vault, re-parsing frontmatter.
  ///
  /// Useful after structural changes that FSEvents may not capture perfectly (e.g., bulk
  /// imports or changing `.obsidian/` configuration).
  ///
  /// - Returns: All `Note` instances discovered in the vault.
  func rescan() async throws -> [Note] {
    guard let url = vaultURL, let _ = config else {
      throw VaultError.notAnObsidianVault(URL(fileURLWithPath: "/dev/null"))
    }
    let result = try await openVault(at: url, role: vaultRole)
    return result.notes
  }

  func setVaultRole(_ role: VaultRole) {
    vaultRole = role
  }

  private func currentVaultRole() -> VaultRole {
    vaultRole
  }

  // MARK: - Private: .obsidian Config Parsing

  /// Parses Obsidian's `app.json` and related configuration from `.obsidian/`.
  private func parseObsidianConfig(at obsidianDir: URL) -> VaultConfig.ObsidianConfig {
    var cfg = VaultConfig.ObsidianConfig()

    // app.json — contains theme, showLineNumbers, defaultViewMode, etc.
    let appJSON = obsidianDir.appendingPathComponent("app.json")
    if let data = try? Data(contentsOf: appJSON),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      cfg.theme = json["theme"] as? String
      cfg.showLineNumbers = json["showLineNumber"] as? Bool
      cfg.defaultViewMode = json["defaultViewMode"] as? String

      // "attachmentFolderPath" — note the Obsidian spelling (missing 'h')
      cfg.attachmentFolderPath = json["attachmentFolderPath"] as? String
        ?? json["attachmentFolderPath"] as? String

      // "newLinkFormat"
      cfg.newLinkFormat = json["newLinkFormat"] as? String
    }

    // appearance.json (Obsidian 1.0+)
    let appearanceJSON = obsidianDir.appendingPathComponent("appearance.json")
    if let data = try? Data(contentsOf: appearanceJSON),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      if cfg.theme == nil { cfg.theme = json["theme"] as? String }
    }

    let coreJSON = obsidianDir.appendingPathComponent("core-plugins.json")
    if let data = try? Data(contentsOf: coreJSON),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      cfg.vaultName = json["vaultName"] as? String
    }

    return cfg
  }
}
