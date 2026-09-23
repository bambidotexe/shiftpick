// The README's animation, drawn frame by frame: a schematic Finder window in icon view, Finder's own
// ⇧ Shift click first (it adds one file, docs/functional.md §4), then ShiftPick's (§2 and §3): the range
// runs from the file a plain click set as the anchor to the one under the pointer, read across the row and
// down to the next, and a further ⇧ Shift click is measured from that same first file. The scene is in the
// family's style (an indigo desktop, a menu-bar strip, a caption pill, a keycap for a held key), the window
// is schematic, and the selection rules are the app's own.
//
// It is not part of the app: nothing builds it. To regenerate docs/assets/shift-click.gif, with ImageMagick
// installed (brew install imagemagick):
//
//   frames=$(mktemp -d)
//   swiftc -O -o "$frames/render" docs/assets/shift-click.swift && "$frames/render" "$frames"
//   magick "$frames/strip.png" +dither -colors 224 -unique-colors "$frames/palette.png"
//   magick -delay 4 -loop 0 "$frames"/f*.png +dither -remap "$frames/palette.png" \
//       -layers optimize docs/assets/shift-click.gif
//
// 800 × 500 at 25 frames a second, like the siblings' animations; the README shows it 720 wide. One palette
// for every frame, drawn from a strip of every twelfth one, so nothing flickers between frames, and no
// dithering, so a pixel that does not change is the same pixel and the optimiser can drop it.

import AppKit
import CoreGraphics

// MARK: - Canvas, timing, layout

let width = 800.0
let height = 500.0
let fps = 25.0
let duration = 9.6

let menuBarHeight = 20.0
let window = CGRect(x: 70, y: 52, width: 660, height: 400)
let sidebarWidth = 140.0
let toolbarHeight = 42.0
let columns = 6
let rowCount = 3
let cellWidth = 84.0
let cellHeight = 110.0
let iconSide = 52.0
let contentLeft = window.minX + sidebarWidth
let gridLeft = contentLeft + (window.maxX - contentLeft - Double(columns) * cellWidth) / 2
let gridTop = window.minY + toolbarHeight + 16

/// Reading order is rows from the leading edge: file `i` sits in row `i / columns`, column `i % columns`.
func iconCentre(_ i: Int) -> CGPoint {
    CGPoint(x: gridLeft + cellWidth * Double(i % columns) + cellWidth / 2,
            y: gridTop + cellHeight * Double(i / columns) + 8 + iconSide / 2)
}

func labelCentreY(_ i: Int) -> Double { gridTop + cellHeight * Double(i / columns) + 8 + iconSide + 14 }

// MARK: - Colours

func rgb(_ hex: UInt32, _ alpha: Double = 1) -> CGColor {
    CGColor(srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, alpha: alpha)
}

let brand = rgb(0x3978F5)               // OnboardingWindow.brand, the icon's fill
let desktopBase = rgb(0x3A3976)
let menuBarFill = rgb(0x1F1F27)
let windowBody = rgb(0xF8F8FA)
let sidebarFill = rgb(0xEEEEF1)
let toolbarFill = rgb(0xF1F1F4)
let hairline = rgb(0xD8D8DD)
let labelGrey = rgb(0xA3A3A9)
let sidebarBar = rgb(0xC9C9D0)
let iconHighlight = rgb(0x000000, 0.09)
let captionFill = rgb(0x121216, 0.92)
let keycapFill = rgb(0xB8B8C4, 0.72)
let keycapGlyphFill = rgb(0x83838F)

// MARK: - Easing and interpolation

