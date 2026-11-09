import AppKit
import SwiftUI

struct ClipboardScreen: PaletteScreen {
    let store: ClipboardStore
    let core: AppCore
    let vm: PaletteState

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }
    let openActions: () -> Void
    let scrollToFollow: () -> Void

    var rows: [ClipboardItem] { store.search(vm.query, filter: vm.clipboardFilter) }

    var landingSelection: Int { store.landingIndex(in: vm.query, filter: vm.clipboardFilter) }

    /// The batch selection as it is listed now; empty unless two or more of its rows are still shown.
    private var marked: [ClipboardItem] {
        let selection = vm.clipboardSelection
        guard selection.isMultiple else { return [] }
        let marked = rows.filter { selection.contains($0.id) }
        return marked.count >= 2 ? marked : []
    }

    var primaryActionTitle: String {
        let defaultAction = core.settings.clipboardDefaultAction
        let marked = marked
        if !marked.isEmpty {
            return ClipboardActionsMenu.mergedTitle(
                defaultAction.mergedAction(for: .return), count: marked.count, target: vm.pasteTarget)
        }
        let action = item(at: vm.selection).flatMap { defaultAction.action(for: .return, on: $0) }
        return (action ?? defaultAction).title(pastingInto: vm.pasteTarget)
    }

    private func item(at selection: Int) -> ClipboardItem? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let item = item(at: selection) else { return nil }
        let marked = marked
        if !marked.isEmpty {
            return ClipboardActionsMenu.content(
                marked: marked, cursor: item, core: core, target: vm.pasteTarget)
        }
        return ClipboardActionsMenu.content(
            item: item, core: core, store: store, target: vm.pasteTarget)
    }

    func activate(at selection: Int) {
        let marked = marked
        if !marked.isEmpty { return core.clipboardCoordinator.activate(merging: marked) }
        guard let item = item(at: selection) else { return }
        core.clipboardCoordinator.activate(item)
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        let marked = marked
        switch shortcut {
        case .commandDelete, .delete:
            if !marked.isEmpty {
                Task { await core.clipboardCoordinator.deleteClips(marked) }
                return true
            }
            delete(at: selection)
            return true
        case .deleteAll:
            deleteAll()
            return true
        case .pin:
            if !marked.isEmpty, let cursor = item(at: selection) {
                core.clipboardCoordinator.togglePinnedClips(marked, cursor: cursor)
                return true
            }
            return pin(at: selection)
        case .favoriteSlot(let index):
            vm.clipboardSelection.clear()
            return activatePinned(at: index)
        case .selectAll:
            // With text in the field ⌘A belongs to the field, and so does it while a menu is open.
            guard vm.query.isEmpty, !vm.menuOpen, !vm.isComposing else { return false }
            vm.clipboardSelection.selectAll(in: rows.map(\.id))
            return true
        case .copyText:
            guard marked.isEmpty, let item = item(at: selection), item.offersTextExtraction else { return false }
            core.clipboardCoordinator.copyImageText(item)
            return true
        case .showInFinder:
            guard marked.isEmpty, let item = item(at: selection), item.kind != .text else {
                return false
            }
            core.clipboardCoordinator.revealClip(item)
            return true
        case .edit:
            guard marked.isEmpty, let item = item(at: selection), item.kind == .text else {
                return false
            }
            Task { await core.clipboardCoordinator.editClip(item) }
            return true
        default: return false
        }
    }

    private func activatePinned(at index: Int) -> Bool {
        guard let item = store.pinnedItem(at: index, in: vm.query, filter: vm.clipboardFilter) else {
            return false
        }
        core.clipboardCoordinator.activate(item)
        return true
    }

    /// ⌘↵ — the action ↵ is not set to.
    func secondary(at selection: Int) -> Bool {
        let marked = marked
        if !marked.isEmpty {
            core.clipboardCoordinator.activate(merging: marked, chord: .command)
            return true
        }
        guard let item = item(at: selection) else { return false }
        return core.clipboardCoordinator.activate(item, chord: .command)
    }

    /// ⌃⌘↵ — Paste as Plain Text, or Paste while that is the default.
    func tertiary(at selection: Int) -> Bool {
        let marked = marked
        if !marked.isEmpty {
            core.clipboardCoordinator.activate(merging: marked, chord: .controlCommand)
            return true
        }
        guard let item = item(at: selection) else { return false }
        return core.clipboardCoordinator.activate(item, chord: .controlCommand)
    }

    /// ⌥↵ — the palette stays up, so a run of entries goes over without re-summoning it.
    func pasteKeepingWindowOpen(at selection: Int) -> Bool {
        let marked = marked
        if !marked.isEmpty {
            core.clipboardCoordinator.pasteKeepingWindowOpen(merging: marked)
            return true
        }
        guard let item = item(at: selection) else { return false }
        core.clipboardCoordinator.pasteKeepingWindowOpen(item)
        return true
    }

    private func pin(at selection: Int) -> Bool {
        guard let item = item(at: selection) else { return false }
        core.clipboardCoordinator.togglePinnedClip(item)
        return true
    }

    /// ⌘⌫ / ⌃X — the screen owns the chord whether or not a row sits under the selection.
    private func delete(at selection: Int) {
        guard let item = item(at: selection) else { return }
        store.remove(item)
    }

    /// ⌃⇧X — mirrors the Actions row, confirmation included; pinned entries go with the rest.
    private func deleteAll() {
        Task { await core.clipboardCoordinator.deleteAllClips() }
    }

    /// A plain arrow collapses a batch selection to the row it lands on, as in Finder.
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? {
        if axis == .vertical { vm.clipboardSelection.clear() }
        return nil
    }

    func extendSelection(_ delta: Int, from selection: Int) -> Int? {
        let rows = rows
        guard let cursor = item(at: selection) else { return nil }
        let target = min(max(selection + delta, 0), rows.count - 1)
        vm.clipboardSelection.extend(from: cursor.id, to: rows[target].id, in: rows.map(\.id))
        return target
    }

    /// ⇧ extends from the anchor to the row, ⌘ flips it, and a bare click goes back to one row.
    private func select(_ item: ClipboardItem, modifiers: NSEvent.ModifierFlags, in rows: [ClipboardItem]) {
        let cursor = self.item(at: vm.selection)?.id
        if modifiers.contains(.shift), let cursor {
            vm.clipboardSelection.extend(from: cursor, to: item.id, in: rows.map(\.id))
        } else if modifiers.contains(.command) {
            vm.clipboardSelection.toggle(item.id, cursor: cursor)
        } else {
            vm.clipboardSelection.clear()
        }
        vm.selection = rows.firstIndex(of: item) ?? 0
    }

    /// Follow a row the store moved; with a query typed the highlight stays put.
    private func follow(from old: ClipFollowKey, to new: ClipFollowKey) {
        // A nil `old.id` is the first load landing, not a row that moved.
        guard old.id != nil else { return }
        let rows = rows
        if vm.query.trimmingCharacters(in: .whitespaces).isEmpty, old.id != new.id, let id = new.id,
            let index = rows.firstIndex(where: { $0.id == id })
        {
            vm.selection = index
        }
        scrollToFollow()
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            content(selection: selection, scroll: scroll)
                .onChange(of: ClipFollowKey(id: store.items.first?.id, token: vm.followToken)) {
                    old, new in
                    follow(from: old, to: new)
                }
        )
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        // Empty history: centre one message across the panel, not in the list column.
        if rows.isEmpty {
            // Names the filter, so one hiding every entry doesn't read as an empty history.
            EmptyResults(text: vm.clipboardFilter.emptyMessage)
        } else {
            let selected = item(at: selection)
            let marked = marked
            HStack(spacing: 0) {
                ClipboardList(
                    results: rows,
                    selectedID: selected?.id,
                    markedIDs: Set(marked.map(\.id)),
                    scroll: scroll,
                    onSelect: { item, modifiers in select(item, modifiers: modifiers, in: rows) },
                    onActivate: { activate(at: vm.selection) },
                    onActions: { item in
                        // A right-click inside the batch acts on the batch; elsewhere it starts over.
                        if !vm.clipboardSelection.contains(item.id) { vm.clipboardSelection.clear() }
                        if let index = rows.firstIndex(of: item) { vm.selection = index }
                        openActions()
                    },
                    onDragPayload: { core.clipboardCoordinator.dragPayload(for: $0) },
                    onDropped: { core.paletteCoordinator.dragLanded() }
                )
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(width: 1)
                ClipboardPreview(item: selected, marked: marked)
            }
        }
    }
}

