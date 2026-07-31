#if DEBUG
import AppKit
import Foundation
import WebKit

@MainActor
extension MarkdownEditorSession {
    struct TestingPresentationSnapshot: Decodable, Sendable {
        let rootContentTopInset: String
        let rootTextScale: String
        let rootProseLineHeight: String
        let rootParagraphGap: String
        let rootHeadingLineHeight: String
        let rootInlineRegular: String
        let rootInlineSource: String
        let rootInlineNarrow: String
        let rootLineWidth: String
        let viewportWidth: Double
        let pageColor: String
        let pageBackgroundColor: String
        let documentFontFamily: String
        let documentFontSize: String
        let documentLineHeight: String
        let documentMaxWidth: String
        let documentPaddingTop: String
        let documentPaddingInlineStart: String
        let documentWidth: Double
        let documentLeft: Double
        let documentRight: Double
        let firstGlyphLeft: Double
        let pageHorizontalOverflow: Double
        let latinGlyphsPerLine: Int
        let cjkGlyphsPerLine: Int
        let headingFontFamily: String
        let headingFontSize: String
        let headingFontWeight: String
        let headingLineHeight: String
        let headingBlockBefore: Double
        let headingBlockAfter: Double
        let headingWidth: Double
        let headingTextDecorationLine: String
        let titleTextDecorationLine: String
        let titleBorderBottomWidth: String
        let titleWidth: Double
        let calloutAccent: String
        let calloutBorderColor: String
        let calloutFontSize: String
        let calloutLineHeight: String
        let calloutWidth: Double
        let calloutRoleColor: String
        let calloutRolePosition: String
        let calloutRoleWidth: Double
        let calloutRoleHeight: Double
        let calloutRoleFontFamily: String
        let calloutRoleFontSize: String
        let calloutRoleFontWeight: String
        let calloutRoleLineHeight: String
        let calloutRoleLetterSpacing: String
        let calloutRoleTextTransform: String
        let calloutTitleColor: String
        let calloutTitleFontFamily: String
        let calloutTitleFontSize: String
        let calloutTitleFontWeight: String
        let calloutTitleLineHeight: String
        let calloutTitleLetterSpacing: String
        let calloutTitleTextTransform: String
        let orientationTextAlign: String
        let tableOverflowX: String
        let tableWidth: Double
        let tableCellFontFamily: String
        let tableCellFontSize: String
        let tableCellLineHeight: String
        let tableCellPaddingBlockStart: String
        let tableCellPaddingInlineStart: String
        let tableCellBorderBottomWidth: String
        let tableCellBorderBottomColor: String
        let mathOverflowX: String
        let mathColor: String
        let mathFontSize: String
        let mathLineHeight: String
        let mathMarginBlockStart: String
        let mathPaddingBlockStart: String
        let mathWidth: Double
        let mathScrollExtent: Double
        let mathOutputWidth: Double
        let mathOutputInternalOverflow: Double
        let mathStartClipping: Double
        let mathEndClipping: Double
        let mathMiddleTrackWidth: Double
        let mathRightTrackWidth: Double
    }