func clamp01(_ t: Double) -> Double { min(1, max(0, t)) }
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
func easeInOut(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

// MARK: - The story

/// Where the pointer is: waypoints, eased between, held where two share a point.
let waypoints: [(Double, CGPoint)] = [
    (0.0, CGPoint(x: 690, y: 425)),
    (0.5, CGPoint(x: 690, y: 425)),
    (1.1, iconCentre(3)),
    (1.55, iconCentre(3)),
    (2.3, iconCentre(14)),
    (3.55, iconCentre(14)),
    (4.3, iconCentre(3)),
    (4.75, iconCentre(3)),
    (5.5, iconCentre(14)),
    (7.3, iconCentre(14)),
    (7.9, iconCentre(8)),
    (9.6, iconCentre(8)),
]

func pointer(at t: Double) -> CGPoint {
    guard let last = waypoints.last, t < last.0 else { return waypoints.last!.1 }
    for k in 1..<waypoints.count where t < waypoints[k].0 {
        let (t0, p0) = waypoints[k - 1]
        let (t1, p1) = waypoints[k]
        let u = easeInOut(clamp01((t - t0) / (t1 - t0)))
        return CGPoint(x: lerp(p0.x, p1.x, u), y: lerp(p0.y, p1.y, u))
    }
    return last.1
}

let clicks = [1.15, 2.35, 4.35, 5.55, 7.95]

/// Every change of a file's selection, in time order: Finder's own click adds one file; ShiftPick's fills
/// the range in reading order, and the narrowing takes the far end away in the reverse of it.
var toggles: [(Double, Int, Bool)] = [
    (1.2, 3, true),
    (2.4, 14, true),
    (3.45, 3, false), (3.45, 14, false),
    (4.4, 3, true),
]
for k in 4...14 { toggles.append((5.6 + 0.04 * Double(k - 4), k, true)) }
for k in stride(from: 14, through: 9, by: -1) { toggles.append((8.0 + 0.04 * Double(14 - k), k, false)) }

let selectionFade = 0.12

func selection(of file: Int, at t: Double) -> Double {
    var state = false
    var since = -1.0
    for (time, index, on) in toggles where index == file && time <= t {
        state = on
        since = time
    }
    let progress = since < 0 ? 1 : clamp01((t - since) / selectionFade)
    return state ? progress : 1 - progress
}

let keycapHeld: [(Double, Double)] = [(1.45, 3.35), (4.65, 9.25)]
let keycapFade = 0.16

func keycapPresence(at t: Double) -> Double {
    for (down, up) in keycapHeld {
        if t >= down && t < up + keycapFade {
            return t < up ? easeOut(clamp01((t - down) / keycapFade)) : 1 - clamp01((t - up) / keycapFade)
        }
    }
    return 0
}

let captions: [(Double, String)] = [
    (0.0, "Finder's icon view: a ⇧ Shift click adds one file"),
    (3.4, "With ShiftPick: click one file, ⇧ Shift click another"),
    (5.6, "Everything between them is selected"),
    (8.0, "Measured from the same first file, so widen or narrow it"),
]
let captionFade = 0.2

func caption(at t: Double) -> (String, Double) {
    var current = captions[0]
    var next: (Double, String)?
    for (k, c) in captions.enumerated() where c.0 <= t {
        current = c
        next = k + 1 < captions.count ? captions[k + 1] : nil
    }
    let fadeIn = clamp01((t - current.0) / captionFade)
    let fadeOut = next.map { clamp01(($0.0 - t) / captionFade) } ?? 1
    return (current.1, min(fadeIn, fadeOut))
}

let markAppears = 3.5
func markScale(at t: Double) -> Double { easeOut(clamp01((t - markAppears) / 0.3)) }

let fadeOutStarts = 9.25

// MARK: - The files

enum Kind {
    case photo(UInt32, UInt32)
    case document(UInt32)
}

let files: [Kind] = [
    .photo(0xFFC48A, 0xF08AA0), .document(0x4A90E2), .document(0xF5A623), .photo(0x8ED6C9, 0x3D8BD9),
    .document(0xE74C3C), .photo(0xB7E39C, 0x3E9C6B), .document(0x4A90E2), .photo(0xD9C2F0, 0x7B5BC7),
    .document(0x9B9BA3), .photo(0xFFE08A, 0xF0965A), .document(0x4A90E2), .document(0xF5A623),
    .photo(0x9FD8F5, 0x2E6FD6), .document(0xE74C3C), .photo(0xF7B7C8, 0xC2559A), .document(0x4A90E2),
    .photo(0xBFE6B0, 0x5AA0A8), .document(0x9B9BA3),
]
let labelWidths: [Double] = [44, 36, 52, 40, 30, 46, 38, 50, 34, 42, 56, 32, 48, 36, 44, 40, 30, 52]

// MARK: - Drawing helpers

func roundedPath(_ rect: CGRect, _ radius: Double) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fill(_ ctx: CGContext, _ path: CGPath, _ color: CGColor) {
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
}

func fillRounded(_ ctx: CGContext, _ rect: CGRect, _ radius: Double, _ color: CGColor) {
    fill(ctx, roundedPath(rect, radius), color)
}

func fillPolygon(_ ctx: CGContext, _ points: [CGPoint], _ color: CGColor) {
    ctx.beginPath()
    ctx.move(to: points[0])
    for p in points.dropFirst() { ctx.addLine(to: p) }
    ctx.closePath()
    ctx.setFillColor(color)
    ctx.fillPath()
}

func text(_ ctx: CGContext, _ string: String, centredAt centre: CGPoint, size: Double,
          weight: NSFont.Weight, color: NSColor) -> Double {
    let attributed = NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
    ])
    let box = attributed.size()
    attributed.draw(at: NSPoint(x: centre.x - box.width / 2, y: centre.y - box.height / 2))
    return box.width
}

