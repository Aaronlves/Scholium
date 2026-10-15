import Foundation
import Testing

@testable import ScholiumApp

@Suite("Exact App source bytes")
struct ScholiumExactUTF8Tests {
    @Test("Contiguous comparison agrees with UTF-8 units for native and Cocoa-bridged Strings")
    func sourceBytesAcrossStringRepresentations() {
        let cases: [(String, String)] = [
            ("", ""), ("", "a"), ("small", "small"), ("same-length-A", "same-length-B"),
            ("Café", "Cafe\u{301}"), ("A\u{0}B", "A\u{0}C"), ("中文😀👨‍👩‍👧‍👦", "中文😀👨‍👩‍👧‍👦"),
            ("line\r\nnext", "line\nnext"),
            (String(repeating: "Synthetic e\u{301} 中文😀 ", count: 1_024), String(repeating: "Synthetic e\u{301} 中文😀 ", count: 1_024)),
        ]
        for (lhs, rhs) in cases {
            let exact = lhs.utf8.elementsEqual(rhs.utf8)
            #expect(ScholiumExactUTF8.equal(lhs, rhs) == exact)
            let leftUnits = Array(lhs.utf16)
            let rightUnits = Array(rhs.utf16)
            let bridgedLeft = leftUnits.withUnsafeBufferPointer { units in
                guard let address = units.baseAddress else { return "" }
                return NSString(characters: address, length: units.count) as String
            }
            let bridgedRight = rightUnits.withUnsafeBufferPointer { units in
                guard let address = units.baseAddress else { return "" }
                return NSString(characters: address, length: units.count) as String
            }
            #expect(ScholiumExactUTF8.equal(bridgedLeft, bridgedRight) == exact)
            #expect(bridgedLeft.utf8.elementsEqual(lhs.utf8) && bridgedRight.utf8.elementsEqual(rhs.utf8))
        }
    }
}
