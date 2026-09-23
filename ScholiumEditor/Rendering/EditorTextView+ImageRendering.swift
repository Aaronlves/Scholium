// Modified by Scholium; upstream attribution: ThirdParty/Edmund/NOTICE.md.
import AppKit

/// Image destinations remain source text. Rendering cannot grant file or network access.
enum ImageLoadFailure: Equatable {
    case blockedBySetting
    case embedTypeUnsupported
    var label: String {
        switch self {
        case .blockedBySetting: return "External images blocked"
        case .embedTypeUnsupported: return "Embedded file preview unavailable"
        }
    }
}

extension EditorTextView {
    func imageOverlay(destination: String, width: Int? = nil, height: Int? = nil) -> FragmentOverlay? {
        placeholderOverlay(failure: .blockedBySetting)
    }

    func embedOverlay(destination: String) -> FragmentOverlay? {
        placeholderOverlay(failure: .embedTypeUnsupported, icon: "file-x")
    }

    private func placeholderOverlay(failure: ImageLoadFailure, icon iconName: String = "image-off") -> FragmentOverlay? {
        let pointSize = bodyFont.pointSize
        guard let icon = LucideIcons.image(iconName, color: .secondaryLabelColor, pointSize: pointSize)
        else { return nil }

        let labelAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: NSColor.secondaryLabelColor]
        let label = NSAttributedString(string: failure.label, attributes: labelAttrs)
        let labelSize = label.size()

        let gap = pointSize * 0.3
        let iconW = icon.size.width
        let iconH = icon.size.height
        let height = ceil(max(iconH, labelSize.height))
        let width = ceil(iconW + gap + labelSize.width)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            icon.draw(in: NSRect(x: 0, y: (height - iconH) / 2, width: iconW, height: iconH))
            label.draw(at: NSPoint(x: iconW + gap, y: (height - labelSize.height) / 2))
            return true
        }
        image.cacheMode = .never  // re-rasterize at the screen's backing scale, like the callout header

        return FragmentOverlay(image: image, bounds: CGRect(x: 0, y: 0, width: width, height: height))
    }
}