func textWidth(_ string: String, size: Double, weight: NSFont.Weight) -> Double {
    NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)])
        .size().width
}

// MARK: - The scene

func drawDesktop(_ ctx: CGContext) {
    ctx.setFillColor(desktopBase)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    fillPolygon(ctx, [CGPoint(x: 0, y: 0), CGPoint(x: 430, y: 0), CGPoint(x: 0, y: 340)], rgb(0x47468C))
    fillPolygon(ctx, [CGPoint(x: 520, y: 0), CGPoint(x: 800, y: 0), CGPoint(x: 800, y: 130), CGPoint(x: 640, y: 320)],
                rgb(0x41407F))
    fillPolygon(ctx, [CGPoint(x: 800, y: 130), CGPoint(x: 800, y: 500), CGPoint(x: 290, y: 500)], rgb(0x2E2D62))
    fillPolygon(ctx, [CGPoint(x: 0, y: 340), CGPoint(x: 0, y: 500), CGPoint(x: 290, y: 500)], rgb(0x33326C))
}

/// ShiftPick's menu-bar mark: four tiles, the bottom-right one a ring (MenuBarController.icon), at 18 pt.
func drawMark(_ ctx: CGContext, centre: CGPoint, scale: Double) {
    guard scale > 0 else { return }
    ctx.saveGState()
    ctx.translateBy(x: centre.x, y: centre.y)
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: -9, y: -9)
    let white = rgb(0xF2F2F5)
    for origin in [CGPoint(x: 1, y: 1), CGPoint(x: 10, y: 1), CGPoint(x: 1, y: 10)] {
        fillRounded(ctx, CGRect(origin: origin, size: CGSize(width: 7, height: 7)), 1.6, white)
    }
    let ring = CGMutablePath()
    ring.addPath(roundedPath(CGRect(x: 10, y: 10, width: 7, height: 7), 1.6))
    ring.addPath(roundedPath(CGRect(x: 11.5, y: 11.5, width: 4, height: 4), 0.4))
    ctx.addPath(ring)
    ctx.setFillColor(white)
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
}

func drawMenuBar(_ ctx: CGContext, markScale: Double) {
    ctx.setFillColor(menuBarFill)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: menuBarHeight))
    let pill = rgb(0x76767E)
    ctx.setFillColor(rgb(0x9A9AA2))
    ctx.fillEllipse(in: CGRect(x: 12, y: 6, width: 8, height: 8))
    fillRounded(ctx, CGRect(x: 30, y: 7.5, width: 30, height: 5), 2.5, rgb(0xD6D6DC))
    var x = 70.0
    for w in [16.0, 20, 14, 18] {
        fillRounded(ctx, CGRect(x: x, y: 7.5, width: w, height: 5), 2.5, pill)
        x += w + 10
    }
    x = width - 26
    for w in [14.0, 14, 18] {
        fillRounded(ctx, CGRect(x: x - w, y: 7.5, width: w, height: 5), 2.5, pill)
        x -= w + 12
    }
    drawMark(ctx, centre: CGPoint(x: x - 9, y: menuBarHeight / 2), scale: markScale)
}