    struct TestingAccessibilitySnapshot: Decodable, Sendable {
        let contentEditableCount: Int
        let textboxCount: Int
        let label: String
        let multiline: String
        let hasValueText: Bool
        let spellcheck: String
        let isFocused: Bool
        let liveModeClassCount: Int
        let sourceModeClassCount: Int
        let selectionMatchCount: Int
        let matchingBracketCount: Int
        let sourceSemanticTypographyCount: Int
        let liveProjectionDOMCount: Int
        let selectionActionsCount: Int
        let previewPopoverCount: Int
        let gutterCount: Int
        let lineNumberCount: Int
        let activeLineCount: Int
        let liveTitleCount: Int
        let liveH1Count: Int
        let liveH2Count: Int
        let h1FontSize: String
        let h2FontSize: String
        let titleTextAlign: String
        let h2TextAlign: String
        let collapsedCodeFenceLineCount: Int
        let collapsedCodeFenceVisibleHeight: Double
        let editBlankLineCount: Int
        let editBlankLineMinimumHeight: Double
        let semanticGapCount: Int
        let liveListMarkerCount: Int
        let liveListMarkerUsesPrimaryText: Bool
        let liveListMarkerText: String
        let liveListMarkerTextGap: Double
        let liveTaskSourceTokenCount: Int
        let quotePaddingInlineStart: String
        let quoteMarginInlineStart: String
        let visibleLineClassSummary: String
        let contentPaddingTop: String
        let contentPaddingInlineStart: String
        let lineWrappingEnabled: Bool
        let softWrapProbeHeight: Double
        let scrollTop: Double
        let scrollExtent: Double
        let mathRuntimeVersion: Int
        let renderedMathCount: Int
        let mathErrorCount: Int
        let displayMathOverflowX: String
        let previewAnchorCount: Int
        let previewPopoverHidden: Bool
        let previewTitle: String
        let previewNestedListCount: Int
        let previewBlockquoteCount: Int
        let previewCodeBlockCount: Int
        let previewCalloutCount: Int
        let previewTableCount: Int
        let previewRenderedMathCount: Int
        let frontmatterLineCount: Int
        let frontmatterVisibleHeight: Double
        let unclosedFrontmatterNoticeCount: Int
        let semanticTableCount: Int
        let liveTableSourceLineCount: Int
        let tableHeaderCount: Int
        let tableBodyCellCount: Int
        let tableStrongCount: Int
        let tableFirstHeaderText: String
        let tableOverflowX: String
        let footnoteReferenceCount: Int
        let footnoteDefinitionSourceCount: Int
        let liveCalloutWidgetCount: Int
        let liveCalloutSourceLineCount: Int
        let liveRawHTMLWidgetCount: Int
        let liveRawHTMLSourceLineCount: Int
        let exactWikilinkSourceCount: Int
        let incompleteWikilinkSourceCount: Int
        let exactCalloutSourceCount: Int
        let activeLiveBlockKind: String
        let presentation: TestingPresentationSnapshot
    }

    struct TestingInlineProjectionSnapshot: Decodable, Sendable {
        let lineText: String
        let strongTexts: [String]
        let strongWeights: [String]
        let emphasisTexts: [String]
        let emphasisStyles: [String]
        let strikethroughTexts: [String]
        let highlightTexts: [String]
        let highlightBackgrounds: [String]
        let highlightColors: [String]
        let codeTexts: [String]
        let linkTexts: [String]
        let wikiLinkTexts: [String]
    }

    struct TestingCalloutProjectionSnapshot: Decodable, Sendable {
        let sourceLineText: String
        let renderedLinkTexts: [String]
        let renderedLinkTargets: [String]
    }

    struct TestingPointerProjectionResult: Sendable {
        let duringDragLineText: String
        let afterMouseUpLineText: String
    }

    struct TestingEditorSelectionPresentationSnapshot: Decodable, Sendable {
        let selectedTexts: [String]
        let selectedRunCount: Int
        let selectedBlankLineRunCount: Int
        let stockRectangleCount: Int
        let nativeSelectionBackground: String
        let selectedBackgroundsMatchAccent: Bool
    }

    @discardableResult
    func testingSimulateWebContentProcessTermination() -> Bool {
        guard let webView,
              let coordinator = webView.navigationDelegate as? MarkdownEditorWebView.Coordinator else {
            return false
        }
        coordinator.webViewWebContentProcessDidTerminate(webView)
        return true
    }

