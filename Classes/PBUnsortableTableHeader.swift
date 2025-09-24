import Cocoa

@objcMembers
@objc(PBUnsortableTableHeader)
final class PBUnsortableTableHeader: NSTableHeaderView {
    override func mouseDown(with event: NSEvent) {
        // Intentionally ignore mouse events to prevent sort toggles
    }
}