func drawWindowChrome(_ ctx: CGContext) {
    let radius = 10.0
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: rgb(0x000000, 0.35))
    fillRounded(ctx, window, radius, windowBody)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(roundedPath(window, radius))
    ctx.clip()

    // The sidebar runs the window's full height, with the traffic lights over it.
    ctx.setFillColor(sidebarFill)
    ctx.fill(CGRect(x: window.minX, y: window.minY, width: sidebarWidth, height: window.height))
    ctx.setFillColor(hairline)
    ctx.fill(CGRect(x: window.minX + sidebarWidth - 0.5, y: window.minY, width: 1, height: window.height))
    for (k, colour) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        ctx.setFillColor(rgb(UInt32(colour)))
        ctx.fillEllipse(in: CGRect(x: window.minX + 14 + Double(k) * 20, y: window.minY + 15, width: 12, height: 12))
    }
    var y = window.minY + 58
    for w in [64.0, 52, 74, 46, 60, 40, 70] {
        fillRounded(ctx, CGRect(x: window.minX + 18, y: y, width: 10, height: 10), 3, sidebarBar)
        fillRounded(ctx, CGRect(x: window.minX + 36, y: y + 2.5, width: w, height: 5), 2.5, sidebarBar)
        y += 26
    }

    // The toolbar over the content pane: back and forward, the folder's name, the view-mode switch with
    // icon view chosen.
    ctx.setFillColor(toolbarFill)
    ctx.fill(CGRect(x: contentLeft, y: window.minY, width: window.maxX - contentLeft, height: toolbarHeight))
    ctx.setFillColor(hairline)
    ctx.fill(CGRect(x: contentLeft, y: window.minY + toolbarHeight - 0.5, width: window.maxX - contentLeft, height: 1))
    let chevron = rgb(0x8E8E95)
    for (k, dir) in [1.0, -1.0].enumerated() {
        let cx = contentLeft + 22 + Double(k) * 24
        let cy = window.minY + toolbarHeight / 2
        ctx.beginPath()
        ctx.move(to: CGPoint(x: cx + dir * 3, y: cy - 6))
        ctx.addLine(to: CGPoint(x: cx - dir * 3, y: cy))
        ctx.addLine(to: CGPoint(x: cx + dir * 3, y: cy + 6))
        ctx.setStrokeColor(chevron)
        ctx.setLineWidth(2)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }
    _ = text(ctx, "Downloads", centredAt: CGPoint(x: (contentLeft + window.maxX) / 2, y: window.minY + toolbarHeight / 2),
             size: 13, weight: .semibold, color: NSColor(srgbRed: 0.24, green: 0.24, blue: 0.27, alpha: 1))
    let switchRect = CGRect(x: window.maxX - 118, y: window.minY + 10, width: 104, height: 22)
    fillRounded(ctx, switchRect, 6, rgb(0xE3E3E8))
    fillRounded(ctx, CGRect(x: switchRect.minX + 2, y: switchRect.minY + 2, width: 24, height: 18), 5, rgb(0xFFFFFF))
    for k in 0..<4 {
        let cx = switchRect.minX + 14 + Double(k) * 26
        let cy = switchRect.midY
        let glyph = k == 0 ? rgb(0x3C3C43) : rgb(0x9A9AA2)
        switch k {
        case 0:
            for (dx, dy) in [(-3.5, -3.5), (1.5, -3.5), (-3.5, 1.5), (1.5, 1.5)] {
                fillRounded(ctx, CGRect(x: cx + dx - 1, y: cy + dy - 1, width: 4, height: 4), 1, glyph)
            }
        case 1:
            for dy in [-4.0, 0, 4] { fillRounded(ctx, CGRect(x: cx - 6, y: cy + dy - 1, width: 12, height: 2), 1, glyph) }
        case 2:
            for dx in [-5.0, -1, 3] { fillRounded(ctx, CGRect(x: cx + dx - 1, y: cy - 5, width: 2, height: 10), 1, glyph) }
        default:
            fillRounded(ctx, CGRect(x: cx - 6, y: cy - 5, width: 12, height: 7), 1.5, glyph)
            for dx in [-5.0, -1.5, 2] { fillRounded(ctx, CGRect(x: cx + dx, y: cy + 3.5, width: 3, height: 2), 1, glyph) }
        }
    }
    ctx.restoreGState()
}