    func testingAccessibilitySnapshot() async throws -> TestingAccessibilitySnapshot {
        guard let webView else { throw SessionError.unavailable }
        let rawResult = try await webView.callAsyncJavaScript(
            """
            const editable = document.querySelectorAll('[contenteditable="true"]');
            const textboxes = document.querySelectorAll('[role="textbox"]');
            const content = editable[0];
            const contentStyle = content ? getComputedStyle(content) : null;
            const rootStyle = getComputedStyle(document.documentElement);
            const px = value => Number.parseFloat(value || '0') || 0;
            const style = selector => {
                const element = document.querySelector(selector);
                return element ? getComputedStyle(element) : null;
            };
            const width = selector => document.querySelector(selector)?.getBoundingClientRect().width || 0;
            const bounds = selector => document.querySelector(selector)?.getBoundingClientRect() || {left: 0, right: 0};
            const firstGlyphLeft = selector => {
                const element = document.querySelector(selector);
                if (!element) return 0;
                const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
                let node;
                while ((node = walker.nextNode())) {
                    if (!node.textContent?.trim()) continue;
                    if (node.parentElement?.closest('.cm-widgetBuffer')) continue;
                    const offset = node.textContent.search(/\\S/);
                    const range = document.createRange();
                    range.setStart(node, Math.max(0, offset));
                    range.setEnd(node, Math.max(0, offset) + 1);
                    return range.getBoundingClientRect().left;
                }
                return 0;
            };
            const maximumGlyphsOnLine = marker => {
                const element = Array.from(document.querySelectorAll('.cm-line'))
                    .find(candidate => candidate.textContent?.includes(marker));
                if (!element) return 0;
                const counts = new Map();
                const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
                let node;
                while ((node = walker.nextNode())) {
                    let offset = 0;
                    for (const glyph of Array.from(node.textContent || '')) {
                        const nextOffset = offset + glyph.length;
                        if (!/[\\r\\n]/u.test(glyph)) {
                            const range = document.createRange();
                            range.setStart(node, offset);
                            range.setEnd(node, nextOffset);
                            const rect = range.getClientRects()[0];
                            if (rect) {
                                const line = Math.round(rect.top * 2) / 2;
                                counts.set(line, (counts.get(line) || 0) + 1);
                            }
                        }
                        offset = nextOffset;
                    }
                }
                return Math.max(0, ...counts.values());
            };
            const textStyle = selector => {
                const element = document.querySelector(selector);
                if (!element) return null;
                const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
                let node;
                while ((node = walker.nextNode())) {
                    if (node.textContent?.trim()) return getComputedStyle(node.parentElement || element);
                }
                return getComputedStyle(element);
            };
            const headingBlockStyle = style('.cm-live-h2');
            const headingStyle = textStyle('.cm-live-h2');
            const titleBlockStyle = style('.cm-live-document-title');
            const titleRuleStyle = (() => {
                const element = document.querySelector('.cm-live-document-title');
                return element ? getComputedStyle(element, '::after') : null;
            })();
            const titleStyle = textStyle('.cm-live-document-title');
            const calloutStyle = style('.cm-live-callout-widget.scholium-callout-state');
            const calloutRoleStyle = style('.cm-live-callout-widget.scholium-callout-state .scholium-callout-role');
            const calloutTitleStyle = style('.cm-live-callout-widget.scholium-callout-state .scholium-callout-title');
            const orientationStyle = style('.cm-live-callout-widget.scholium-callout-orient .scholium-callout-body');
            const tableStyle = style('.cm-live-table-widget');
            const tableCellStyle = style('.cm-live-table-widget th');
            const mathStyle = style('.cm-live-math.scholium-math-display');
            const mathGeometry = (() => {
                const display = document.querySelector('.cm-live-math.scholium-math-display');
                const output = display?.querySelector(':scope > .katex-display, :scope > .scholium-math-output');
                if (!display || !output) return {
                    scrollExtent: 0,
                    outputWidth: 0,
                    outputInternalOverflow: 0,
                    startClipping: 0,
                    endClipping: 0,
                    middleTrackWidth: 0,
                    rightTrackWidth: 0,
                };
                const originalScrollLeft = display.scrollLeft;
                const displayBounds = display.getBoundingClientRect();
                display.scrollLeft = 0;
                const startBounds = output.getBoundingClientRect();
                display.scrollLeft = display.scrollWidth;
                const endBounds = output.getBoundingClientRect();
                display.scrollLeft = originalScrollLeft;
                const tracks = getComputedStyle(display).gridTemplateColumns
                    .split(/\\s+/)
                    .map(value => Number.parseFloat(value))
                    .filter(value => Number.isFinite(value));
                return {
                    scrollExtent: Math.max(0, display.scrollWidth - display.clientWidth),
                    outputWidth: output.getBoundingClientRect().width,
                    outputInternalOverflow: Math.max(0, output.scrollWidth - output.clientWidth),
                    startClipping: Math.max(0, displayBounds.left - startBounds.left),
                    endClipping: Math.max(0, endBounds.right - displayBounds.right),
                    middleTrackWidth: tracks[1] || 0,
                    rightTrackWidth: tracks[2] || 0,
                };
            })();
            return {
                contentEditableCount: editable.length,
                textboxCount: textboxes.length,
                label: content?.getAttribute('aria-label') || '',
                multiline: content?.getAttribute('aria-multiline') || '',
                hasValueText: content?.hasAttribute('aria-valuetext') || false,
                spellcheck: content?.getAttribute('spellcheck') || '',
                isFocused: document.activeElement === content,
                liveModeClassCount: document.querySelectorAll('.cm-editor.scholium-live-mode').length,
                sourceModeClassCount: document.querySelectorAll('.cm-editor.scholium-source-mode').length,
                selectionMatchCount: document.querySelectorAll('.cm-selectionMatch, .cm-selectionMatch-main').length,
                matchingBracketCount: document.querySelectorAll('.cm-matchingBracket, .cm-nonmatchingBracket').length,
                sourceSemanticTypographyCount: Array.from(
                    document.querySelectorAll('.cm-editor.scholium-source-mode .cm-content span')
                ).filter(element => {
                    const computed = getComputedStyle(element);
                    const weight = Number.parseInt(computed.fontWeight, 10) || 400;
                    return weight >= 600
                        || computed.fontStyle === 'italic'
                        || computed.textDecorationLine.includes('line-through')
                        || computed.textDecorationLine.includes('underline');
                }).length,
                liveProjectionDOMCount: document.querySelectorAll('[class*="cm-live-"]').length,
                selectionActionsCount: document.querySelectorAll('#scholium-selection-actions').length,
                previewPopoverCount: document.querySelectorAll('#scholium-preview-popover').length,
                gutterCount: document.querySelectorAll('.cm-gutters').length,
                lineNumberCount: document.querySelectorAll('.cm-lineNumbers .cm-gutterElement').length,
                activeLineCount: document.querySelectorAll('.cm-activeLine').length,
                liveTitleCount: document.querySelectorAll('.cm-live-document-title').length,
                liveH1Count: document.querySelectorAll('.cm-live-h1').length,
                liveH2Count: document.querySelectorAll('.cm-live-h2').length,
                h1FontSize: style('.cm-live-h1')?.fontSize || '',
                h2FontSize: style('.cm-live-h2')?.fontSize || '',
                titleTextAlign: style('.cm-live-document-title')?.textAlign || '',
                h2TextAlign: style('.cm-live-h2')?.textAlign || '',
                collapsedCodeFenceLineCount: document.querySelectorAll('.cm-live-code-fence-line').length,
                collapsedCodeFenceVisibleHeight: Array.from(document.querySelectorAll('.cm-live-code-fence-line'))
                    .reduce((height, line) => height + line.getBoundingClientRect().height, 0),
                editBlankLineCount: document.querySelectorAll('.cm-live-blank-line').length,
                editBlankLineMinimumHeight: (() => {
                    const heights = Array.from(document.querySelectorAll('.cm-live-blank-line'))
                        .map(line => line.getBoundingClientRect().height);
                    return heights.length > 0 ? Math.min(...heights) : 0;
                })(),
                semanticGapCount: document.querySelectorAll('.cm-live-semantic-gap').length,
                liveListMarkerCount: document.querySelectorAll('.cm-live-list-marker').length,
                liveListMarkerUsesPrimaryText: (() => {
                    const marker = document.querySelector('.cm-live-list-marker');
                    if (!marker) return false;
                    const expected = getComputedStyle(document.documentElement)
                        .getPropertyValue('--scholium-color-primary-text').trim();
                    const probe = document.createElement('span');
                    probe.style.color = expected;
                    document.body.appendChild(probe);
                    const resolvedExpected = getComputedStyle(probe).color;
                    probe.remove();
                    return getComputedStyle(marker).color === resolvedExpected;
                })(),
                liveListMarkerText: Array.from(document.querySelectorAll('.cm-live-list-marker'))
                    .map(marker => marker.textContent || '')
                    .join('|'),
                liveListMarkerTextGap: (() => {
                    const marker = document.querySelector('.cm-live-list-marker');
                    if (!marker) return 0;
                    const line = marker.closest('.cm-line');
                    if (!line) return 0;
                    const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
                    let node;
                    let afterMarker = false;
                    while ((node = walker.nextNode())) {
                        if (marker.contains(node)) {
                            afterMarker = true;
                            continue;
                        }
                        if (!afterMarker || !(node.textContent || '').length) continue;
                        const range = document.createRange();
                        range.setStart(node, 0);
                        range.setEnd(node, 1);
                        return Math.max(
                            0,
                            range.getBoundingClientRect().left - marker.getBoundingClientRect().right
                        );
                    }
                    return 0;
                })(),
                liveTaskSourceTokenCount: Array.from(document.querySelectorAll('.cm-live-task-list'))
                    .filter(line => /\\[[ xX]\\]/.test(line.textContent || ''))
                    .length,
                quotePaddingInlineStart: style('.cm-live-quote')?.paddingLeft || '',
                quoteMarginInlineStart: style('.cm-live-quote')?.marginInlineStart || '',
                visibleLineClassSummary: Array.from(document.querySelectorAll('.cm-line'))
                    .slice(0, 16)
                    .map(line => `${line.textContent || ''} [${line.className}]`)
                    .join(' | '),
                contentPaddingTop: contentStyle?.paddingTop || '',
                contentPaddingInlineStart: contentStyle?.paddingInlineStart || '',
                lineWrappingEnabled: content?.classList.contains('cm-lineWrapping') || false,
                softWrapProbeHeight: Array.from(document.querySelectorAll('.cm-line'))
                    .find(line => line.textContent?.includes('SOFT_WRAP_PROBE'))
                    ?.getBoundingClientRect().height || 0,
                scrollTop: document.querySelector('.cm-scroller')?.scrollTop || 0,
                scrollExtent: (() => {
                    const scroller = document.querySelector('.cm-scroller');
                    return scroller ? Math.max(0, scroller.scrollHeight - scroller.clientHeight) : 0;
                })(),
                mathRuntimeVersion: window.scholiumMath?.version || 0,
                renderedMathCount: document.querySelectorAll('.cm-live-math.scholium-math-rendered').length,
                mathErrorCount: document.querySelectorAll('.cm-live-math.scholium-math-error').length,
                displayMathOverflowX: (() => {
                    const display = document.querySelector('.cm-live-math.scholium-math-display');
                    return display ? getComputedStyle(display).overflowX : '';
                })(),
                previewAnchorCount: document.querySelectorAll('[data-link-preview-index]').length,
                previewPopoverHidden: document.getElementById('scholium-preview-popover')?.hidden !== false,
                previewTitle: document.querySelector('#scholium-preview-popover .scholium-preview-title')?.textContent || '',
                previewNestedListCount: document.querySelectorAll('#scholium-preview-popover ul ul').length,
                previewBlockquoteCount: document.querySelectorAll('#scholium-preview-popover blockquote').length,
                previewCodeBlockCount: document.querySelectorAll('#scholium-preview-popover pre code.language-swift').length,
                previewCalloutCount: document.querySelectorAll('#scholium-preview-popover .scholium-callout-state').length,
                previewTableCount: document.querySelectorAll('#scholium-preview-popover table.scholium-table').length,
                previewRenderedMathCount: document.querySelectorAll('#scholium-preview-popover .scholium-math-rendered').length,
                frontmatterLineCount: document.querySelectorAll('.cm-live-frontmatter').length,
                frontmatterVisibleHeight: Array.from(document.querySelectorAll('.cm-live-frontmatter'))
                    .reduce((height, line) => height + line.getBoundingClientRect().height, 0),
                unclosedFrontmatterNoticeCount: document.querySelectorAll('.cm-live-frontmatter-unavailable').length,
                semanticTableCount: document.querySelectorAll('.cm-live-table-widget .scholium-table').length,
                liveTableSourceLineCount: document.querySelectorAll('.cm-line.cm-live-table').length,
                tableHeaderCount: document.querySelectorAll('.cm-live-table-widget th[scope="col"]').length,
                tableBodyCellCount: document.querySelectorAll('.cm-live-table-widget tbody td').length,
                tableStrongCount: document.querySelectorAll('.cm-live-table-widget strong').length,
                tableFirstHeaderText: document.querySelector('.cm-live-table-widget th')?.textContent || '',
                tableOverflowX: (() => {
                    const scroller = document.querySelector('.cm-live-table-widget');
                    return scroller ? getComputedStyle(scroller).overflowX : '';
                })(),
                footnoteReferenceCount: document.querySelectorAll('.cm-live-footnote-reference-widget .footnote-reference').length,
                footnoteDefinitionSourceCount: Array.from(document.querySelectorAll('.cm-line'))
                    .filter(line => /^\\s*\\[\\^[^\\]]+\\]:/.test(line.textContent || ''))
                    .length,
                liveCalloutWidgetCount: document.querySelectorAll('.cm-live-callout-widget.scholium-callout').length,
                liveCalloutSourceLineCount: document.querySelectorAll('.cm-line.cm-live-callout').length,
                liveRawHTMLWidgetCount: document.querySelectorAll('.cm-live-raw-html-widget').length,
                liveRawHTMLSourceLineCount: document.querySelectorAll('.cm-line.cm-live-raw-html').length,
                exactWikilinkSourceCount: Array.from(document.querySelectorAll('.cm-line'))
                    .filter(line => line.textContent?.includes('[[') && line.textContent?.includes(']]')).length,
                incompleteWikilinkSourceCount: Array.from(document.querySelectorAll('.cm-line'))
                    .filter(line => line.textContent?.includes('[[') !== line.textContent?.includes(']]')).length,
                exactCalloutSourceCount: Array.from(document.querySelectorAll('.cm-line'))
                    .filter(line => line.textContent?.includes('[!')).length,
                activeLiveBlockKind: document.querySelector('.cm-editor')
                    ?.dataset.scholiumActiveLiveBlock || '',
                presentation: {
                    rootContentTopInset: rootStyle.getPropertyValue('--scholium-document-content-top-inset').trim(),
                    rootTextScale: rootStyle.getPropertyValue('--scholium-document-text-scale').trim(),
                    rootProseLineHeight: rootStyle.getPropertyValue('--scholium-rhythm-prose-line-height').trim(),
                    rootParagraphGap: rootStyle.getPropertyValue('--scholium-rhythm-paragraph-gap').trim(),
                    rootHeadingLineHeight: rootStyle.getPropertyValue('--scholium-rhythm-heading-line-height').trim(),
                    rootInlineRegular: rootStyle.getPropertyValue('--scholium-rhythm-inline-regular').trim(),
                    rootInlineSource: rootStyle.getPropertyValue('--scholium-rhythm-inline-source').trim(),
                    rootInlineNarrow: rootStyle.getPropertyValue('--scholium-rhythm-inline-narrow').trim(),
                    rootLineWidth: rootStyle.getPropertyValue('--scholium-document-line-width').trim(),
                    viewportWidth: document.documentElement.clientWidth,
                    pageColor: style('.cm-scroller')?.color || '',
                    pageBackgroundColor: style('.cm-editor')?.backgroundColor || '',
                    documentFontFamily: style('.cm-scroller')?.fontFamily || '',
                    documentFontSize: style('.cm-scroller')?.fontSize || '',
                    documentLineHeight: style('.cm-scroller')?.lineHeight || '',
                    documentMaxWidth: contentStyle?.maxWidth || '',
                    documentPaddingTop: contentStyle?.paddingTop || '',
                    documentPaddingInlineStart: contentStyle?.paddingInlineStart || '',
                    documentWidth: width('.cm-content'),
                    documentLeft: bounds('.cm-content').left,
                    documentRight: bounds('.cm-content').right,
                    firstGlyphLeft: firstGlyphLeft('.cm-live-h2'),
                    pageHorizontalOverflow: Math.max(0, document.documentElement.scrollWidth - document.documentElement.clientWidth),
                    latinGlyphsPerLine: maximumGlyphsOnLine('LATIN_GRID_PROBE'),
                    cjkGlyphsPerLine: maximumGlyphsOnLine('CJK_GRID_PROBE'),
                    headingFontFamily: headingStyle?.fontFamily || '',
                    headingFontSize: headingStyle?.fontSize || '',
                    headingFontWeight: headingStyle?.fontWeight || '',
                    headingLineHeight: headingStyle?.lineHeight || '',
                    headingBlockBefore: px(headingBlockStyle?.marginTop) + px(headingBlockStyle?.paddingTop),
                    headingBlockAfter: px(headingBlockStyle?.marginBottom) + px(headingBlockStyle?.paddingBottom),
                    headingWidth: width('.cm-live-h2'),
                    headingTextDecorationLine: headingStyle?.textDecorationLine || '',
                    titleTextDecorationLine: titleStyle?.textDecorationLine || '',
                    titleBorderBottomWidth: titleRuleStyle?.borderTopWidth || '',
                    titleWidth: width('.cm-live-document-title'),
                    calloutAccent: calloutStyle?.getPropertyValue('--callout-accent').trim() || '',
                    calloutBorderColor: calloutStyle?.borderInlineStartColor || '',
                    calloutFontSize: calloutStyle?.fontSize || '',
                    calloutLineHeight: calloutStyle?.lineHeight || '',
                    calloutWidth: width('.cm-live-callout-widget.scholium-callout-state'),
                    calloutRoleColor: calloutRoleStyle?.color || '',
                    calloutRolePosition: calloutRoleStyle?.position || '',
                    calloutRoleWidth: width('.cm-live-callout-widget.scholium-callout-state .scholium-callout-role'),
                    calloutRoleHeight: document.querySelector('.cm-live-callout-widget.scholium-callout-state .scholium-callout-role')?.getBoundingClientRect().height || 0,
                    calloutRoleFontFamily: calloutRoleStyle?.fontFamily || '',
                    calloutRoleFontSize: calloutRoleStyle?.fontSize || '',
                    calloutRoleFontWeight: calloutRoleStyle?.fontWeight || '',
                    calloutRoleLineHeight: calloutRoleStyle?.lineHeight || '',
                    calloutRoleLetterSpacing: calloutRoleStyle?.letterSpacing || '',
                    calloutRoleTextTransform: calloutRoleStyle?.textTransform || '',
                    calloutTitleColor: calloutTitleStyle?.color || '',
                    calloutTitleFontFamily: calloutTitleStyle?.fontFamily || '',
                    calloutTitleFontSize: calloutTitleStyle?.fontSize || '',
                    calloutTitleFontWeight: calloutTitleStyle?.fontWeight || '',
                    calloutTitleLineHeight: calloutTitleStyle?.lineHeight || '',
                    calloutTitleLetterSpacing: calloutTitleStyle?.letterSpacing || '',
                    calloutTitleTextTransform: calloutTitleStyle?.textTransform || '',
                    orientationTextAlign: orientationStyle?.textAlign || '',
                    tableOverflowX: tableStyle?.overflowX || '',
                    tableWidth: width('.cm-live-table-widget'),
                    tableCellFontFamily: tableCellStyle?.fontFamily || '',
                    tableCellFontSize: tableCellStyle?.fontSize || '',
                    tableCellLineHeight: tableCellStyle?.lineHeight || '',
                    tableCellPaddingBlockStart: tableCellStyle?.paddingBlockStart || '',
                    tableCellPaddingInlineStart: tableCellStyle?.paddingInlineStart || '',
                    tableCellBorderBottomWidth: tableCellStyle?.borderBottomWidth || '',
                    tableCellBorderBottomColor: tableCellStyle?.borderBottomColor || '',
                    mathOverflowX: mathStyle?.overflowX || '',
                    mathColor: mathStyle?.color || '',
                    mathFontSize: mathStyle?.fontSize || '',
                    mathLineHeight: mathStyle?.lineHeight || '',
                    mathMarginBlockStart: mathStyle?.marginBlockStart || '',
                    mathPaddingBlockStart: mathStyle?.paddingBlockStart || '',
                    mathWidth: width('.cm-live-math.scholium-math-display'),
                    mathScrollExtent: mathGeometry.scrollExtent,
                    mathOutputWidth: mathGeometry.outputWidth,
                    mathOutputInternalOverflow: mathGeometry.outputInternalOverflow,
                    mathStartClipping: mathGeometry.startClipping,
                    mathEndClipping: mathGeometry.endClipping,
                    mathMiddleTrackWidth: mathGeometry.middleTrackWidth,
                    mathRightTrackWidth: mathGeometry.rightTrackWidth
                }
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard JSONSerialization.isValidJSONObject(rawResult as Any) else {
            throw SessionError.invalidResult
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rawResult as Any) else {
            throw SessionError.invalidResult
        }
        return try JSONDecoder().decode(TestingAccessibilitySnapshot.self, from: data)
    }

    func testingInlineProjectionSnapshot(
        containing requestedText: String
    ) async throws -> TestingInlineProjectionSnapshot {
        guard let webView else { throw SessionError.unavailable }
        let rawResult = try await webView.callAsyncJavaScript(
            """
            const line = Array.from(document.querySelectorAll('.cm-line'))
                .find(candidate => candidate.textContent?.includes(requestedText));
            if (!line) return null;
            const texts = selector => Array.from(line.querySelectorAll(selector))
                .map(element => element.textContent || '');
            const styles = (selector, property) => Array.from(line.querySelectorAll(selector))
                .map(element => getComputedStyle(element)[property] || '');
            return {
                lineText: line.textContent || '',
                strongTexts: texts('.cm-live-strong'),
                strongWeights: styles('.cm-live-strong', 'fontWeight'),
                emphasisTexts: texts('.cm-live-emphasis'),
                emphasisStyles: styles('.cm-live-emphasis', 'fontStyle'),
                strikethroughTexts: texts('.cm-live-strike'),
                highlightTexts: texts('.cm-live-highlight'),
                highlightBackgrounds: styles('.cm-live-highlight', 'backgroundColor'),
                highlightColors: styles('.cm-live-highlight', 'color'),
                codeTexts: texts('.cm-live-code'),
                linkTexts: texts('.cm-live-link'),
                wikiLinkTexts: texts('.cm-live-vector-link, .cm-live-embed')
            };
            """,
            arguments: ["requestedText": requestedText],
            in: nil,
            contentWorld: .page
        )
        guard JSONSerialization.isValidJSONObject(rawResult as Any),
              let data = try? JSONSerialization.data(withJSONObject: rawResult as Any) else {
            throw SessionError.invalidResult
        }
        return try JSONDecoder().decode(TestingInlineProjectionSnapshot.self, from: data)
    }

    func testingCalloutProjectionSnapshot(
        containing requestedText: String
    ) async throws -> TestingCalloutProjectionSnapshot {
        guard let webView else { throw SessionError.unavailable }
        let rawResult = try await webView.callAsyncJavaScript(
            """
            const line = Array.from(document.querySelectorAll('.cm-line'))
                .find(candidate => candidate.textContent?.includes(requestedText));
            const widget = Array.from(document.querySelectorAll('.cm-live-callout-widget'))
                .find(candidate => candidate.textContent?.includes(requestedText));
            const links = widget
                ? Array.from(widget.querySelectorAll('[data-scholium-link-target]'))
                : [];
            return {
                sourceLineText: line?.textContent || '',
                renderedLinkTexts: links.map(link => link.textContent || ''),
                renderedLinkTargets: links.map(link => link.dataset.scholiumLinkTarget || '')
            };
            """,
            arguments: ["requestedText": requestedText],
            in: nil,
            contentWorld: .page
        )
        guard JSONSerialization.isValidJSONObject(rawResult as Any),
              let data = try? JSONSerialization.data(withJSONObject: rawResult as Any) else {
            throw SessionError.invalidResult
        }
        return try JSONDecoder().decode(TestingCalloutProjectionSnapshot.self, from: data)
    }

    func testingEditorSelectionPresentationSnapshot() async throws
        -> TestingEditorSelectionPresentationSnapshot
    {
        guard let webView else { throw SessionError.unavailable }
        let rawResult = try await webView.callAsyncJavaScript(
            """
            const runs = Array.from(document.querySelectorAll('.cm-scholium-selected-text'));
            const probe = document.createElement('span');
            probe.style.background = 'color-mix(in srgb, var(--scholium-color-accent) 24%, transparent)';
            document.body.appendChild(probe);
            const expected = getComputedStyle(probe).backgroundColor;
            probe.remove();
            const content = document.querySelector('.cm-content');
            return {
                selectedTexts: runs.map(run => run.textContent || ''),
                selectedRunCount: runs.length,
                selectedBlankLineRunCount: document.querySelectorAll(
                    '.cm-live-blank-line .cm-scholium-selected-text'
                ).length,
                stockRectangleCount: document.querySelectorAll('.cm-selectionBackground').length,
                nativeSelectionBackground: content
                    ? getComputedStyle(content, '::selection').backgroundColor
                    : '',
                selectedBackgroundsMatchAccent: runs.every(
                    run => getComputedStyle(run).backgroundColor === expected
                )
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard JSONSerialization.isValidJSONObject(rawResult as Any),
              let data = try? JSONSerialization.data(withJSONObject: rawResult as Any) else {
            throw SessionError.invalidResult
        }
        return try JSONDecoder().decode(
            TestingEditorSelectionPresentationSnapshot.self,
            from: data
        )
    }
}
#endif
