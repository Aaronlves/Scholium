import Combine
import Foundation

/// One window's native presentations pin its reader controls. Tokens carry no
/// document, command, source, or operation authority.
@MainActor
final class PDFReaderPresentationActivity: ObservableObject {
    struct Token: Hashable {
        fileprivate let id = UUID()
    }

    @Published private(set) var isActive = false
    private var tokens: Set<Token> = []
    private var isInvalidated = false

    func begin() -> Token? {
        guard !isInvalidated else { return nil }
        let token = Token()
        tokens.insert(token)
        if !isActive { isActive = true }
        return token
    }

    func end(_ token: Token) {
        guard tokens.remove(token) != nil else { return }
        if tokens.isEmpty { isActive = false }
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        tokens.removeAll()
        if isActive { isActive = false }
    }
}
