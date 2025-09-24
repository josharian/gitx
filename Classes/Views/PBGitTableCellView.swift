import Cocoa

@objcMembers
@objc(PBGitTableCellView)
final class PBGitTableCellView: NSTableCellView {
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            applyTextColor(for: backgroundStyle)
        }
    }

    private func applyTextColor(for style: NSView.BackgroundStyle) {
        if style == .emphasized || style == .dark {
            textField?.textColor = .white
        } else {
            textField?.textColor = .controlTextColor
            // SHA columns keep their monospaced font; nothing else to do here.
        }
    }
}
