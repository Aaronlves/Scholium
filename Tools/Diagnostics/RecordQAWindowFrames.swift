import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import Darwin
import ScreenCaptureKit

// Diagnostic helper: captures only the explicitly identified QA process's window.
// The frame timestamp is the WindowServer display event, not screenshot return.
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let output: URL
    let context = CIContext(options: [.cacheIntermediates: false])
    let queue = DispatchQueue(label: "scholium.qa.frame-recorder")
    var index = 0
    var timebase = mach_timebase_info_data_t()
    var log: FileHandle!
    var frames: [(CVPixelBuffer, [String: Any])] = []
    var statuses: [Int: Int] = [:]
    var dropped = 0
    var errors = 0
    init(output: URL) throws {
        self.output = output
        super.init()
        mach_timebase_info(&timebase)
        // The caller creates only the parent; exclusive mkdir rejects stale
        // contents and leaf symlinks before writing any capture artifact.
        guard mkdir(output.path, 0o700) == 0 else { throw CocoaError(.fileWriteFileExists) }
        let file = output.appendingPathComponent("frames.jsonl")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        log = try FileHandle(forWritingTo: file)
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
            let metadata = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let frame = metadata.first,
            let status = frame[.status] as? Int
        else {
            errors += 1
            return
        }
        statuses[status, default: 0] += 1
        guard status == SCFrameStatus.complete.rawValue else { return }
        guard
            let ticks = (frame[.displayTime] as? NSNumber)?.uint64Value,
            let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            errors += 1
            return
        }
        guard frames.count < 128 else {
            dropped += 1
            return
        }
        let received = DispatchTime.now().uptimeNanoseconds
        let nanoseconds = ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
        let file = String(format: "frame-%05d.png", index)
        // Release the stream's surface immediately. PNG conversion and disk
        // writes run only after capture stops, outside the measured action.
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        var copy: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &copy) == kCVReturnSuccess,
            let copy
        else {
            errors += 1
            return
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(copy, [])
        }
        guard let source = CVPixelBufferGetBaseAddress(buffer), let destination = CVPixelBufferGetBaseAddress(copy) else {
            errors += 1
            return
        }
        let sourceRow = CVPixelBufferGetBytesPerRow(buffer)
        let destinationRow = CVPixelBufferGetBytesPerRow(copy)
        for row in 0..<height { memcpy(destination + row * destinationRow, source + row * sourceRow, width * 4) }
        let value: [String: Any] = [
            "frame": index, "file": file, "display_uptime_ns": nanoseconds,
            "received_uptime_ns": received, "copy_finished_uptime_ns": DispatchTime.now().uptimeNanoseconds,
            "width": width, "height": height,
        ]
        frames.append((copy, value))
        index += 1
        if index == 1 { do { try Data("ready".utf8).write(to: output.appendingPathComponent("ready")) } catch { errors += 1 } }
    }
    func finish() throws {
        for (buffer, value) in frames {
            let image = CIImage(cvPixelBuffer: buffer)
            let file = value["file"] as! String
            try context.writePNGRepresentation(
                of: image, to: output.appendingPathComponent(file), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            data.append(10)
            try log.write(contentsOf: data)
        }
        let summary: [String: Any] = [
            "captured_frames": frames.count, "frame_capacity": 128,
            "overflow_frames": dropped, "errors": errors, "statuses": Dictionary(uniqueKeysWithValues: statuses.map { (String($0.key), $0.value) }),
            "encoding": "PNG encoded after capture stopped; callbacks only copy pixels into bounded memory",
        ]
        do {
            try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]).write(
                to: output.appendingPathComponent("capture-summary.json"))
            try log.close()
        } catch { throw error }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { self.errors += 1 }
    }
}

@main struct Main {
    static func main() async throws {
        let args = CommandLine.arguments
        guard CGPreflightScreenCaptureAccess() else {
            fputs("screen_capture_access=false\n", stderr)
            exit(77)
        }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let qaRoot = repository.appendingPathComponent(".build/qa-runtime").standardizedFileURL.resolvingSymlinksInPath().path
        guard args.count == 5, args[1] == "--pid", let pid = Int32(args[2]), args[3] == "--output",
            let application = NSRunningApplication(processIdentifier: pid), application.bundleIdentifier == "com.scholium.qa",
            let executable = application.executableURL?.standardizedFileURL.resolvingSymlinksInPath().path,
            [qaRoot + "/Scholium-QA.app/Contents/MacOS/Scholium", qaRoot + "/registered/Scholium-Codex-QA-Do-Not-Use.app/Contents/MacOS/Scholium"].contains(
                executable)
        else { fatalError("Requires a running QA PID, output directory, and existing screen capture access") }
        let output = URL(fileURLWithPath: args[4]).standardizedFileURL.resolvingSymlinksInPath()
        guard output.path.hasPrefix(repository.appendingPathComponent(".build").standardizedFileURL.resolvingSymlinksInPath().path + "/"),
            !FileManager.default.fileExists(atPath: output.appendingPathComponent("frames.jsonl").path)
        else { fatalError("Requires a fresh output under repository .build") }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard
            let window = content.windows.filter({ $0.owningApplication?.processID == pid && $0.frame.width >= 700 && $0.frame.height >= 400 }).max(by: {
                $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
            })
        else {
            fatalError("QA window unavailable")
        }
        let recorder = try Recorder(output: output)
        let frameRate = Int(ProcessInfo.processInfo.environment["SCHOLIUM_QA_FRAME_RATE"] ?? "60") ?? 0
        guard [15, 60].contains(frameRate) else { fatalError("QA frame rate must be 15 or 60") }
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width)
        config.height = Int(window.frame.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(frameRate))
        config.queueDepth = 5
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        config.captureResolution = .nominal
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: recorder)
        try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: recorder.queue)
        try await stream.startCapture()
        let identity: [String: Any] = [
            "pid": pid, "window_id": window.windowID, "width": config.width, "height": config.height,
            "clock": "SCStreamFrameInfo.displayTime mach_absolute_time converted with mach_timebase_info to uptime nanoseconds",
            "requested_interval_ms": 1000.0 / Double(frameRate),
        ]
        try JSONSerialization.data(withJSONObject: identity, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("identity.json"))
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        let stopped = DispatchSemaphore(value: 0)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        term.setEventHandler { stopped.signal() }
        interrupt.setEventHandler { stopped.signal() }
        term.resume()
        interrupt.resume()
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                _ = stopped.wait(timeout: .now() + 45)
                continuation.resume()
            }
        }
        do { try await stream.stopCapture() } catch { recorder.queue.sync { recorder.errors += 1 } }
        try recorder.queue.sync { try recorder.finish() }
        term.cancel()
        interrupt.cancel()
    }
}
