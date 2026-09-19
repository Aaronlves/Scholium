import Foundation

/// The approved adaptive editorial grid. Values are named by responsibility,
/// not by scale position: AppKit still owns window and split geometry, while
/// these roles govern Scholium-owned spacing and component dimensions.
enum ScholiumGrid {
    static let foundationUnit: CGFloat = 4

    enum Spacing {
        /// Reserved for baseline and symbol alignment, never ordinary spacing.
        static let opticalAlignmentAdjustment = foundationUnit / 2
        static let labelAccessoryGap = foundationUnit
        static let inlineControlGap = foundationUnit * 2
        static let nestedContentInset = foundationUnit * 3
        static let sectionSeparation = foundationUnit * 4
        static let regionContentInset = foundationUnit * 5
        static let documentShellInsetCSSPixels = foundationUnit * 8
        static let sourceShellInsetCSSPixels = foundationUnit * 10
    }

    enum Dimension {
        static let minimumCustomTarget = foundationUnit * 5
        static let compactHierarchyRowHeight = foundationUnit * 6
        static let preferredCustomTarget = foundationUnit * 7
        static let regionHeaderHeight = foundationUnit * 12
        static let iconTrackWidth = foundationUnit * 4
    }

    enum Document {
        static let narrowWidthThresholdRootEms: CGFloat = 44
        static let compactShellInsetCSSPixels = Spacing.regionContentInset
        static let contentTopInsetCSSPixels = Spacing.documentShellInsetCSSPixels
        static let trailingScrollViewportFraction: CGFloat = 0.45
    }

    /// Inspector-owned layout variables. Section hierarchy, content groups,
    /// link occurrences, and Action rows each have a distinct cadence.
    enum Apparatus {
        static let headingToContentGap = foundationUnit * 2.5
        static let contentRowGap = foundationUnit * 2
        static let contentLineSpacing = foundationUnit
        static let iconColumnWidth = foundationUnit * 4
        static let iconToTextGap = foundationUnit * 2
        static let connectionOccurrenceVerticalInset = foundationUnit
        static let actionCopyGap = foundationUnit
        static let longTextLabelGap = foundationUnit
    }

    enum SegmentedControl {
        static let trackInset = Spacing.opticalAlignmentAdjustment
        static let segmentGap = Spacing.opticalAlignmentAdjustment
        static let regularSegmentMinimumHeight = Dimension.preferredCustomTarget
        static let compactSegmentMinimumHeight = Dimension.compactHierarchyRowHeight
        static let regularHorizontalInset = Spacing.nestedContentInset
        static let compactHorizontalInset = Spacing.inlineControlGap
    }

    /// Page- and pane-level state copy shares one readable measure. Placement
    /// and density adapt to the owning region without changing the state's
    /// workflow meaning or lifecycle.
    enum ContentState {
        static let readableWidth = foundationUnit * 90
    }

    /// Settings owns one explanatory content-row rhythm. Native Lists and
    /// controls retain their own geometry; these values apply only to the
    /// supporting content and action rows inside preference pages.
    enum SettingsPresentation {
        static let titleDetailGap = foundationUnit * 1.5
    }

    /// Research-facing sheets share one continuous editorial frame while
    /// their fields, operations, and lifecycle remain workflow-owned.
    enum ResearchSheet {
        static let headerDetailGap = Spacing.labelAccessoryGap
        static let bodySectionGap = Spacing.sectionSeparation
        static let footerControlGap = Spacing.inlineControlGap
        static let statusVerticalInset = foundationUnit * 2.5
    }
}

enum ScholiumMetrics {
    enum Accessibility {
        static let preferredCustomTarget = ScholiumGrid.Dimension.preferredCustomTarget
        static let minimumCustomTarget = ScholiumGrid.Dimension.minimumCustomTarget
    }

    enum SegmentedControl {
        static let trackInset = ScholiumGrid.SegmentedControl.trackInset
        static let segmentSpacing = ScholiumGrid.SegmentedControl.segmentGap
        static let regularSegmentMinimumHeight =
            ScholiumGrid.SegmentedControl.regularSegmentMinimumHeight
        static let compactSegmentMinimumHeight =
            ScholiumGrid.SegmentedControl.compactSegmentMinimumHeight
        static let regularHorizontalInset =
            ScholiumGrid.SegmentedControl.regularHorizontalInset
        static let compactHorizontalInset =
            ScholiumGrid.SegmentedControl.compactHorizontalInset
    }