func drawFile(_ ctx: CGContext, _ i: Int, selected: Double) {
    let centre = iconCentre(i)
    let icon = CGRect(x: centre.x - iconSide / 2, y: centre.y - iconSide / 2, width: iconSide, height: iconSide)
    let frame = icon.insetBy(dx: 3, dy: 5)
    let page = CGRect(x: icon.minX + 8, y: icon.minY + 1, width: 36, height: 50)
    // Finder's highlight hugs the icon's own box, not its cell.
    if selected > 0 {
        let art: CGRect
        switch files[i] {
        case .photo: art = frame
        case .document: art = page
        }
        fillRounded(ctx, art.insetBy(dx: -6, dy: -5), 7, rgb(0x000000, 0.09 * selected))
    }
    switch files[i] {
    case let .photo(top, bottom):
        ctx.saveGState()
        ctx.addPath(roundedPath(frame, 4))
        ctx.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  colors: [rgb(top), rgb(bottom)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: frame.minX, y: frame.minY),
                               end: CGPoint(x: frame.minX, y: frame.maxY), options: [])
        ctx.setFillColor(rgb(0xFFFFFF, 0.55))
        ctx.fillEllipse(in: CGRect(x: frame.minX + 8, y: frame.minY + 8, width: 10, height: 10))
        fillPolygon(ctx, [CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.minX + 18, y: frame.midY + 4),
                          CGPoint(x: frame.minX + 30, y: frame.maxY - 8), CGPoint(x: frame.maxX, y: frame.midY + 10),
                          CGPoint(x: frame.maxX, y: frame.maxY)], rgb(0x000000, 0.18))
        ctx.restoreGState()
    case let .document(stripe):
        let fold = 11.0
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 2, color: rgb(0x000000, 0.18))
        fillPolygon(ctx, [CGPoint(x: page.minX, y: page.minY), CGPoint(x: page.maxX - fold, y: page.minY),
                          CGPoint(x: page.maxX, y: page.minY + fold), CGPoint(x: page.maxX, y: page.maxY),
                          CGPoint(x: page.minX, y: page.maxY)], rgb(0xFFFFFF))
        ctx.restoreGState()
        fillPolygon(ctx, [CGPoint(x: page.maxX - fold, y: page.minY), CGPoint(x: page.maxX - fold, y: page.minY + fold),
                          CGPoint(x: page.maxX, y: page.minY + fold)], rgb(0xE2E2E7))
        fillRounded(ctx, CGRect(x: page.minX + 6, y: page.minY + 14, width: 16, height: 4), 2, rgb(stripe))
        for (k, w) in [22.0, 18, 22, 14].enumerated() {
            fillRounded(ctx, CGRect(x: page.minX + 6, y: page.minY + 23 + Double(k) * 6, width: w, height: 2.5), 1.25,
                        rgb(0xCFCFD5))
        }
    }
    // The name: a bar, a pill in the accent colour once the file is selected.
    let w = labelWidths[i]
    let y = labelCentreY(i)
    fillRounded(ctx, CGRect(x: centre.x - w / 2, y: y - 3.5, width: w, height: 7), 3.5, labelGrey)
    if selected > 0 {
        let grow = 2.5 * selected
        let pill = CGRect(x: centre.x - w / 2 - grow, y: y - 3.5 - grow, width: w + 2 * grow, height: 7 + 2 * grow)
        fillRounded(ctx, pill, pill.height / 2, CGColor(srgbRed: 0.22353, green: 0.47059, blue: 0.96078, alpha: selected))
    }
}

func drawClickRing(_ ctx: CGContext, at p: CGPoint, t: Double) {
    for click in clicks {
        let u = (t - click) / 0.32
        guard u >= 0 && u < 1 else { continue }
        let radius = lerp(5, 20, easeOut(u))
        ctx.setStrokeColor(CGColor(srgbRed: 0.22353, green: 0.47059, blue: 0.96078, alpha: 0.7 * (1 - u)))
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: 2 * radius, height: 2 * radius))
    }
}

func drawPointer(_ ctx: CGContext, at p: CGPoint) {
    let outline: [CGPoint] = [
        CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 17), CGPoint(x: 4.3, y: 13.2), CGPoint(x: 7.2, y: 19.6),
        CGPoint(x: 10.2, y: 18.3), CGPoint(x: 7.4, y: 12.1), CGPoint(x: 12.6, y: 12.1),
    ]
    ctx.saveGState()
    ctx.translateBy(x: p.x, y: p.y)
    ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 2, color: rgb(0x000000, 0.35))
    ctx.beginPath()
    ctx.move(to: outline[0])
    for q in outline.dropFirst() { ctx.addLine(to: q) }
    ctx.closePath()
    ctx.setStrokeColor(rgb(0xFFFFFF))
    ctx.setLineWidth(2.4)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()
    fillPolygon(ctx, outline.map { CGPoint(x: $0.x + p.x, y: $0.y + p.y) }, rgb(0x000000))
}

