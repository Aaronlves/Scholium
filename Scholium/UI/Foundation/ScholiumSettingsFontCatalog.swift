import Combine
import CoreText
import Foundation

/// One catalogue per retained Appearance page. Only Sendable font names cross
/// the worker boundary; AppKit font objects and settings drafts stay on the UI actor.
@MainActor
final class ScholiumSettingsFontCatalog: ObservableObject {
    typealias Loader = @Sendable () async -> [String]

    @Published private(set) var families: [String] = []
    private var loaded = false
    private var generation = 0
    private var loading: Task<Void, Never>?
    private var observations: Set<AnyCancellable> = []
    private let loader: Loader

    init(
        loader: @escaping Loader = {
            // Core Text returns visible family names already sorted for UI display.
            CTFontManagerCopyAvailableFontFamilyNames() as! [String]
        },
        localNotifications: NotificationCenter = .default,
        distributedNotifications: NotificationCenter = DistributedNotificationCenter.default()
    ) {
        self.loader = loader
        let notification = Notification.Name(kCTFontManagerRegisteredFontsChangedNotification as String)
        for center in [localNotifications, distributedNotifications] {
            center.publisher(for: notification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.invalidate() }
                .store(in: &observations)
        }
    }

    deinit {
        loading?.cancel()
    }

    func loadIfNeeded() async {
        if !loaded, loading == nil { startLoading() }
        // An invalidation during enumeration starts one replacement query. All
        // waiters follow it, rather than returning with an obsolete catalogue.
        while let loading { await loading.value }
    }

    func families(retaining selected: String?, excluding presets: [String] = []) -> [String] {
        let excluded = Set(presets)
        var choices = families.filter { !excluded.contains($0) }
        if let selected, !selected.isEmpty, !excluded.contains(selected), !choices.contains(selected) {
            choices.append(selected)
        }
        return choices
    }

    func invalidate() {
        generation += 1
        loaded = false
        if loading == nil { startLoading() }
    }

    private func startLoading() {
        let requestedGeneration = generation
        let work = Task.detached(priority: .userInitiated, operation: loader)
        loading = Task { [weak self] in
            let names = await work.value
            guard let self, !Task.isCancelled else { return }
            self.loading = nil
            guard requestedGeneration == self.generation else {
                self.startLoading()
                return
            }
            self.families = names
            self.loaded = true
        }
    }
}
