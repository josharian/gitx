import Cocoa

@objcMembers
@objc(PBFileChangesTableView)
final class PBFileChangesTableView: NSTableView {
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let controller = delegate as? PBGitIndexController else { return nil }
        let eventLocation = convert(event.locationInWindow, from: nil)
        let rowIndex = row(at: eventLocation)
        guard rowIndex >= 0 else { return nil }

        selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: true)
        return controller.menu(forTable: self)
    }

    override func keyDown(with event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            super.keyDown(with: event)
            return
        }

        let isUnstagedView = tag == 0
        let commandDown = event.modifierFlags.contains(.command)

        if characters == "s" && commandDown && isUnstagedView {
            stageSelectedFiles()
        } else if characters == "u" && commandDown && !isUnstagedView {
            unstageSelectedFiles()
        } else {
            super.keyDown(with: event)
        }
    }

    private func stageSelectedFiles() {
        let previousRow = selectedRow
        (delegate as? PBGitIndexController)?.stageSelectedFiles()
        selectNextRow(preservingPrevious: previousRow)
    }

    private func unstageSelectedFiles() {
        let previousRow = selectedRow
        (delegate as? PBGitIndexController)?.unstageSelectedFiles()
        selectNextRow(preservingPrevious: previousRow)
    }

    private func selectNextRow(preservingPrevious previousRow: Int) {
        guard numberOfRows > 0 else {
            deselectAll(nil)
            return
        }

        let rowToSelect = min(previousRow, numberOfRows - 1)
        selectRowIndexes(IndexSet(integer: rowToSelect), byExtendingSelection: false)
    }
}
