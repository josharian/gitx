import Cocoa

@objcMembers
@objc(OpenRecentController)
final class OpenRecentController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSControlTextEditingDelegate {
    @IBOutlet private weak var searchField: NSSearchField!
    @IBOutlet private weak var resultViewer: NSTableView!

    @objc dynamic private(set) var currentResults: [NSURL] = []
    @objc dynamic private(set) var possibleResults: [NSURL] = []
    private var selectedResult: NSURL?

    override var windowNibName: NSNib.Name? {
        "OpenRecentPopup"
    }

    override init(window: NSWindow?) {
        super.init(window: window)
        rebuildPossibleResults()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        rebuildPossibleResults()
    }

    convenience init() {
        self.init(window: nil)
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        resultViewer.target = self
        resultViewer.doubleAction = #selector(tableDoubleClick(_:))
    }

    @objc func show() {
        ensureWindowLoaded()
        rebuildPossibleResults()
        performSearch(query: searchField?.stringValue ?? "")
        window?.makeKeyAndOrderFront(self)
    }

    @objc func hide() {
        window?.orderOut(self)
    }

    @IBAction func doSearch(_ sender: Any?) {
        performSearch(query: searchField?.stringValue ?? "")
    }

    @IBAction func changeSelection(_ sender: Any?) {
        updateSelectedResult(at: resultViewer.selectedRow)
    }

    @IBAction func tableDoubleClick(_ sender: Any?) {
        changeSelection(sender)
        guard let result = selectedResult as URL? else { return }
        NSDocumentController.shared.openDocument(withContentsOf: result, display: true) { _, _, _ in }
        hide()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        currentResults.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row >= 0 && row < currentResults.count else { return nil }
        let url = currentResults[row]
        switch tableColumn?.identifier.rawValue {
        case "icon":
            let values = try? url.resourceValues(forKeys: [.effectiveIconKey])
            return values?[.effectiveIconKey]
        case "label":
            return url.lastPathComponent
        default:
            return nil
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            tableDoubleClick(control)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(offset: -1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(offset: 1)
            return true
        default:
            return false
        }
    }

    private func ensureWindowLoaded() {
        if window == nil {
            _ = self.window
        }
    }

    private func rebuildPossibleResults() {
        possibleResults = NSDocumentController.shared.recentDocumentURLs.map { $0 as NSURL }
    }

    private func performSearch(query rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            currentResults = possibleResults
        } else {
            currentResults = possibleResults.filter { url in
                guard let name = url.lastPathComponent else { return false }
                return name.range(of: query, options: .caseInsensitive) != nil
            }
        }

        resultViewer.reloadData()

        if currentResults.isEmpty {
            selectedResult = nil
            resultViewer.deselectAll(self)
        } else {
            resultViewer.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            resultViewer.scrollRowToVisible(0)
            selectedResult = currentResults.first
        }
    }

    private func updateSelectedResult(at index: Int) {
        if index >= 0 && index < currentResults.count {
            selectedResult = currentResults[index]
        } else {
            selectedResult = nil
        }
    }

    private func moveSelection(offset: Int) {
        guard !currentResults.isEmpty else { return }
        let currentIndex = resultViewer.selectedRow
        var next = currentIndex == -1 ? (offset > 0 ? 0 : currentResults.count - 1) : currentIndex + offset
        next = max(0, min(currentResults.count - 1, next))
        resultViewer.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        resultViewer.scrollRowToVisible(next)
        updateSelectedResult(at: next)
    }
}
