import Foundation

/// The entries a batch action covers, kept by id so a row that moves keeps its mark.
struct ClipboardSelection: Equatable, Sendable {
    private(set) var ids: Set<UUID> = []
    /// The end a Shift-extension keeps fixed while the other end moves.
    private(set) var anchor: UUID?

    /// One mark is just the cursor row, which the single-selection path already handles.
    var isMultiple: Bool { ids.count >= 2 }

    func contains(_ id: UUID) -> Bool { ids.contains(id) }

    mutating func clear() {
        ids = []
        anchor = nil
    }

    /// The closed run between the anchor and `target`; the cursor row seeds the anchor.
    mutating func extend(from cursor: UUID, to target: UUID, in order: [UUID]) {
        let start = anchor ?? cursor
        guard let from = order.firstIndex(of: start), let to = order.firstIndex(of: target) else {
            return
        }
        anchor = start
        ids = Set(order[min(from, to)...max(from, to)])
    }

    /// An empty selection first takes the cursor row, so ⌘-clicking a second row makes two.
    mutating func toggle(_ id: UUID, cursor: UUID?) {
        if ids.isEmpty, let cursor { ids.insert(cursor) }
        if !ids.insert(id).inserted { ids.remove(id) }
        anchor = id
    }

    mutating func selectAll(in order: [UUID]) {
        ids = Set(order)
        anchor = order.first
    }

    /// Drops what the list no longer shows, so a deleted or filtered-out row leaves no mark.
    mutating func prune(to order: [UUID]) {
        ids.formIntersection(order)
        if let anchor, !ids.contains(anchor) { self.anchor = nil }
    }
}
