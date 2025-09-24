import AppKit

@objc extension NSBezierPath {
    @objc(bezierPathWithRoundedRect:cornerRadius:)
    class func bezierPathWithRoundedRect(_ rect: NSRect, cornerRadius: Double) -> NSBezierPath {
        let maximumRadius = Double(min(rect.width, rect.height) / 2.0)
        let clampedRadius = max(0.0, min(cornerRadius, maximumRadius))

        if clampedRadius == 0 {
            return NSBezierPath(rect: rect)
        }

        return NSBezierPath(
            roundedRect: rect,
            xRadius: CGFloat(clampedRadius),
            yRadius: CGFloat(clampedRadius)
        )
    }
}
