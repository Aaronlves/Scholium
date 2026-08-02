import Foundation
import ScholiumContracts

struct SidebarRemovalFocusPlan: Equatable {
    let originDocumentID: VaultQualifiedNoteID
    let disclosureScope: LibraryDisclosureScope?
    let successorPath: String?
}

enum SidebarRemovalFocusDestination: Equatable {
    case row(String)
    case locationPicker
}

struct SidebarRemovalFocusReconciliation: Equatable {
    let pendingPlans: [SidebarRemovalFocusPlan]
    let destination: SidebarRemovalFocusDestination?
}

func sidebarRemovalFocusPlan(
    originDocumentID: VaultQualifiedNoteID,
    originPath: String,
    disclosureScope: LibraryDisclosureScope?,
    visibleNotePaths: [String]
) -> SidebarRemovalFocusPlan {
    guard let index = visibleNotePaths.firstIndex(of: originPath) else {
        return SidebarRemovalFocusPlan(
            originDocumentID: originDocumentID,
            disclosureScope: disclosureScope,
            successorPath: nil
        )
    }
    let successor: String? = if visibleNotePaths.indices.contains(index + 1) {
        visibleNotePaths[index + 1]
    } else if index > visibleNotePaths.startIndex {
        visibleNotePaths[index - 1]
    } else {
        nil
    }
    return SidebarRemovalFocusPlan(
        originDocumentID: originDocumentID,
        disclosureScope: disclosureScope,
        successorPath: successor
    )
}

/// Reconciles every in-flight row removal after a category projection changes.
/// Plans from another Scope/Location are discarded. When several removals
/// commit together, the most recently invoked completed action determines the
/// single native focus destination; still-present origins retain their plans.
func sidebarRemovalFocusAfterCompletions(
    plans: [SidebarRemovalFocusPlan],
    disclosureScope: LibraryDisclosureScope?,
    remainingDocumentIDs: Set<VaultQualifiedNoteID>,
    remainingVisibleNotePaths: [String]
) -> SidebarRemovalFocusReconciliation {
    let currentPlans = plans.filter { $0.disclosureScope == disclosureScope }
    let completedPlans = currentPlans.filter {
        !remainingDocumentIDs.contains($0.originDocumentID)
    }
    let pendingPlans = currentPlans.filter {
        remainingDocumentIDs.contains($0.originDocumentID)
    }
    guard let completed = completedPlans.last else {
        return SidebarRemovalFocusReconciliation(
            pendingPlans: pendingPlans,
            destination: nil
        )
    }

    let remainingPaths = Set(remainingVisibleNotePaths)
    if let successor = completed.successorPath,
       remainingPaths.contains(successor) {
        return SidebarRemovalFocusReconciliation(
            pendingPlans: pendingPlans,
            destination: .row(successor)
        )
    }
    if let first = remainingVisibleNotePaths.first {
        return SidebarRemovalFocusReconciliation(
            pendingPlans: pendingPlans,
            destination: .row(first)
        )
    }
    return SidebarRemovalFocusReconciliation(
        pendingPlans: pendingPlans,
        destination: .locationPicker
    )
}

/// Removes only the failed operation's plan. Another in-flight lifecycle
/// command keeps its independent restoration contract.
func sidebarRemovalFocusAfterFailure(
    plans: [SidebarRemovalFocusPlan],
    originDocumentID: VaultQualifiedNoteID,
    originPath: String,
    disclosureScope: LibraryDisclosureScope?
) -> SidebarRemovalFocusReconciliation {
    guard let index = plans.lastIndex(where: {
        $0.originDocumentID == originDocumentID
    }) else {
        return SidebarRemovalFocusReconciliation(
            pendingPlans: plans,
            destination: nil
        )
    }
    var pendingPlans = plans
    let failed = pendingPlans.remove(at: index)
    let destination: SidebarRemovalFocusDestination? =
        failed.disclosureScope == disclosureScope ? .row(originPath) : nil
    return SidebarRemovalFocusReconciliation(
        pendingPlans: pendingPlans,
        destination: destination
    )
}
