import AppKit
import Combine
import SwiftUI
import Testing

@testable import ScholiumApp

#if DEBUG
    @Suite("Workspace scene ownership", .serialized)
    @MainActor
    struct ScholiumWindowSceneOwnershipTests {
        private final class Revision: ObservableObject {
            @Published var value = 0
            var renderedValues: [Int] = []

            func recordBody() {
                renderedValues.append(value)
            }
        }

        private final class WeakModel {
            weak var value: WindowModel?
            init(_ value: WindowModel) { self.value = value }
        }

        private final class Observation {
            var constructed: [WeakModel] = []
            var renderedPairs: [(ObjectIdentifier, ObjectIdentifier)] = []
            var identitiesAreCoherent = true
        }

        private struct ReevaluatingRoot: View {
            @ObservedObject var revision: Revision
            let workspaceStore: WorkspaceStore
            let route: TriptychWindowRoute
            let alternateTriptychID: UUID
            let lifecycleRegistry: ScholiumWindowLifecycleRegistry

            var body: some View {
                let _ = revision.recordBody()
                let projectedRoute = TriptychWindowRoute(
                    windowID: route.windowID,
                    triptychID: revision.value.isMultiple(of: 2)
                        ? route.triptychID : alternateTriptychID,
                    initialDocument: route.initialDocument
                )
                ScholiumWindowRoot(
                    workspaceStore: workspaceStore,
                    route: projectedRoute,
                    lifecycleRegistry: lifecycleRegistry
                )
            }
        }

        @Test("Reevaluating a mounted workspace root creates one coherent owner pair and preserves observation")
        func mountedRootReevaluationRetainsOneOwnerPair() async throws {
            _ = NSApplication.shared
            let route = TriptychWindowRoute()
            let revision = Revision()
            let observation = Observation()
            ScholiumWindowRoot.qaSceneEvent = { event in
                switch event {
                case .constructed(let model):
                    guard model.nativeWindowID == route.windowID else { return }
                    observation.constructed.append(WeakModel(model))
                case .observed(let model, let coordinator):
                    guard model.nativeWindowID == route.windowID else { return }
                    observation.renderedPairs.append(
                        (
                            ObjectIdentifier(model), ObjectIdentifier(coordinator)
                        ))
                    observation.identitiesAreCoherent =
                        observation.identitiesAreCoherent
                        && model.nativeWindowCoordinator === coordinator
                        && coordinator.windowID == route.windowID
                }
            }
            defer { ScholiumWindowRoot.qaSceneEvent = nil }

            let lifecycleRegistry = ScholiumWindowLifecycleRegistry()
            let root = ReevaluatingRoot(
                revision: revision,
                workspaceStore: makeTestWorkspaceStore(),
                route: route,
                alternateTriptychID: UUID(),
                lifecycleRegistry: lifecycleRegistry
            )
            let host = NSHostingView(rootView: root)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            defer {
                window.orderOut(nil)
                window.contentView = nil
                window.close()
            }
            window.contentView = host
            window.orderFrontRegardless()

            func waitForRender(after count: Int) async throws {
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                while observation.renderedPairs.count <= count,
                    ContinuousClock.now < deadline
                {
                    try await Task.sleep(for: .milliseconds(20))
                }
                _ = try #require(observation.renderedPairs.count > count)
            }

            try await waitForRender(after: 0)
            for nextRevision in 1...3 {
                revision.value = nextRevision
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                while !revision.renderedValues.contains(nextRevision),
                    ContinuousClock.now < deadline
                {
                    try await Task.sleep(for: .milliseconds(20))
                }
                #expect(revision.renderedValues.contains(nextRevision))
            }
            #expect(observation.constructed.count == 1)
            #expect(Set(observation.renderedPairs.map(\.0)).count == 1)
            #expect(Set(observation.renderedPairs.map(\.1)).count == 1)
            #expect(observation.identitiesAreCoherent)

            let renderedModelID = try #require(observation.renderedPairs.first?.0)
            let activeModel = try #require(
                observation.constructed.compactMap(\.value).first {
                    ObjectIdentifier($0) == renderedModelID
                })
            let previousRenders = observation.renderedPairs.count
            activeModel.noteExportPreparationInProgress.toggle()
            try await waitForRender(after: previousRenders)
            #expect(observation.constructed.count == 1)
            #expect(observation.identitiesAreCoherent)
        }
    }
#endif
