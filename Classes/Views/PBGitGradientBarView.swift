import Cocoa

@objcMembers
@objc(PBGitGradientBarView)
final class PBGitGradientBarView: NSView {
    private var gradient: NSGradient?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureDefaultGradient()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureDefaultGradient()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        gradient?.draw(in: bounds, angle: 90)
    }

    func setTopShade(_ topShade: CGFloat, bottomShade: CGFloat) {
        let topColor = NSColor(calibratedWhite: topShade, alpha: 1)
        let bottomColor = NSColor(calibratedWhite: bottomShade, alpha: 1)
        setTopColor(topColor, bottomColor: bottomColor)
    }

    func setTopColor(_ topColor: NSColor?, bottomColor: NSColor?) {
        guard let topColor, let bottomColor else { return }
        gradient = NSGradient(starting: bottomColor, ending: topColor)
        needsDisplay = true
    }

    private func configureDefaultGradient() {
        setTopShade(1, bottomShade: 0)
    }
}
