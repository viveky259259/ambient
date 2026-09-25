// Renders Ambient's app icon: a dark tile, the notch with a glowing orb, and light along the bottom edge.
// Usage: swift scripts/make-icon.swift <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let s = CGFloat(size)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                            CGFloat(hex & 0xFF) / 255, a])!
}

// The macOS icon grid: an 824 pt tile centered in 1024.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

// Drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(0x16161A))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()

// Background: deep graphite, a touch lighter at the top.
let bg = CGGradient(colorsSpace: space, colors: [rgb(0x2A2A31), rgb(0x111114)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: s / 2, y: tile.maxY), end: CGPoint(x: s / 2, y: tile.minY), options: [])

// Light rising from the bottom edge, like the Dock glow.
let coral: UInt32 = 0xD97757
ctx.saveGState()
ctx.translateBy(x: s / 2, y: tile.minY - 40)
ctx.scaleBy(x: 1.9, y: 1)
let floor = CGGradient(colorsSpace: space, colors: [rgb(coral, 0.95), rgb(coral, 0.35), rgb(coral, 0)] as CFArray,
                       locations: [0, 0.45, 1])!
ctx.drawRadialGradient(floor, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 330, options: [])
ctx.restoreGState()

// The notch, hanging from the top edge, with flared shoulders.
let notchW: CGFloat = 470, notchH: CGFloat = 150, t: CGFloat = 26, b: CGFloat = 70
let nx = s / 2 - notchW / 2, top = tile.maxY
let notch = CGMutablePath()
notch.move(to: CGPoint(x: nx, y: top))
notch.addQuadCurve(to: CGPoint(x: nx + t, y: top - t), control: CGPoint(x: nx + t, y: top))
notch.addLine(to: CGPoint(x: nx + t, y: top - notchH + b))
notch.addQuadCurve(to: CGPoint(x: nx + t + b, y: top - notchH), control: CGPoint(x: nx + t, y: top - notchH))
notch.addLine(to: CGPoint(x: nx + notchW - t - b, y: top - notchH))
notch.addQuadCurve(to: CGPoint(x: nx + notchW - t, y: top - notchH + b), control: CGPoint(x: nx + notchW - t, y: top - notchH))
notch.addLine(to: CGPoint(x: nx + notchW - t, y: top - t))
notch.addQuadCurve(to: CGPoint(x: nx + notchW, y: top), control: CGPoint(x: nx + notchW - t, y: top))
notch.closeSubpath()
ctx.addPath(notch)
ctx.setFillColor(rgb(0x000000))
ctx.fillPath()

// The orb in the notch's left wing, glowing.
let orbCenter = CGPoint(x: nx + t + 88, y: top - notchH / 2 - 6)
let halo = CGGradient(colorsSpace: space, colors: [rgb(coral, 0.9), rgb(coral, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(halo, startCenter: orbCenter, startRadius: 0, endCenter: orbCenter, endRadius: 78, options: [])
let orb = CGGradient(colorsSpace: space, colors: [rgb(0xF4B39A), rgb(coral)] as CFArray, locations: [0, 1])!
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: orbCenter.x - 34, y: orbCenter.y - 34, width: 68, height: 68))
ctx.clip()
ctx.drawRadialGradient(orb, startCenter: CGPoint(x: orbCenter.x - 12, y: orbCenter.y + 12), startRadius: 0,
                       endCenter: orbCenter, endRadius: 40, options: [.drawsAfterEndLocation])
ctx.restoreGState()

// A quiet status line in the right wing.
ctx.setFillColor(rgb(0xFFFFFF, 0.22))
ctx.addPath(CGPath(roundedRect: CGRect(x: nx + notchW - t - 170, y: orbCenter.y - 9, width: 110, height: 18),
                   cornerWidth: 9, cornerHeight: 9, transform: nil))
ctx.fillPath()

// A hairline rim so the tile reads on dark backgrounds.
ctx.restoreGState()
ctx.addPath(tilePath)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.08))
ctx.setLineWidth(3)
ctx.strokePath()

let image = ctx.makeImage()!
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png")
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
