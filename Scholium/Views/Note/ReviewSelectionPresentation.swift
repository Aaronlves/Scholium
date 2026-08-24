/// Native-owned CSS for the Review selection paint installed by the generated
/// WebReader runtime. JavaScript behavior lives in WebEditor so it is built,
/// type-checked, and tested with the rest of the document web boundary.
enum ReviewSelectionPresentation {
    static let css = """
        html.scholium-review-custom-selection #scholium-document::selection,
        html.scholium-review-custom-selection #scholium-document ::selection {
          color: inherit;
          background-color: transparent;
        }
        ::highlight(scholium-review-selection) {
          background-color: color-mix(in srgb, var(--scholium-color-accent) 24%, transparent);
        }
    """
}
