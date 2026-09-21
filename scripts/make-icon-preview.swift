#!/usr/bin/env swift
// Renders the 1024 px master the flat `.icns` inside the bundle is rasterised from.
//
//   swift scripts/make-icon-preview.swift <out.png>
//
// **This is a placeholder.** The real icon of an app of this family comes out of Icon Composer, which
// exports both `Resources/AppIcon.icon` and this master; until somebody draws one, both are generated from
// the same three-bar mark the menu-bar item draws, so that the two at least agree. Replacing the icon means
// re-exporting both from Icon Composer and deleting this script.
//
// The rounded square is macOS's own proportion: a continuous corner radius of 0.2237 of the side.

import AppKit
import Foundation

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("make-icon-preview: " + message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else { die("usage: make-icon-preview.swift <out.png>") }

let side: CGFloat = 1024
let cornerRadius = side * 0.2237
let top = NSColor(srgbRed: 0.40, green: 0.58, blue: 0.98, alpha: 1)
let bottom = NSColor(srgbRed: 0.23, green: 0.38, blue: 0.84, alpha: 1)

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
else { die("could not allocate the bitmap") }
rep.size = NSSize(width: side, height: side)

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: rep) else { die("could not open a context") }
NSGraphicsContext.current = context
context.imageInterpolation = .high

// The slab, with the mask an .icns is required to bake in.
let mask = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: side, height: side),
                        xRadius: cornerRadius, yRadius: cornerRadius)
mask.addClip()
NSGradient(starting: top, ending: bottom)?.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                                                angle: -90)

// The mark: three bars, the middle one filled. The numbers are the SVG's, with y flipped for AppKit.
let barWidth: CGFloat = 560
let barHeight: CGFloat = 150
let gap: CGFloat = 85
let stroke: CGFloat = 48
let total = barHeight * 3 + gap * 2
let left = (side - barWidth) / 2
var bottomEdge = (side + total) / 2 - barHeight

NSColor.white.setFill()
NSColor.white.setStroke()
for index in 0..<3 {
    let rect = NSRect(x: left, y: bottomEdge, width: barWidth, height: barHeight)
    if index == 1 {
        NSBezierPath(roundedRect: rect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
    } else {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: stroke / 2, dy: stroke / 2),
                                xRadius: barHeight / 2, yRadius: barHeight / 2)
        path.lineWidth = stroke
        path.stroke()
    }
    bottomEdge -= barHeight + gap
}
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { die("could not encode the PNG") }
do { try png.write(to: URL(fileURLWithPath: arguments[1])) }
catch { die("could not write: \(error.localizedDescription)") }