func drawKeycap(_ ctx: CGContext, presence: Double) {
    guard presence > 0 else { return }
    let label = "Shift"
    let labelWidth = textWidth(label, size: 13, weight: .bold)
    let pill = CGRect(x: 16, y: height - 44, width: 12 + 28 + 8 + labelWidth + 14, height: 32)
    ctx.saveGState()
    ctx.setAlpha(presence)
    let scale = lerp(0.85, 1, presence)
    ctx.translateBy(x: pill.minX, y: pill.midY)
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: -pill.minX, y: -pill.midY)
    fillRounded(ctx, pill, 16, keycapFill)
    fillRounded(ctx, CGRect(x: pill.minX + 8, y: pill.minY + 4, width: 24, height: 24), 6, keycapGlyphFill)
    _ = text(ctx, "⇧", centredAt: CGPoint(x: pill.minX + 20, y: pill.midY), size: 15, weight: .semibold, color: .white)
    _ = text(ctx, label, centredAt: CGPoint(x: pill.minX + 40 + labelWidth / 2, y: pill.midY), size: 13,
             weight: .bold, color: .white)
    ctx.restoreGState()
}

func drawCaption(_ ctx: CGContext, _ string: String, alpha: Double) {
    guard alpha > 0 else { return }
    let w = textWidth(string, size: 13.5, weight: .bold)
    let pill = CGRect(x: (width - w) / 2 - 14, y: height - 44, width: w + 28, height: 32)
    ctx.saveGState()
    ctx.setAlpha(alpha)
    fillRounded(ctx, pill, 16, captionFill)
    _ = text(ctx, string, centredAt: CGPoint(x: width / 2, y: pill.midY), size: 13.5, weight: .bold, color: .white)
    ctx.restoreGState()
}

func drawFrame(_ ctx: CGContext, at t: Double) {
    drawDesktop(ctx)
    drawMenuBar(ctx, markScale: markScale(at: t))
    drawWindowChrome(ctx)
    for i in 0..<(columns * rowCount) { drawFile(ctx, i, selected: selection(of: i, at: t)) }
    let p = pointer(at: t)
    drawClickRing(ctx, at: p, t: t)
    drawPointer(ctx, at: p)
    drawKeycap(ctx, presence: keycapPresence(at: t))
    let (string, alpha) = caption(at: t)
    drawCaption(ctx, string, alpha: alpha)
    // The loop's end: down to black, and the next pass starts fresh.
    let fade = clamp01((t - fadeOutStarts) / (duration - fadeOutStarts))
    if fade > 0 {
        ctx.setFillColor(rgb(0x000000, fade))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
}

// MARK: - Rendering

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write("usage: shift-click <output directory>\n".data(using: .utf8)!)
    exit(2)
}
let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let frameCount = Int((duration * fps).rounded())
var paletteSamples: [CGImage] = []

for frame in 0..<frameCount {
    let ctx = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    drawFrame(ctx, at: Double(frame) / fps)
    NSGraphicsContext.current = nil
    let image = ctx.makeImage()!
    let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try png.write(to: outputDirectory.appendingPathComponent(String(format: "f%04d.png", frame)))
    if frame % 12 == 0 { paletteSamples.append(image) }
}

// A strip of every twelfth frame, for ImageMagick to draw one palette from and remap every frame to.
let strip = CGContext(data: nil, width: Int(width) * paletteSamples.count, height: Int(height), bitsPerComponent: 8,
                      bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
for (k, image) in paletteSamples.enumerated() {
    strip.draw(image, in: CGRect(x: Double(k) * width, y: 0, width: width, height: height))
}
let stripPNG = NSBitmapImageRep(cgImage: strip.makeImage()!).representation(using: .png, properties: [:])!
try stripPNG.write(to: outputDirectory.appendingPathComponent("strip.png"))
print("\(frameCount) frames in \(outputDirectory.path); the palette strip is strip.png")
