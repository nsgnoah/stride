#!/usr/bin/env swift
// Draws the Stride app icon: an "S" laid down like a ribbon of road, with the runner as
// the dot at its leading end. Usage: swift Tools/make_icon.swift <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha])!
}

func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { color($0.0, $0.1) } as CFArray, locations: stops.map { $0.2 })!
}

// Background: deep ink, a little lighter toward the top, with a warm glow where the road leads.
ctx.drawLinearGradient(gradient([(0x1B1D2B, 1, 0), (0x0D0E16, 1, 1)]),
                       start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
ctx.drawRadialGradient(gradient([(0xFF7A4D, 0.30, 0), (0xFF7A4D, 0, 1)]),
                       startCenter: CGPoint(x: 800, y: 800), startRadius: 0,
                       endCenter: CGPoint(x: 800, y: 800), endRadius: 620, options: [])

// Everything from here is the mark; size and centre it in the square (and inside the
// circle the watch crops to).
ctx.translateBy(x: 512, y: 512)
ctx.scaleBy(x: 1.1, y: 1.1)
ctx.translateBy(x: -552, y: -556)

// The S, from its lower-left tail up to the upper-right, leaning forward like something moving.
typealias Curve = (CGPoint, CGPoint, CGPoint, CGPoint)
let curves: [Curve] = [
    (CGPoint(x: 300, y: 290), CGPoint(x: 720, y: 210), CGPoint(x: 800, y: 470), CGPoint(x: 512, y: 520)),
    (CGPoint(x: 512, y: 520), CGPoint(x: 210, y: 572), CGPoint(x: 300, y: 820), CGPoint(x: 640, y: 752)),
]

func point(_ c: Curve, _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    let x = u * u * u * c.0.x + 3 * u * u * t * c.1.x + 3 * u * t * t * c.2.x + t * t * t * c.3.x
    let y = u * u * u * c.0.y + 3 * u * u * t * c.1.y + 3 * u * t * t * c.2.y + t * t * t * c.3.y
    // Lean it forward.
    return CGPoint(x: x + 0.16 * (y - 512), y: y)
}

/// The ribbon as a run of overlapping discs, thin at the tail and full at the front,
/// so it reads as a stride gathering speed rather than a letter.
func ribbon(scale: CGFloat = 1) -> CGPath {
    let path = CGMutablePath()
    let steps = 400
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let p = t < 0.5 ? point(curves[0], t * 2) : point(curves[1], (t - 0.5) * 2)
        let eased = t * t * (3 - 2 * t)
        let radius = (20 + 50 * eased) * scale
        path.addEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
    }
    return path
}

// A soft shadow lifts the ribbon off the background.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 44, color: color(0x000000, 0.6))
ctx.addPath(ribbon())
ctx.setFillColor(color(0xFF6A3D))
ctx.fillPath(using: .winding)
ctx.restoreGState()

// Ember at the tail, warming to gold at the front.
ctx.saveGState()
ctx.addPath(ribbon())
ctx.clip(using: .winding)
ctx.drawLinearGradient(gradient([(0xFF3F3A, 1, 0), (0xFF7445, 1, 0.45), (0xFFC25A, 1, 1)]),
                       start: CGPoint(x: 240, y: 260), end: CGPoint(x: 800, y: 800), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// A highlight along the upper edge gives it some volume.
ctx.drawLinearGradient(gradient([(0xFFFFFF, 0.22, 0), (0xFFFFFF, 0, 0.5)]),
                       start: CGPoint(x: 512, y: 860), end: CGPoint(x: 512, y: 300), options: [])
ctx.restoreGState()

// The runner's head: a bright dot just ahead of the front of the stride.
let head = point(curves[1], 1)
let dot = CGRect(x: head.x + 78, y: head.y + 6, width: 104, height: 104)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 50, color: color(0xFFD27A, 0.95))
ctx.setFillColor(color(0xFFF4E0))
ctx.fillEllipse(in: dot)
ctx.restoreGState()

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png")
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
