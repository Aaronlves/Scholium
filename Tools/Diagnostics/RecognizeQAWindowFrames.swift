import AppKit
import Foundation
import Vision

// One line per captured frame: no recognized text is retained.
guard CommandLine.arguments.count == 3 else { fatalError("Requires a QA frames directory and synthetic body phrase") }
let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let build = repository.appendingPathComponent(".build").standardizedFileURL.resolvingSymlinksInPath()
let directory = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL.resolvingSymlinksInPath()
guard directory.path.hasPrefix(build.path + "/") else { fatalError("QA frame artifacts must be under repository .build") }
let summary = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("capture-summary.json"))) as! [String: Any]
guard summary["errors"] as? Int == 0, summary["overflow_frames"] as? Int == 0 else {
    fatalError("Capture errors or overflow invalidate frame analysis")
}
let phrase = CommandLine.arguments[2].lowercased().filter { $0.isLetter || $0.isNumber }
let lines = try String(contentsOf: directory.appendingPathComponent("frames.jsonl"), encoding: .utf8).split(separator: "\n")
var observations: [[String: Any]] = []
for line in lines {
    var value = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
    let filename = value["file"] as! String
    guard filename.range(of: #"^frame-[0-9]{5}\.png$"#, options: .regularExpression) != nil else {
        fatalError("Invalid QA frame filename")
    }
    let url = directory.appendingPathComponent(filename).resolvingSymlinksInPath()
    guard url.deletingLastPathComponent() == directory else { fatalError("QA frames cannot escape their capture directory") }
    let request = VNRecognizeTextRequest()
    request.recognitionLanguages = ["en-US"]
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    // Exclude Library/sidebar text. The sentinel occurs only in the body.
    request.regionOfInterest = CGRect(x: 0.25, y: 0, width: 0.75, height: 0.90)
    try VNImageRequestHandler(url: url).perform([request])
    let text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased().filter { $0.isLetter || $0.isNumber } ?? ""
    value["body_sentinel_visible"] = text.contains(phrase)
    observations.append(value)
}
try JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys]).write(
    to: directory.appendingPathComponent("recognized-frames.json"))
let matched = observations.filter { $0["body_sentinel_visible"] as? Bool == true }.count
print("frames=\(observations.count) matched=\(matched)")