/// Change key for the follow-the-moved-row handler, read from the store, not the results.
private struct ClipFollowKey: Equatable {
    let id: ClipboardItem.ID?
    let token: UUID
}

@MainActor
enum ClipboardActionsMenu {
    /// The ⌘K rows for a batch selection: only what makes sense for every entry at once.
    static func content(
        marked: [ClipboardItem], cursor: ClipboardItem, core: AppCore, target: PasteTarget?
    ) -> PopoverMenuContent {
        let defaultAction = core.settings.clipboardDefaultAction
        let count = marked.count
        // Plain paste folds into paste for merged text, so each action is listed once, at its first chord.
        var listed: Set<ClipboardDefaultAction> = []
        var items: [PopoverMenuItem] = ClipboardChord.allCases.compactMap { chord in
            let action = defaultAction.mergedAction(for: chord)
            guard listed.insert(action).inserted else { return nil }
            return PopoverMenuItem(
                title: mergedTitle(action, count: count, target: target),
                icon: action == .copy ? .symbol("doc.on.doc") : .paste(target, fallback: "doc.on.clipboard"),
                shortcut: chord.label
            ) {
                core.clipboardCoordinator.activate(merging: marked, chord: chord)
            }
        }
        let unpin = marked.allSatisfy(\.isPinned)
        items.append(
            PopoverMenuItem(
                title: unpin ? String(localized: "Unpin Entries") : String(localized: "Pin Entries"),
                systemImage: unpin ? "pin.slash" : "pin", startsSection: true, shortcut: "⌘."
            ) {
                core.clipboardCoordinator.togglePinnedClips(marked, cursor: cursor)
            })
        items.append(
            PopoverMenuItem(
                title: String(localized: "Delete Entries"), systemImage: "trash", startsSection: true,
                shortcut: "⌃X", isDestructive: true
            ) {
                Task { await core.clipboardCoordinator.deleteClips(marked) }
            })
        return PopoverMenuContent(header: String(localized: "\(count) entries"), items: items)
    }