    enum Onboarding {
        static let preferredWidth: CGFloat = 620
        static let preferredHeight: CGFloat = 700
        static let minimumWidth: CGFloat = 480
        static let minimumHeight: CGFloat = 540
        static let contentMaximumWidth: CGFloat = 540
        static let contentInset = ScholiumGrid.Spacing.regionContentInset
        static let welcomeArtworkHeight: CGFloat = 72
        static let rootSectionSpacing = ScholiumGrid.foundationUnit * 4.5
        static let rootDisclosureSpacing = ScholiumGrid.foundationUnit * 1.5
        static let rootContentInset = ScholiumGrid.foundationUnit * 7
    }

    enum Workspace {
        static let preferredWidth: CGFloat = 1_180
        static let preferredHeight: CGFloat = 760
        /// A region-owned row beneath the native titlebar. Unlike toolbar
        /// height, this is a Scholium component metric used by the Library
        /// identity and Apparatus mode row. Document identity and commands
        /// belong to the native toolbar and do not create a second row.
        static let regionHeaderHeight = ScholiumGrid.Dimension.regionHeaderHeight
        static let loadingOverlayInset = ScholiumGrid.foundationUnit * 7
    }

    enum SettingsPresentation {
        static let titleDetailSpacing = ScholiumGrid.SettingsPresentation.titleDetailGap
        static let trailingControlMinimumSpacing = ScholiumGrid.Spacing.nestedContentInset
        static let editorContentInset = ScholiumGrid.foundationUnit * 4.5
    }

    enum ResearchSheet {
        static let contentInset = ScholiumGrid.Spacing.regionContentInset
        static let headerDetailSpacing = ScholiumGrid.ResearchSheet.headerDetailGap
        static let bodySectionSpacing = ScholiumGrid.ResearchSheet.bodySectionGap
        static let footerControlSpacing = ScholiumGrid.ResearchSheet.footerControlGap
        static let statusVerticalInset = ScholiumGrid.ResearchSheet.statusVerticalInset
        static let fieldSpacing = ScholiumGrid.foundationUnit * 1.5

        enum FileOperation {
            static let minimumWidth: CGFloat = 320
            static let idealWidth: CGFloat = 520
            static let listMaximumHeight: CGFloat = 300
        }

        enum NoteRestructure {
            static let folderColumnWidth: CGFloat = 240
            static let minimumWidth: CGFloat = 560
            static let idealWidth: CGFloat = 760
            static let minimumHeight: CGFloat = 420
            static let idealHeight: CGFloat = 560
        }

        enum AgentChanges {
            static let minimumWidth: CGFloat = 680
            static let idealWidth: CGFloat = 760
            static let minimumHeight: CGFloat = 420
            static let idealHeight: CGFloat = 560
            static let changeColumnWidth: CGFloat = 180
            static let dateColumnWidth: CGFloat = 145
        }

        enum Comparison {
            static let minimumWidth: CGFloat = 760
            static let idealWidth: CGFloat = 900
            static let minimumHeight: CGFloat = 560
            static let idealHeight: CGFloat = 720
            static let documentStateMinimumHeight = ScholiumGrid.foundationUnit * 40
        }
    }

