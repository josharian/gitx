//
//  PBSourceViewBadge.swift
//  GitX
//
//  Created by Pieter de Bie on 2/13/10.
//  Copyright 2010 Nathan Kinsinger. All rights reserved.
//

import Cocoa

@objc class PBSourceViewBadge: NSObject {

    @objc static var badgeHighlightColor: NSColor {
        return NSColor(calibratedHue: 0.612, saturation: 0.275, brightness: 0.735, alpha: 1.000)
    }

    @objc static var badgeBackgroundColor: NSColor {
        return NSColor(calibratedWhite: 0.6, alpha: 1.00)
    }

    @objc(badgeColorForCell:)
    static func badgeColor(for cell: NSTextFieldCell) -> NSColor {
        if cell.isHighlighted {
            return .white
        }

        if cell.controlView?.window?.isMainWindow == true {
            return badgeHighlightColor
        }

        return badgeBackgroundColor
    }

    @objc(badgeTextColorForCell:)
    static func badgeTextColor(for cell: NSTextFieldCell) -> NSColor {
        if !cell.isHighlighted {
            return .white
        }

        if cell.controlView?.window?.isKeyWindow != true {
            if cell.controlView?.window?.isMainWindow == true {
                return badgeHighlightColor
            } else {
                return badgeBackgroundColor
            }
        }

        if cell.controlView?.window?.firstResponder == cell.controlView {
            return badgeHighlightColor
        }

        return badgeBackgroundColor
    }

    @objc static var badgeTextAttributes: [NSAttributedString.Key: Any] {
        let centerStyle = NSMutableParagraphStyle()
        centerStyle.alignment = .center

        let fontSize = NSFont.systemFontSize - 2
        let font = NSFont(name: "Helvetica-Bold", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)

        return [
            .font: font,
            .paragraphStyle: centerStyle
        ]
    }

    // MARK: - badges

    @objc(badge:forCell:)
    static func badge(_ badge: String, for cell: NSTextFieldCell) -> NSImage {
        let badgeColor = self.badgeColor(for: cell)

        let textColor = self.badgeTextColor(for: cell)
        var attributes = badgeTextAttributes
        attributes[.foregroundColor] = textColor
        let badgeString = NSAttributedString(string: badge, attributes: attributes)

        let imageHeight = ceil(badgeString.size().height)
        let radius = ceil(imageHeight / 4) * 2
        let minWidth = ceil(radius * 2.5)

        var imageWidth = ceil(badgeString.size().width + radius)
        if imageWidth < minWidth {
            imageWidth = minWidth
        }
        let badgeRect = NSRect(x: 0, y: 0, width: imageWidth, height: imageHeight)

        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: radius, yRadius: radius)

        let badgeImage = NSImage(size: badgeRect.size)
        badgeImage.lockFocus()

        badgeColor.set()
        badgePath.fill()

        badgeString.draw(in: badgeRect)

        badgeImage.unlockFocus()

        return badgeImage
    }

    @objc(checkedOutBadgeForCell:)
    static func checkedOutBadge(for cell: NSTextFieldCell) -> NSImage {
        return badge("✔", for: cell)
    }

    @objc(numericBadge:forCell:)
    static func numericBadge(_ number: Int, for cell: NSTextFieldCell) -> NSImage {
        return badge("\(number)", for: cell)
    }
}