import AppKit
import Foundation

// Diagnostic only: a mode indicator must match its settled captured state and
// the document body must match the settled captured body in the same frame.
// This is a WindowServer pixel endpoint, never physical panel scanout or AX timing.
let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let build = repository.appendingPathComponent(".build").standardizedFileURL.resolvingSymlinksInPath()
guard CommandLine.arguments.count == 2 else { fatalError("Requires one synthetic QA mode observation directory") }
let directory = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL.resolvingSymlinksInPath()
guard directory.path.hasPrefix(build.path + "/") else { fatalError("QA observations must be under repository .build") }
let observation = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("observations.json"))) as! [String: Any]
guard observation["kind"] as? String == "mode_switch",
    let started = (observation["driver_action_start_uptime_ns"] as? NSNumber)?.uint64Value,
    let passiveEnd = (observation["passive_interval_end_uptime_ns"] as? NSNumber)?.uint64Value
else { fatalError("Invalid mode observation") }
let framesDirectory = directory.appendingPathComponent("frames")
let summary = try JSONSerialization.jsonObject(with: Data(contentsOf: framesDirectory.appendingPathComponent("capture-summary.json"))) as! [String: Any]
guard summary["errors"] as? Int == 0, summary["overflow_frames"] as? Int == 0 else {
    fatalError("Capture errors or overflow invalidate mode analysis")
}
let lines = try String(contentsOf: framesDirectory.appendingPathComponent("frames.jsonl"), encoding: .utf8).split(separator: "\n")
let frames = try lines.map { line in
    try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
}.filter { (($0["display_uptime_ns"] as! NSNumber).uint64Value) < passiveEnd }
guard let before = frames.last(where: { ($0["display_uptime_ns"] as! NSNumber).uint64Value <= started }),
    let settled = frames.last, (settled["display_uptime_ns"] as! NSNumber).uint64Value > started
else { fatalError("Mode comparison requires pre-action and settled passive frames") }

func image(_ frame: [String: Any]) throws -> CGImage {
    let name = frame["file"] as! String
    guard name.range(of: #"^frame-[0-9]{5}\.png$"#, options: .regularExpression) != nil else {
        fatalError("Invalid QA frame filename")
    }
    let url = framesDirectory.appendingPathComponent(name).resolvingSymlinksInPath()
    guard url.deletingLastPathComponent() == framesDirectory,
        let bitmap = NSBitmapImageRep(data: try Data(contentsOf: url)), let image = bitmap.cgImage
    else { fatalError("Invalid QA frame pixels") }
    return image
}

struct Pixels {
    let bytes: [UInt8]
    let width: Int
    let height: Int
}

func crop(_ image: CGImage, key: String) -> Pixels {
    guard let value = observation[key] as? [String: Double],
        let x = value["x"], let y = value["y"], let width = value["width"], let height = value["height"],
        [x, y, width, height].allSatisfy({ $0.isFinite }),
        x >= 0, y >= 0, width > 0, height > 0, x + width <= 1.001, y + height <= 1.001
    else { fatalError("Invalid normalized QA crop") }
    let rect = CGRect(
        x: x * Double(image.width), y: y * Double(image.height),
        width: width * Double(image.width), height: height * Double(image.height)
    ).integral
    guard let cropped = image.cropping(to: rect), cropped.width > 1, cropped.height > 1 else {
        fatalError("Empty QA crop")
    }
    var bytes = [UInt8](repeating: 0, count: cropped.width * cropped.height * 4)
    let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress, width: cropped.width, height: cropped.height,
            bitsPerComponent: 8, bytesPerRow: cropped.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
    }
    return Pixels(bytes: bytes, width: cropped.width, height: cropped.height)
}

func pixelDifference(_ left: Pixels, _ right: Pixels, _ offset: Int) -> Int {
    (0..<3).map { abs(Int(left.bytes[offset + $0]) - Int(right.bytes[offset + $0])) }.max()!
}

func mask(_ initial: Pixels, _ reference: Pixels, stride: Int) -> (offsets: [Int], changed: Int) {
    guard initial.width == reference.width, initial.height == reference.height else { fatalError("QA frame size changed") }
    var offsets: [Int] = []
    var changed = 0
    for y in Swift.stride(from: 0, to: reference.height - 1, by: stride) {
        for x in Swift.stride(from: 0, to: reference.width - 1, by: stride) {
            let offset = (y * reference.width + x) * 4
            let isChanged = pixelDifference(initial, reference, offset) >= 18
            if isChanged { changed += 1 }
            let neighbors = [offset + 4, offset + reference.width * 4]
            let edge = neighbors.contains { next in
                (0..<3).contains { abs(Int(reference.bytes[offset + $0]) - Int(reference.bytes[next + $0])) >= 18 }
            }
            if isChanged || edge { offsets.append(offset) }
        }
    }
    return (offsets, changed)
}