    enum Settings {
        static let navigationWidth: CGFloat = 240
        static let minimumWindowWidth: CGFloat = 780
        static let minimumWindowHeight: CGFloat = 560
        static let headingMatrixMinimumWidth: CGFloat = 650
        static let matrixColumnSpacing = ScholiumGrid.foundationUnit * 4
        static let matrixRowSpacing = ScholiumGrid.foundationUnit * 2.5
        static let numberFieldWidth: CGFloat = 64
        static let unitLabelWidth: CGFloat = 24
        static let sectionSpacing = ScholiumGrid.foundationUnit * 3.5
        static let editorContentInset = ScholiumGrid.Spacing.regionContentInset
        static let headerMaximumWidth = ScholiumGrid.foundationUnit * 155
        static let formExplanationMaximumWidth = ScholiumGrid.foundationUnit * 105
        static let appearancePickerWidth = ScholiumGrid.foundationUnit * 42
        static let listRowSpacing = ScholiumGrid.foundationUnit * 1.25
        static let rowControlSpacing = ScholiumGrid.foundationUnit * 1.5
        static let labelActionMinimumSpacing = ScholiumGrid.foundationUnit * 1.5
        static let fieldSpacing = ScholiumGrid.foundationUnit * 1.5
        static let rootSpacing = ScholiumGrid.foundationUnit * 2.5
        static let rowDetailSpacing = ScholiumGrid.foundationUnit * 0.5
        static let rowActionMinimumSpacing = ScholiumGrid.Spacing.labelAccessoryGap
        static let rowVerticalInset = ScholiumGrid.foundationUnit * 0.75
        static let pathHorizontalInset = ScholiumGrid.foundationUnit * 6
        static let trailingControlMinimumSpacing = ScholiumGrid.Spacing.nestedContentInset
    }

    enum DocumentWorkflow {
        static let sectionSpacing = ScholiumGrid.foundationUnit * 4.5
        static let sheetContentInset = ScholiumGrid.foundationUnit * 5.5
        static let identityContentInset = ScholiumGrid.foundationUnit * 6
        static let compactFieldSpacing = ScholiumGrid.foundationUnit * 1.5
        static let conflictDiffRowVerticalInset = ScholiumGrid.Spacing.opticalAlignmentAdjustment
        static let exactDiffColumnSpacing = ScholiumGrid.Spacing.inlineControlGap
        static let exactDiffLineNumberWidth: CGFloat = 38
        static let exactDiffMarkerWidth: CGFloat = 16
        static let recoverySectionSpacing = ScholiumGrid.foundationUnit * 1.75
        static let recoveryCompactSpacing = ScholiumGrid.foundationUnit * 1.5
        static let recoveryFileSpacing = ScholiumGrid.foundationUnit * 1.25
        static let recoveryRowVerticalInset = ScholiumGrid.foundationUnit * 1.25
    }

    /// Compact macOS completion geometry; touch-sized rows are not imposed on text entry.
    enum Completion {
        static let rowHeight: CGFloat = 28
        static let detailedRowHeight: CGFloat = 40
        static let maximumVisibleRows = 7
    }

    enum Notice {
        static let readableWidth = ScholiumGrid.foundationUnit * 130
        static let maximumStackHeight = ScholiumGrid.foundationUnit * 45
        static let contentSpacing = ScholiumGrid.foundationUnit * 2.5
        static let detailSpacing = ScholiumGrid.foundationUnit * 0.5
        static let verticalInset = ScholiumGrid.foundationUnit * 2.5
    }

    enum Library {
        /// Smallest width at which the complete Library remains readable while
        /// expanded. The longest fixed English header, its count and action,
        /// plus the 20-point region insets fit inside this boundary. AppKit
        /// still owns resizing and collapse; this is not a preferred width or
        /// a window minimum.
        static let minimumReadableWidth: CGFloat = 300
        /// One semantic item-type slot shared by Folder and Note rows after
        /// AppKit's native disclosure gutter.
        static let leadingSlotWidth = ScholiumGrid.Dimension.iconTrackWidth
        static let rowHorizontalInset = ScholiumGrid.Spacing.nestedContentInset
        /// The native outline remains responsible for indentation; Scholium
        /// supplies only its 4-unit hierarchy step.
        static let hierarchyIndent = ScholiumGrid.Dimension.iconTrackWidth
    }

    enum Attention {
        /// Notifications are intentionally presented in a bounded native
        /// popover. Native List scrolling, chrome, and arrow geometry remain
        /// system-owned.
        static let popoverWidth: CGFloat = 420
        static let popoverHeight: CGFloat = 360
    }

