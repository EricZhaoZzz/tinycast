// Standalone test for the clipboard's batch selection and merged text, compiling the real sources.
import Foundation

@main
@MainActor
struct ClipboardSelectionTests {
    static var failures = 0
    static var passes = 0

    static let a = ClipboardItem(text: "alpha", sourceBundleID: nil)
    static let b = ClipboardItem(text: "beta", sourceBundleID: nil)
    static let c = ClipboardItem(text: "gamma", sourceBundleID: nil)
    static let d = ClipboardItem(text: "delta", sourceBundleID: nil)
    static let image = ClipboardItem(imagePath: "/scratch/shot.png", sourceBundleID: nil)
    static let file = ClipboardItem(filePath: "/scratch/report.pdf", sourceBundleID: nil)
    static let order = [a, b, c, d].map(\.id)

    static func main() {
        extendRunsFromTheCursorRow()
        extendKeepsItsAnchorBothWays()
        extendToAnUnknownRowChangesNothing()
        toggleSeedsFromTheCursorRow()
        toggleRemovesAMarkedRow()
        oneMarkIsNotAMultiSelection()
        selectAllTakesEveryRow()
        pruneDropsWhatIsNoLongerListed()
        clearEmptiesTheSelection()
        mergeJoinsTextFilesAndImagesInOrder()
        mergeSkipsWhatHasNothingToWrite()
        mergedActionNeverWithholdsAChord()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func extendRunsFromTheCursorRow() {
        var selection = ClipboardSelection()
        selection.extend(from: a.id, to: c.id, in: order)
        expect(selection.ids == Set([a.id, b.id, c.id]), "⇧↓ twice from the first row marks three rows")
        expect(selection.isMultiple, "three marks are a multi-selection")
    }

    static func extendKeepsItsAnchorBothWays() {
        var selection = ClipboardSelection()
        selection.extend(from: b.id, to: d.id, in: order)
        selection.extend(from: d.id, to: a.id, in: order)
        expect(
            selection.ids == Set([a.id, b.id]),
            "crossing back over the anchor swaps the side, and the anchor row stays marked")
        selection.extend(from: a.id, to: b.id, in: order)
        expect(selection.ids == Set([b.id]), "returning to the anchor leaves just that row")
        expect(!selection.isMultiple, "one mark is not a multi-selection")
    }

    static func extendToAnUnknownRowChangesNothing() {
        var selection = ClipboardSelection()
        selection.extend(from: a.id, to: b.id, in: order)
        selection.extend(from: b.id, to: UUID(), in: order)
        expect(selection.ids == Set([a.id, b.id]), "a target the list does not show is ignored")
    }

    static func toggleSeedsFromTheCursorRow() {
        var selection = ClipboardSelection()
        selection.toggle(c.id, cursor: a.id)
        expect(selection.ids == Set([a.id, c.id]), "⌘-click beside the cursor row makes two")
        selection.extend(from: c.id, to: d.id, in: order)
        expect(
            selection.ids == Set([c.id, d.id]),
            "a ⇧ extension after a ⌘-click runs from the clicked row")
    }

    static func toggleRemovesAMarkedRow() {
        var selection = ClipboardSelection()
        selection.selectAll(in: order)
        selection.toggle(b.id, cursor: a.id)
        expect(selection.ids == Set([a.id, c.id, d.id]), "⌘-click on a marked row unmarks it")
    }

    static func oneMarkIsNotAMultiSelection() {
        var selection = ClipboardSelection()
        selection.toggle(a.id, cursor: nil)
        expect(!selection.isMultiple, "a lone toggled row stays the single path")
    }

    static func selectAllTakesEveryRow() {
        var selection = ClipboardSelection()
        selection.selectAll(in: order)
        expect(selection.ids == Set(order), "⌘A marks every listed row")
    }

    static func pruneDropsWhatIsNoLongerListed() {
        var selection = ClipboardSelection()
        selection.selectAll(in: order)
        selection.prune(to: [b.id, c.id])
        expect(selection.ids == Set([b.id, c.id]), "a deleted or filtered-out row leaves no mark")
        expect(selection.anchor == nil, "the anchor goes with its row")
    }

    static func clearEmptiesTheSelection() {
        var selection = ClipboardSelection()
        selection.selectAll(in: order)
        selection.clear()
        expect(selection == ClipboardSelection(), "clear returns to the empty selection")
    }

    static func mergeJoinsTextFilesAndImagesInOrder() {
        let text = ClipboardMerge.text(of: [a, file, image, b])
        expect(
            text == "alpha\n/scratch/report.pdf\n/scratch/shot.png\nbeta",
            "text as it is, a file and an image by path, in list order")
    }

    static func mergeSkipsWhatHasNothingToWrite() {
        expect(ClipboardMerge.text(of: []) == "", "an empty selection merges to nothing")
        expect(ClipboardMerge.text(of: [a]) == "alpha", "one entry merges to itself")
    }

    static func mergedActionNeverWithholdsAChord() {
        for chord in ClipboardChord.allCases {
            expect(
                ClipboardDefaultAction.pastePlainText.mergedAction(for: chord) != .pastePlainText,
                "merged text has no plain-text action of its own")
        }
        expect(
            ClipboardDefaultAction.copy.mergedAction(for: .return) == .copy,
            "a Copy default copies the merged text on ↵")
        expect(
            ClipboardDefaultAction.copy.mergedAction(for: .command) == .paste,
            "and pastes it on ⌘↵")
        expect(
            ClipboardDefaultAction.paste.mergedAction(for: .command) == .copy,
            "a Paste default copies the merged text on ⌘↵")
    }

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            print("FAIL: \(label)")
            failures += 1
        }
    }
}
