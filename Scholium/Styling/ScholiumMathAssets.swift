import Foundation

enum ScholiumMathAssets {
    static let runtimeJavaScript: String = loadTextResource("math.bundle", extension: "js")

    static let css: String = {
        let bundled = loadTextResource("katex.min", extension: "css")
        guard !bundled.isEmpty,
              let expression = try? NSRegularExpression(
                pattern: #"src:url\(fonts/(KaTeX_[A-Za-z0-9_-]+)\.woff2\)[^}]+"#
              ) else { return presentationCSS }

        let mutable = NSMutableString(string: bundled)
        let matches = expression.matches(
            in: bundled,
            range: NSRange(location: 0, length: mutable.length)
        )
        for match in matches.reversed() {
            let fontName = (bundled as NSString).substring(with: match.range(at: 1))
            guard let url = Bundle.module.url(forResource: fontName, withExtension: "woff2"),
                  let data = try? Data(contentsOf: url) else { continue }
            mutable.replaceCharacters(
                in: match.range,
                with: "src:url(\"data:font/woff2;base64,\(data.base64EncodedString())\") format(\"woff2\")"
            )
        }
        return (mutable as String) + "\n" + presentationCSS
    }()

    private static let presentationCSS = """
    .scholium-math {
      color: inherit;
      max-inline-size: 100%;
    }
    .scholium-math-inline { display: inline; }
    .scholium-document,
    .cm-editor.scholium-live-mode .cm-content {
      counter-reset: scholium-equation;
    }
    .scholium-math-display {
      display: grid;
      grid-template-columns: minmax(2.5em, 1fr) max-content minmax(2.5em, 1fr);
      align-items: baseline;
      overflow-x: auto;
      overflow-y: hidden;
      margin-block: var(--scholium-rhythm-paragraph-gap);
      padding-block: 0.12em;
      direction: ltr;
      counter-increment: scholium-equation;
      scrollbar-width: thin;
    }
    .scholium-math-display > .scholium-math-output,
    .scholium-math-display > .katex-display {
      grid-column: 2;
      min-inline-size: max-content;
      margin: 0;
      justify-self: center;
    }
    .scholium-math-display > .scholium-math-source {
      grid-column: 2;
      min-inline-size: 0;
      margin: 0;
      justify-self: center;
    }
    .scholium-math-display::after {
      grid-column: 3;
      justify-self: end;
      align-self: baseline;
      content: "(" counter(scholium-equation) ")";
      font: normal 0.82em/1 Alegreya, Georgia, serif;
      font-variant-numeric: tabular-nums;
    }
    .scholium-math-display .katex { font-style: italic; }
    .scholium-math-display .katex .mop,
    .scholium-math-display .katex .mbin,
    .scholium-math-display .katex .mrel,
    .scholium-math-display .katex .mopen,
    .scholium-math-display .katex .mclose,
    .scholium-math-display .katex .mpunct { font-style: normal; }
    .cm-live-math.scholium-math-display { inline-size: 100%; }
    .cm-live-math-slot {
      box-sizing: border-box;
      inline-size: 100%;
      pointer-events: none;
    }
    .cm-live-math-slot > .scholium-math-display {
      margin-block: 0;
      pointer-events: auto;
    }
    .scholium-math-source {
      font-family: "Victor Mono", ui-monospace, "SFMono-Regular", Menlo, monospace;
      font-size: 0.92em;
      white-space: pre-wrap;
      overflow-wrap: anywhere;
    }
    .scholium-math-rendered > .scholium-math-source { display: none; }
    .scholium-math-error {
      text-decoration-line: underline;
      text-decoration-style: wavy;
      text-decoration-color: var(--scholium-color-destructive);
      text-decoration-thickness: max(1px, 0.07em);
      text-underline-offset: 0.16em;
    }
    @media (forced-colors: active) {
      .scholium-math-error { text-decoration-color: CanvasText; }
    }
    """

    private static func loadTextResource(_ name: String, extension fileExtension: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: fileExtension),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return source
    }
}