    enum Document {
        /// Document-local breathing room below the system-owned toolbar. The
        /// toolbar safe area is not added again by document layout.
        static let contentTopInsetCSSPixels = ScholiumGrid.Document.contentTopInsetCSSPixels
        static let defaultTextScale = 1.0
        static let minimumTextScale = 1.0
        static let maximumTextScale = 2.0
        static let textScaleStep = 0.1
        /// The outline rail yields before the document becomes too narrow to
        /// remain readable. It is an overlay affordance, not a split item.
        static let outlineRailMinimumWidth: CGFloat = ScholiumGrid.foundationUnit * 180
        static let outlineRailWidth: CGFloat = ScholiumGrid.foundationUnit * 8
        static let outlineRailVerticalInset = ScholiumGrid.Spacing.sectionSeparation
        /// The compact rail keeps its visual rhythm denser than a regular
        /// custom control under the compact-outline precision exception in
        /// specification section 20. Each 32 x 12pt target is disjoint, spans
        /// the rail, and retains a named keyboard/AX button. Overflow scrolls
        /// rather than shrinking the targets further.
        static let outlineMarkerTarget: CGFloat = ScholiumGrid.foundationUnit * 3
        static let outlineMarkerHeight: CGFloat = ScholiumGrid.foundationUnit / 2
        static let outlineMarkerActiveHeight: CGFloat = ScholiumGrid.foundationUnit * 0.625
        /// Hierarchy uses length, current location uses stroke weight, and
        /// pointer proximity supplies a continuous additional extension.
        static let outlineMarkerHeadingOneWidth: CGFloat = ScholiumGrid.foundationUnit * 3
        static let outlineMarkerHeadingTwoWidth: CGFloat = ScholiumGrid.foundationUnit * 1.5
        static let outlineMarkerHoverMaximumWidth: CGFloat = ScholiumGrid.foundationUnit * 7
        static let outlineMarkerHoverRadius: CGFloat = 4
        static let outlineMarkerHoverHeight: CGFloat = ScholiumGrid.foundationUnit
        static let outlineHoverHapticInterval: TimeInterval = 0.06
        static let outlinePreviewCornerRadius: CGFloat = ScholiumGrid.foundationUnit * 1.5
        static let outlinePreviewWidth: CGFloat = ScholiumGrid.foundationUnit * 64
        static let outlineMarkerRestingOpacity: CGFloat = 0.32
        static let outlineMarkerHoverOpacity: CGFloat = 0.78
        static let outlineMarkerActiveOpacity: CGFloat = 0.72
        static let outlineMarkerIncreasedContrastRestingOpacity: CGFloat = 0.52
        static let outlineMarkerIncreasedContrastHoverOpacity: CGFloat = 0.78
        static let outlineMarkerIncreasedContrastActiveOpacity: CGFloat = 0.92
        static let outlineMarkerPressedOpacity: CGFloat = 0.78
    }

    enum Apparatus {
        /// AppKit's standard Inspector thickness is 270 points. Scholium keeps
        /// that readable lower bound while allowing the native split item to
        /// grow without an application-defined maximum.
        static let minimumReadableWidth: CGFloat = 270
        /// One initial suggestion, mirroring the system inspector's ideal-width
        /// semantics. AppKit continues to own subsequent resizing.
        static let firstRevealWidth: CGFloat = 320
        /// Internal section rhythm is deliberately separate from the spacing
        /// between complete sections.
        static let sectionContentSpacing = ScholiumGrid.Apparatus.headingToContentGap
        static let bodyLineSpacing = ScholiumGrid.Apparatus.contentLineSpacing
        static let actionCopySpacing = ScholiumGrid.Apparatus.actionCopyGap
        static let longTextLabelSpacing = ScholiumGrid.Apparatus.longTextLabelGap
        /// A fixed symbol track keeps every row's text on the same scan line,
        /// regardless of the optical width of its SF Symbol.
        static let iconColumnWidth = ScholiumGrid.Apparatus.iconColumnWidth
        static let iconToTextSpacing = ScholiumGrid.Apparatus.iconToTextGap
    }

    enum ContentState {
        static let readableWidth = ScholiumGrid.ContentState.readableWidth
    }

    enum Search {
        static let responsiveMargin = ScholiumGrid.Spacing.regionContentInset
        static let resultContentSpacing = ScholiumGrid.foundationUnit * 2.5
        static let diagnosticBottomInset = ScholiumGrid.foundationUnit * 1.75
        static let availabilityDetailSpacing = ScholiumGrid.Spacing.opticalAlignmentAdjustment
        static let availabilityVerticalInset = ScholiumGrid.foundationUnit * 2.25
    }

}
