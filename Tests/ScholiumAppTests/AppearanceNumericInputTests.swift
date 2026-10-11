import Foundation
import Testing

@testable import ScholiumApp

@Suite("Appearance numeric input", .timeLimit(.minutes(1)))
struct AppearanceNumericInputTests {
    private let english = Locale(identifier: "en_US")

    @Test("Whole-number fields accept their endpoints and reject fractional or partial input")
    func integerInput() {
        for value in [400, 525, 700] {
            #expect(
                AppearanceNumericValidation.parse(
                    String(value), range: 400...700, isInteger: true, locale: english) == .valid(Double(value)))
        }
        for text in ["500.5", "500pt", "500 600", "5e2"] {
            #expect(
                AppearanceNumericValidation.parse(
                    text, range: 400...700, isInteger: true, locale: english) == .invalidNumber)
        }
    }

    @Test("Double fields accept fractional values without applying step rounding")
    func doubleInput() {
        for value in [9.0, 12.375, 24.0] {
            #expect(
                AppearanceNumericValidation.parse(
                    String(value), range: 9...24, locale: english) == .valid(value))
        }
    }

    @Test("Out-of-range input is retained without clamping or changing the last valid draft")
    func outOfRangeRetainsDraft() {
        var drafts = AppearanceNumericDrafts()
        var bodySize = 14.0
        for text in ["8.99", "24.01", "999", "-1"] {
            if let accepted = drafts.update(text, for: .bodyFontSize, range: 9...24, locale: english) {
                bodySize = accepted
            }
            #expect(bodySize == 14)
            #expect(drafts.text(for: .bodyFontSize) == text)
            #expect(drafts.validation(for: .bodyFontSize) == .outOfRange)
            #expect(drafts.hasInvalidInput)
        }
        #expect(
            AppearanceNumericValidation.parse(
                "701", range: 400...700, isInteger: true, locale: english) == .outOfRange)
    }

    @Test("Empty and intermediate edits remain invalid until a complete number is entered")
    func incompleteInput() {
        for text in ["", "  ", "\n"] {
            #expect(AppearanceNumericValidation.parse(text, range: 0...4, locale: english) == .empty)
        }
        for text in ["-", "+", ".", "1.", "1.2pt", "1.2 1.3", "NaN", "Inf"] {
            #expect(
                AppearanceNumericValidation.parse(
                    text, range: 0...4, locale: english) == .invalidNumber)
        }
        // Scanner may report floating-point overflow as infinity or as its
        // finite overflow limit. Neither outcome may authorize a value.
        #expect(AppearanceNumericValidation.parse("1e999", range: 0...4, locale: english).value == nil)
    }

    @Test("Parsing uses the field locale and rejects an unfinished localized decimal")
    func localizedDecimalInput() {
        let german = Locale(identifier: "de_DE")
        #expect(AppearanceNumericValidation.parse("12,5", range: 9...24, locale: german) == .valid(12.5))
        #expect(AppearanceNumericValidation.parse("12.5", range: 9...24, locale: english) == .valid(12.5))
        #expect(AppearanceNumericValidation.parse("12,", range: 9...24, locale: german) == .invalidNumber)
        #expect(AppearanceNumericValidation.parse("12,5", range: 9...24, locale: english) == .invalidNumber)
        #expect(AppearanceNumericValidation.parse("12.5", range: 9...24, locale: german) == .invalidNumber)
        #expect(
            AppearanceNumericValidation.parse(
                "500,5", range: 400...700, isInteger: true, locale: german) == .invalidNumber)
    }

    @Test("Correction keeps exact typed text and clears only that field's invalid state")
    func correctsDraft() {
        var drafts = AppearanceNumericDrafts()
        #expect(drafts.update("999", for: .bodyFontSize, range: 9...24, locale: english) == nil)
        #expect(drafts.update("", for: .headingWeight, range: 400...700, isInteger: true, locale: english) == nil)
        #expect(drafts.update("12.50", for: .bodyFontSize, range: 9...24, locale: english) == 12.5)
        #expect(drafts.text(for: .bodyFontSize) == "12.50")
        #expect(drafts.validation(for: .bodyFontSize) == .valid(12.5))
        #expect(drafts.hasInvalidInput)
        #expect(drafts.update("550", for: .headingWeight, range: 400...700, isInteger: true, locale: english) == 550)
        #expect(!drafts.hasInvalidInput)
    }

    @Test("Adaptive heading presentations share input identity; other fields remain independent")
    func headingFieldIdentity() {
        var drafts = AppearanceNumericDrafts()
        drafts.update(".", for: .headingScale(.h1), range: 0.8...3, locale: english)
        drafts.update("2", for: .headingScale(.h2), range: 0.8...3, locale: english)
        drafts.update("1.25", for: .headingSpaceBefore(.h1), range: 0...4, locale: english)
        #expect(drafts.text(for: .headingScale(.h1)) == ".")
        #expect(drafts.text(for: .headingScale(.h2)) == "2")
        #expect(drafts.text(for: .headingSpaceBefore(.h1)) == "1.25")
        #expect(drafts.hasInvalidInput)
        drafts.update("1.5", for: .headingScale(.h1), range: 0.8...3, locale: english)
        #expect(drafts.text(for: .headingScale(.h1)) == "1.5")
        #expect(!drafts.hasInvalidInput)
    }

    @Test("An explicit step replaces only its field; a draft replacement discards all raw edits")
    func resetsInput() {
        var drafts = AppearanceNumericDrafts()
        drafts.update("", for: .bodyFontSize, range: 9...24, locale: english)
        drafts.update("-", for: .headingScale(.h1), range: 0.8...3, locale: english)
        drafts.clear(.bodyFontSize)
        #expect(drafts.text(for: .bodyFontSize) == nil)
        #expect(drafts.text(for: .headingScale(.h1)) == "-")
        #expect(drafts.hasInvalidInput)
        drafts.reset()
        #expect(drafts.text(for: .headingScale(.h1)) == nil)
        #expect(!drafts.hasInvalidInput)
    }
}
