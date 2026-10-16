import AppKit
import ScholiumContracts
import SwiftUI

struct AppearanceReadingEditor: View {
    @Binding var profile: DocumentAppearanceProfile
    @ObservedObject var fontCatalog: ScholiumSettingsFontCatalog
    @Binding var numericDrafts: AppearanceNumericDrafts

    var body: some View {
        Section("Reading") {
            Picker("Body Font", selection: $profile.settings.body.fontFamily) {
                ForEach(DocumentAppearanceFontFamily.presets, id: \.self) { Text($0.label).tag($0) }
                Divider()
                ForEach(
                    fontCatalog.families(
                        retaining: profile.settings.body.fontFamily.rawValue,
                        excluding: DocumentAppearanceFontFamily.presets.map(\.rawValue)),
                    id: \.self
                ) { family in
                    Text(verbatim: family).tag(DocumentAppearanceFontFamily(rawValue: family))
                }
            }
            .accessibilityIdentifier("scholium.appearance.bodyFont")
            LabeledContent("Body font size") {
                HStack(alignment: .top) {
                    AppearanceNumberControl(
                        field: .bodyFontSize, numericDrafts: $numericDrafts,
                        value: $profile.settings.body.fontSizePoints, range: 9...24, step: 0.5,
                        title: "Body font size")
                    Text("pt").foregroundStyle(.secondary)
                        .frame(width: ScholiumMetrics.Settings.unitLabelWidth, alignment: .leading)
                }
            }
            LabeledContent("Reading line width") {
                AppearanceDoubleValueControl(
                    field: .readingLineWidth, numericDrafts: $numericDrafts,
                    value: $profile.settings.lineWidthCharacterUnits,
                    range: DocumentAppearanceSettings.lineWidthCharacterUnitsRange,
                    step: 1, suffix: "ch", precision: 0, title: "Reading line width",
                    accessibilityUnit: "character-width units")
            }
            LabeledContent("Line spacing") {
                AppearanceDoubleValueControl(
                    field: .bodyLineSpacing, numericDrafts: $numericDrafts,
                    value: $profile.settings.body.lineHeight, range: 1.2...2.4,
                    step: 0.05, suffix: "×", precision: 2, title: "Line spacing", accessibilityUnit: nil)
            }
            Picker("Alignment", selection: $profile.settings.body.alignment) {
                ForEach(DocumentTextAlignment.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Picker("Hyphenation", selection: $profile.settings.hyphenation) {
                ForEach(DocumentHyphenation.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .accessibilityIdentifier("scholium.appearance.hyphenation")
            .id(SettingsSection.appearanceHyphenation)
            Text(
                "Automatic hyphenation uses language-aware dictionaries for supported prose. Chinese text is not syllabified; Source and technical regions remain unchanged."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }.id(SettingsSection.appearanceReading)
    }
}

struct AppearanceSourceEditor: View {
    @Binding var profile: DocumentAppearanceProfile
    @ObservedObject var fontCatalog: ScholiumSettingsFontCatalog
    @Binding var numericDrafts: AppearanceNumericDrafts

    var body: some View {
        Section("Source Font") {
            Picker("Source Font", selection: $profile.settings.source.fontFamily) {
                ForEach(fontCatalog.families(retaining: profile.settings.source.fontFamily), id: \.self) {
                    Text(verbatim: $0).tag($0)
                }
            }
            .accessibilityIdentifier("scholium.appearance.sourceFont")
            LabeledContent("Source font size") {
                HStack(alignment: .top) {
                    AppearanceNumberControl(
                        field: .sourceFontSize, numericDrafts: $numericDrafts,
                        value: $profile.settings.source.fontSizePoints, range: 6...72, step: 0.25,
                        title: "Source font size")
                    Text("pt").foregroundStyle(.secondary)
                        .frame(width: ScholiumMetrics.Settings.unitLabelWidth, alignment: .leading)
                }
            }
        }.id(SettingsSection.appearanceSource)
    }

}

struct TypographySettingsView: View {
    @Binding var profile: DocumentAppearanceProfile
    @ObservedObject var fontCatalog: ScholiumSettingsFontCatalog
    @Binding var numericDrafts: AppearanceNumericDrafts

    var body: some View {
        Group {
            Section("Body Typography") {
                LabeledContent("Paragraph spacing") {
                    AppearanceDoubleValueControl(
                        field: .bodyParagraphSpacing, numericDrafts: $numericDrafts,
                        value: $profile.settings.body.paragraphSpacingEm, range: 0...2,
                        step: 0.05, suffix: "em", precision: 2, title: "Paragraph spacing",
                        accessibilityUnit: nil)
                }
                LabeledContent("First-line indent") {
                    AppearanceDoubleValueControl(
                        field: .bodyFirstLineIndent, numericDrafts: $numericDrafts,
                        value: $profile.settings.body.firstLineIndentEm, range: 0...4,
                        step: 0.1, suffix: "em", precision: 2, title: "First-line indent",
                        accessibilityUnit: nil)
                }
            }.id(SettingsSection.appearanceBody)
            AppearanceSourceEditor(profile: $profile, fontCatalog: fontCatalog, numericDrafts: $numericDrafts)
            Section("Heading Typography") {
                Picker("Heading Font", selection: $profile.settings.headings.fontFamily) {
                    ForEach(DocumentHeadingFontFamily.presets, id: \.self) { Text($0.label).tag($0) }
                    Divider()
                    ForEach(headingFamilies, id: \.self) { family in
                        Text(verbatim: family).tag(DocumentHeadingFontFamily(rawValue: family))
                    }
                }
                .accessibilityIdentifier("scholium.appearance.headingFont")
                Picker("Heading Style", selection: $profile.settings.headings.style) {
                    ForEach(DocumentHeadingStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                LabeledContent("Heading Weight") {
                    AppearanceIntegerControl(
                        field: .headingWeight, numericDrafts: $numericDrafts,
                        title: "Heading Weight", value: $profile.settings.headings.weight, range: 400...700,
                        step: 50)
                }
                LabeledContent("Heading Line Spacing") {
                    AppearanceDoubleValueControl(
                        field: .headingLineSpacing, numericDrafts: $numericDrafts,
                        value: $profile.settings.headings.lineHeight, range: 1...2.4,
                        step: 0.05, suffix: "×", precision: 2, title: "Heading Line Spacing",
                        accessibilityUnit: nil)
                }
            }.id(SettingsSection.appearanceHeadingFont)
            Section("Heading Hierarchy") {
                AppearanceHeadingLevelMatrix(headings: $profile.settings.headings, numericDrafts: $numericDrafts)
            }.id(SettingsSection.appearanceHeadings)
            Section("Text Styles") {
                roleFont("Body Bold Font", selection: $profile.settings.body.cjkStrongFontFamily)
                roleFont("Body Italic Font", selection: $profile.settings.body.cjkEmphasisFontFamily)
                roleFont("Heading Bold Font", selection: $profile.settings.headings.cjkStrongFontFamily)
                roleFont("Heading Italic Font", selection: $profile.settings.headings.cjkEmphasisFontFamily)
            }.id(SettingsSection.appearanceStyles)
        }
        .accessibilityIdentifier("scholium.settings.appearance.typography")
    }

    private var headingFamilies: [String] {
        fontCatalog.families(
            retaining: profile.settings.headings.fontFamily.rawValue,
            excluding: DocumentHeadingFontFamily.presets.map(\.rawValue))
    }

    private func roleFont(_ title: LocalizedStringResource, selection: Binding<String?>) -> some View {
        AppearanceRoleFontPicker(
            title: title, selection: selection,
            availableFamilies: fontCatalog.families(retaining: selection.wrappedValue))
    }

}

private struct AppearanceHeadingLevelMatrix: View {
    @Binding var headings: DocumentHeadingAppearance
    @Binding var numericDrafts: AppearanceNumericDrafts

    var body: some View {
        // Keep each level a direct native Form row so search can reveal it
        // before the lower part of this scrolling group is realized.
        ForEach(AppearanceHeadingLevel.allCases) { level in
            ViewThatFits(in: .horizontal) {
                Grid(
                    alignment: .leading,
                    horizontalSpacing: ScholiumMetrics.Settings.matrixColumnSpacing,
                    verticalSpacing: ScholiumMetrics.Settings.matrixRowSpacing
                ) {
                    GridRow {
                        settingsMatrixHeader("Heading Level")
                        settingsMatrixHeader("Scale")
                        settingsMatrixHeader("Alignment")
                        settingsMatrixHeader("Space Before")
                        settingsMatrixHeader("Space After")
                    }
                    AppearanceHeadingLevelMatrixRow(
                        level: level,
                        appearance: binding(for: level), numericDrafts: $numericDrafts)
                }
                .frame(minWidth: ScholiumMetrics.Settings.headingMatrixMinimumWidth, maxWidth: .infinity, alignment: .leading)
                AppearanceHeadingLevelDetailRow(
                    level: level,
                    appearance: binding(for: level), numericDrafts: $numericDrafts)
            }
            .id(SettingsSection.appearanceHeading(level))
        }
    }

    private func binding(
        for level: AppearanceHeadingLevel
    ) -> Binding<DocumentHeadingLevelAppearance> {
        switch level {
        case .h1: $headings.level1
        case .h2: $headings.level2
        case .h3: $headings.level3
        case .h4: $headings.level4
        case .h5: $headings.level5
        case .h6: $headings.level6
        }
    }

}

private struct AppearanceHeadingLevelMatrixRow: View {
    let level: AppearanceHeadingLevel
    @Binding var appearance: DocumentHeadingLevelAppearance
    @Binding var numericDrafts: AppearanceNumericDrafts

    var body: some View {
        GridRow {
            settingsMatrixRowLabel(level.title)
            HStack(alignment: .top, spacing: 6) {
                AppearanceNumberControl(
                    field: .headingScale(level), numericDrafts: $numericDrafts,
                    value: $appearance.scale,
                    range: 0.8...3,
                    step: 0.05,
                    title: "\(level.title) scale"
                )
                Text("×")
                    .foregroundStyle(.secondary)
            }
            Picker("\(level.title) alignment", selection: $appearance.alignment) {
                ForEach(DocumentTextAlignment.allCases, id: \.self) {
                    Text($0.label).tag($0)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 124, alignment: .leading)
            Group {
                HStack(alignment: .top, spacing: 6) {
                    AppearanceNumberControl(
                        field: .headingSpaceBefore(level), numericDrafts: $numericDrafts,
                        value: $appearance.spaceBeforeEm,
                        range: 0...4,
                        step: 0.05,
                        title: "\(level.title) space before"
                    )
                    Text("em")
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 6) {
                    AppearanceNumberControl(
                        field: .headingSpaceAfter(level), numericDrafts: $numericDrafts,
                        value: $appearance.spaceAfterEm,
                        range: 0...4,
                        step: 0.05,
                        title: "\(level.title) space after"
                    )
                    Text("em")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct AppearanceHeadingLevelDetailRow: View {
    let level: AppearanceHeadingLevel
    @Binding var appearance: DocumentHeadingLevelAppearance
    @Binding var numericDrafts: AppearanceNumericDrafts

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text(level.title)
                .font(.subheadline.weight(.semibold))
            settingsEditorSection("Scale") {
                HStack(alignment: .top, spacing: 6) {
                    AppearanceNumberControl(
                        field: .headingScale(level), numericDrafts: $numericDrafts,
                        value: $appearance.scale,
                        range: 0.8...3,
                        step: 0.05,
                        title: "\(level.title) scale"
                    )
                    Text("×")
                        .foregroundStyle(.secondary)
                }
            }
            settingsEditorSection("Alignment") {
                Picker("\(level.title) alignment", selection: $appearance.alignment) {
                    ForEach(DocumentTextAlignment.allCases, id: \.self) {
                        Text($0.label).tag($0)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            settingsEditorSection("Space Before") {
                HStack(alignment: .top, spacing: 6) {
                    AppearanceNumberControl(
                        field: .headingSpaceBefore(level), numericDrafts: $numericDrafts,
                        value: $appearance.spaceBeforeEm,
                        range: 0...4,
                        step: 0.05,
                        title: "\(level.title) space before"
                    )
                    Text("em")
                        .foregroundStyle(.secondary)
                }
            }
            settingsEditorSection("Space After") {
                HStack(alignment: .top, spacing: 6) {
                    AppearanceNumberControl(
                        field: .headingSpaceAfter(level), numericDrafts: $numericDrafts,
                        value: $appearance.spaceAfterEm,
                        range: 0...4,
                        step: 0.05,
                        title: "\(level.title) space after"
                    )
                    Text("em")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// Raw input belongs to the appearance page, including the two adaptive
// presentations of each heading field. It never becomes saved configuration.
enum AppearanceNumericField: Hashable {
    case bodyFontSize, sourceFontSize, readingLineWidth, bodyLineSpacing
    case bodyParagraphSpacing, bodyFirstLineIndent, headingWeight, headingLineSpacing
    case headingScale(AppearanceHeadingLevel)
    case headingSpaceBefore(AppearanceHeadingLevel)
    case headingSpaceAfter(AppearanceHeadingLevel)
}

enum AppearanceNumericValidation: Equatable {
    case valid(Double)
    case empty
    case invalidNumber
    case outOfRange

    var value: Double? {
        if case .valid(let value) = self { return value }
        return nil
    }

    static func parse(
        _ text: String, range: ClosedRange<Double>, isInteger: Bool = false,
        locale: Locale
    ) -> Self {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        // A trailing decimal separator remains an unfinished edit. Scanner
        // consumes complete input; it cannot accept a valid numeric prefix.
        guard !trimmed.hasSuffix(locale.decimalSeparator ?? ".") else { return .invalidNumber }
        let scanner = Scanner(string: trimmed)
        scanner.locale = locale
        scanner.charactersToBeSkipped = nil
        let candidate: Double?
        if isInteger {
            candidate = scanner.scanInt().map(Double.init)
        } else {
            candidate = scanner.scanDouble()
        }
        guard let candidate, candidate.isFinite, scanner.isAtEnd else { return .invalidNumber }
        guard range.contains(candidate) else { return .outOfRange }
        return .valid(candidate)
    }
}

struct AppearanceNumericDrafts {
    private struct Input {
        let text: String
        let validation: AppearanceNumericValidation
    }

    private var inputs: [AppearanceNumericField: Input] = [:]

    var hasInvalidInput: Bool {
        inputs.values.contains { $0.validation.value == nil }
    }

    func text(for field: AppearanceNumericField) -> String? { inputs[field]?.text }
    func validation(for field: AppearanceNumericField) -> AppearanceNumericValidation? {
        inputs[field]?.validation
    }

    @discardableResult
    mutating func update(
        _ text: String, for field: AppearanceNumericField, range: ClosedRange<Double>,
        isInteger: Bool = false, locale: Locale
    ) -> Double? {
        let validation = AppearanceNumericValidation.parse(
            text, range: range, isInteger: isInteger, locale: locale)
        inputs[field] = Input(text: text, validation: validation)
        return validation.value
    }

    mutating func clear(_ field: AppearanceNumericField) { inputs[field] = nil }
    mutating func reset() { inputs.removeAll() }
}

private struct AppearanceNumericTextField: View {
    @Environment(\.locale) private var locale
    let field: AppearanceNumericField
    @Binding var numericDrafts: AppearanceNumericDrafts
    @Binding var value: Double
    let range: ClosedRange<Double>
    let precision: Int
    let isInteger: Bool
    let title: LocalizedStringResource

    private var format: FloatingPointFormatStyle<Double> {
        .number.locale(locale).grouping(.never).precision(.fractionLength(0...precision))
    }

    private var limits: LocalizedStringResource {
        let lower = range.lowerBound.formatted(format)
        let upper = range.upperBound.formatted(format)
        return isInteger
            ? "Enter a whole number from \(lower) to \(upper)."
            : "Enter a number from \(lower) to \(upper)."
    }

    private var error: LocalizedStringResource? {
        guard let validation = numericDrafts.validation(for: field), validation.value == nil else {
            return nil
        }
        let lower = range.lowerBound.formatted(format)
        let upper = range.upperBound.formatted(format)
        switch validation {
        case .valid: return nil
        case .outOfRange: return "Use \(lower)–\(upper)."
        case .empty, .invalidNumber:
            return isInteger ? "Whole number: \(lower)–\(upper)." : "Enter \(lower)–\(upper)."
        }
    }

    private var text: Binding<String> {
        Binding(
            get: { numericDrafts.text(for: field) ?? value.formatted(format) },
            set: { text in
                if let candidate = numericDrafts.update(
                    text, for: field, range: range, isInteger: isInteger, locale: locale)
                {
                    value = candidate
                }
            })
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(Text(title))
                .accessibilityHint(Text(error ?? limits))
                .help(Text(limits))
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
        // Validation grows vertically without changing the adaptive matrix's
        // width, replacing its text field, or moving native keyboard focus.
        .frame(width: ScholiumMetrics.Settings.numberFieldWidth, alignment: .trailing)
    }
}

private struct AppearanceNumberControl: View {
    let field: AppearanceNumericField
    @Binding var numericDrafts: AppearanceNumericDrafts
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let title: LocalizedStringResource

    private var stepperValue: Binding<Double> {
        Binding(
            get: { value },
            set: { candidate in
                guard candidate.isFinite else { return }
                value = min(max(candidate, range.lowerBound), range.upperBound)
                numericDrafts.clear(field)
            })
    }

    var body: some View {
        HStack(alignment: .top, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            AppearanceNumericTextField(
                field: field, numericDrafts: $numericDrafts, value: $value,
                range: range, precision: 2, isInteger: false, title: title)
            Stepper("", value: stepperValue, in: range, step: step)
                .labelsHidden().accessibilityLabel(Text(title))
        }
        .fixedSize()
    }
}

private struct AppearanceIntegerControl: View {
    let field: AppearanceNumericField
    @Binding var numericDrafts: AppearanceNumericDrafts
    let title: LocalizedStringResource
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    private var stepperValue: Binding<Int> {
        Binding(
            get: { value },
            set: { candidate in
                value = min(max(candidate, range.lowerBound), range.upperBound)
                numericDrafts.clear(field)
            })
    }

    var body: some View {
        HStack(alignment: .top, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            AppearanceNumericTextField(
                field: field, numericDrafts: $numericDrafts,
                value: Binding(get: { Double(value) }, set: { value = Int($0) }),
                range: Double(range.lowerBound)...Double(range.upperBound),
                precision: 0, isInteger: true, title: title)
            Stepper("", value: stepperValue, in: range, step: step)
                .labelsHidden().accessibilityLabel(Text(title))
        }
        .fixedSize()
    }
}

private struct AppearanceDoubleValueControl: View {
    let field: AppearanceNumericField
    @Binding var numericDrafts: AppearanceNumericDrafts
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String
    let precision: Int
    let title: LocalizedStringResource
    let accessibilityUnit: LocalizedStringResource?

    private var stepperValue: Binding<Double> {
        Binding(
            get: { value },
            set: { candidate in
                guard candidate.isFinite else { return }
                value = min(max(candidate, range.lowerBound), range.upperBound)
                numericDrafts.clear(field)
            })
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            AppearanceNumericTextField(
                field: field, numericDrafts: $numericDrafts, value: $value,
                range: range, precision: precision, isInteger: false, title: title)
            Stepper("", value: stepperValue, in: range, step: step)
                .labelsHidden().fixedSize().accessibilityLabel(Text(title))
            Text(suffix)
                .foregroundStyle(.secondary)
                .frame(width: ScholiumMetrics.Settings.unitLabelWidth, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .help(Text(accessibilityUnit ?? title))
    }
}

private struct AppearanceRoleFontPicker: View {
    private static let defaultChoice = "__scholium_role_default__"
    private static let automaticChoice = "__scholium_role_font__"

    let title: LocalizedStringResource
    @Binding var selection: String?
    let availableFamilies: [String]

    private var choiceBinding: Binding<String> {
        Binding(
            get: {
                if let selection, !selection.isEmpty { return selection }
                if selection == nil { return Self.defaultChoice }
                return Self.automaticChoice
            },
            set: { value in
                if value == Self.defaultChoice {
                    selection = nil
                } else if value == Self.automaticChoice {
                    selection = ""
                } else {
                    selection = value
                }
            }
        )
    }

    var body: some View {
        Picker(title, selection: choiceBinding) {
            Text("Default")
                .tag(Self.defaultChoice)
            Text("Use role font")
                .tag(Self.automaticChoice)
            ForEach(availableFamilies, id: \.self) { family in
                Text(verbatim: family).tag(family)
            }
        }
        .pickerStyle(.menu)
    }
}

extension DocumentAppearanceFontFamily {
    fileprivate var label: String {
        switch self {
        case .alegreya: "Alegreya"
        case .iowan: "Iowan Old Style"
        case .palatino: "Palatino"
        case .georgia: "Georgia"
        case .times: "Times New Roman"
        case .systemSerif: "System Serif"
        default: rawValue
        }
    }
}

extension DocumentHeadingFontFamily {
    fileprivate var label: LocalizedStringResource {
        switch self {
        case .body: "Body Font"
        case .alegreya: "Alegreya"
        case .systemSerif: "System Serif"
        case .systemSans: "System Sans"
        default: LocalizedStringResource(stringLiteral: rawValue)
        }
    }
}

extension DocumentHeadingStyle {
    fileprivate var label: LocalizedStringResource {
        switch self {
        case .upright: "Upright"
        case .italic: "Italic"
        case .smallCaps: "Small Caps"
        }
    }
}

extension DocumentTextAlignment {
    fileprivate var label: LocalizedStringResource {
        switch self {
        case .start: "Start"
        case .center: "Center"
        case .justify: "Justify"
        }
    }
}

extension DocumentHyphenation {
    fileprivate var label: LocalizedStringResource {
        switch self {
        case .none: "Never"
        case .automatic: "Automatic"
        }
    }
}