func compare(_ candidate: Pixels, _ reference: Pixels, offsets: [Int]) -> (mean: Double, fraction: Double) {
    guard candidate.width == reference.width, candidate.height == reference.height, !offsets.isEmpty else {
        fatalError("Mode/body reference has no discriminating pixels")
    }
    var total = 0
    var different = 0
    for offset in offsets {
        let error = pixelDifference(candidate, reference, offset)
        total += error
        if error > 32 { different += 1 }
    }
    return (Double(total) / Double(offsets.count), Double(different) / Double(offsets.count))
}

let beforeImage = try image(before)
let referenceImage = try image(settled)
let modeKey = "mode_control_crop_top_left_normalized"
let bodyKey = "body_crop_top_left_normalized"
let modeReference = crop(referenceImage, key: modeKey)
let bodyReference = crop(referenceImage, key: bodyKey)
let modeMask = mask(crop(beforeImage, key: modeKey), modeReference, stride: 1)
let bodyMask = mask(crop(beforeImage, key: bodyKey), bodyReference, stride: 2)
guard modeMask.changed >= 5, modeMask.offsets.count >= 10, bodyMask.offsets.count >= 500 else {
    fatalError("Mode indicator or body reference is insufficiently discriminating")
}
var observations: [[String: Any]] = []
for frame in frames {
    let current = try image(frame)
    let mode = compare(crop(current, key: modeKey), modeReference, offsets: modeMask.offsets)
    let body = compare(crop(current, key: bodyKey), bodyReference, offsets: bodyMask.offsets)
    var result = frame
    result["mode_mean_max_rgb_error"] = mode.mean
    result["mode_fraction_error_above_32"] = mode.fraction
    result["body_mean_max_rgb_error"] = body.mean
    result["body_fraction_error_above_32"] = body.fraction
    result["mode_and_body_match"] = mode.mean <= 8 && mode.fraction <= 0.05 && body.mean <= 8 && body.fraction <= 0.05
    observations.append(result)
}
guard
    !observations.contains(where: {
        ($0["display_uptime_ns"] as! NSNumber).uint64Value <= started && $0["mode_and_body_match"] as? Bool == true
    }), let firstIndex = observations.firstIndex(where: { $0["mode_and_body_match"] as? Bool == true }), firstIndex > 0
else {
    fatalError("Mode endpoint lacks an unmatched pre-action frame")
}
let first = observations[firstIndex]
let previous = observations[firstIndex - 1]
let firstTime = (first["display_uptime_ns"] as! NSNumber).uint64Value
let previousTime = (previous["display_uptime_ns"] as! NSNumber).uint64Value
let output: [String: Any] = [
    "schema": 1, "kind": "mode_switch", "origin": observation["origin"]!, "mode": observation["mode"]!,
    "endpoint": "first WindowServer frame matching settled mode indicator and document body",
    "display_observed_ms": Double(firstTime - started) / 1_000_000,
    "previous_unmatched_ms": (Double(previousTime) - Double(started)) / 1_000_000,
    "boundary_gap_ms": Double(firstTime - previousTime) / 1_000_000,
    "mode_changed_sampled_pixels": modeMask.changed,
    "body_changed_sampled_pixels": bodyMask.changed,
    "body_has_discriminating_visual_change": bodyMask.changed >= 100,
    "mode_mask_pixels": modeMask.offsets.count, "body_mask_pixels": bodyMask.offsets.count,
    "thresholds": ["maximum_mean_max_rgb_error": 8, "maximum_fraction_error_above_32": 0.05],
    "first_matching_frame": first["file"]!, "preceding_unmatched_frame": previous["file"]!,
    "settled_reference_frame": settled["file"]!, "frames": observations,
]
try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
    .write(to: directory.appendingPathComponent("mode-frame-comparison.json"))
print("mode=\(observation["origin"]!)->\(observation["mode"]!) frames=\(frames.count) body_changed=\(bodyMask.changed)")