    static func mergedTitle(_ action: ClipboardDefaultAction, count: Int, target: PasteTarget?) -> String {
        switch action {
        case .copy: String(localized: "Copy \(count) Entries")
        default:
            target.map { String(localized: "Paste \(count) Entries to \($0.name)") }
                ?? String(localized: "Paste \(count) Entries")
        }
    }

    static func content(
        item: ClipboardItem, core: AppCore, store: ClipboardStore, target: PasteTarget?
    ) -> PopoverMenuContent {
        let defaultAction = core.settings.clipboardDefaultAction
        // Chord order puts the default first, beside the ↵ it answers.
        var items: [PopoverMenuItem] = ClipboardChord.allCases.compactMap { chord in
            defaultAction.action(for: chord, on: item).map { action in
                PopoverMenuItem(
                    title: action.title(pastingInto: target), icon: icon(for: action, target: target),
                    shortcut: chord.label
                ) {
                    core.clipboardCoordinator.perform(action, on: item)
                }
            }
        }
        items.append(
            PopoverMenuItem(
                title: String(localized: "Paste and Keep Window Open"),
                icon: .paste(target, fallback: "macwindow"),
                shortcut: "⌥↵"
            ) {
                core.clipboardCoordinator.pasteKeepingWindowOpen(item)
            })
        if item.kind == .text {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Edit Entry"), systemImage: "pencil", startsSection: true,
                    shortcut: "⌘E"
                ) {
                    Task { await core.clipboardCoordinator.editClip(item) }
                })
        }
        items.append(
            PopoverMenuItem(
                title: item.isPinned ? String(localized: "Unpin Entry") : String(localized: "Pin Entry"),
                systemImage: item.isPinned ? "pin.slash" : "pin", startsSection: item.kind != .text,
                shortcut: "⌘."
            ) {
                core.clipboardCoordinator.togglePinnedClip(item)
            })
        if item.offersTextExtraction {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Copy Text"), systemImage: "doc.text.viewfinder",
                    shortcut: "⇧⌘T"
                ) {
                    core.clipboardCoordinator.copyImageText(item)
                })
        }
        if item.kind != .text {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Show in Finder"), systemImage: "folder", shortcut: "⌘F"
                ) {
                    core.clipboardCoordinator.revealClip(item)
                })
        }
        if item.kind == .file {
            items.append(
                PopoverMenuItem(title: String(localized: "Open"), systemImage: "arrow.up.forward.app") {
                    core.clipboardCoordinator.openClip(item)
                })
            items.append(
                PopoverMenuItem(title: String(localized: "Copy Path"), systemImage: "doc.on.clipboard") {
                    core.clipboardCoordinator.copyClipPath(item)
                })
        }
        items.append(
            PopoverMenuItem(
                title: String(localized: "Delete Entry"), systemImage: "trash", startsSection: true,
                shortcut: "⌃X", isDestructive: true
            ) {
                store.remove(item)
            })
        items.append(
            PopoverMenuItem(
                title: String(localized: "Delete All Entries"), systemImage: "trash", shortcut: "⌃⇧X",
                isDestructive: true
            ) {
                Task { await core.clipboardCoordinator.deleteAllClips() }
            })
        return PopoverMenuContent(header: headerText(item), items: items)
    }

    private static func icon(
        for action: ClipboardDefaultAction, target: PasteTarget?
    ) -> PopoverMenuIcon {
        switch action {
        case .paste: .paste(target, fallback: "doc.on.clipboard")
        case .copy: .symbol("doc.on.doc")
        case .pastePlainText: .paste(target, fallback: "doc.plaintext")
        }
    }

    private static func headerText(_ item: ClipboardItem) -> String {
        switch item.kind {
        case .text:
            // Collapse whitespace so a multi-line copy stays a clean one-line title.
            let oneLine = (item.text ?? "").split(whereSeparator: \.isWhitespace).joined(
                separator: " ")
            return String(oneLine.prefix(40))
        case .image: return String(localized: "Image")
        case .file: return (item.filePath as NSString?)?.lastPathComponent ?? String(localized: "File")
        }
    }
}

extension ClipboardDefaultAction {
    func title(pastingInto target: PasteTarget?) -> String {
        guard let target else { return title }
        switch self {
        case .paste: return String(localized: "Paste to \(target.name)")
        case .copy: return title
        case .pastePlainText: return String(localized: "Paste as Plain Text to \(target.name)")
        }
    }
}
