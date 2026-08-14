import Foundation

enum ScholiumWebFonts {
    static let css: String = {
        [
            fontFace(family: "Alegreya", resource: "Alegreya-Regular", weight: "400", style: "normal"),
            fontFace(family: "Alegreya", resource: "Alegreya-Italic", weight: "400", style: "italic"),
            fontFace(family: "Alegreya", resource: "Alegreya-Bold", weight: "700", style: "normal"),
            fontFace(family: "Alegreya", resource: "Alegreya-BoldItalic", weight: "700", style: "italic"),
            fontFace(family: "Victor Mono", resource: "VictorMono-Regular", weight: "400", style: "normal"),
            fontFace(family: "Victor Mono", resource: "VictorMono-Italic", weight: "400", style: "italic"),
            fontFace(family: "Victor Mono", resource: "VictorMono-Bold", weight: "700", style: "normal"),
        ].joined(separator: "\n")
    }()

    private static func fontFace(
        family: String,
        resource: String,
        weight: String,
        style: String
    ) -> String {
        return """
        @font-face {
          font-family: "\(family)";
          src: url("\(ScholiumWebFontResources.url(for: resource + ".ttf"))") format("truetype");
          font-weight: \(weight);
          font-style: \(style);
          font-display: swap;
        }
        """
    }
}
