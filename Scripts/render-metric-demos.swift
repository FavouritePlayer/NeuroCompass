#!/usr/bin/env swift
/// Offline demo renderer: applies the same shared-gradient metric blend used by ScreenShade
/// to a source screenshot. Does not require Screen Recording permission.
import AppKit
import QuartzCore
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

struct Channel {
    var enabled: Bool
    var start: Double
    var end: Double
}

struct DemoSettings {
    var angleDegrees: Double = 0
    var center: Double = 0.5
    var width: Double = 0.12
    var inverted: Bool = false
    var brightOpacity: Double = 0
    var dimOpacity: Double = 0
    var contrast = Channel(enabled: false, start: 0, end: 0)
    var saturation = Channel(enabled: false, start: 0, end: 0)
    var sharpness = Channel(enabled: false, start: 0, end: 0)
    var warmth = Channel(enabled: false, start: 0, end: 0)
}

func locations(center: Double, width: Double) -> [NSNumber] {
    if width <= 0.001 {
        let c = min(max(center, 0.001), 0.999)
        return [0, NSNumber(value: c), NSNumber(value: c), 1]
    }
    let half = width * 0.5
    return [0, NSNumber(value: max(0, center - half)), NSNumber(value: min(1, center + half)), 1]
}

func points(angle: Double) -> (CGPoint, CGPoint) {
    let rad = angle * .pi / 180
    let d = CGPoint(x: cos(rad), y: -sin(rad))
    return (CGPoint(x: 0.5 - d.x * 0.5, y: 0.5 - d.y * 0.5),
            CGPoint(x: 0.5 + d.x * 0.5, y: 0.5 + d.y * 0.5))
}

func makeMask(size: CGSize, s: DemoSettings) -> CIImage {
    let w = max(Int(size.width), 1), h = max(Int(size.height), 1)
    let rect = CGRect(x: 0, y: 0, width: w, height: h)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let layer = CAGradientLayer()
    layer.frame = rect
    layer.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.white.cgColor, NSColor.white.cgColor]
    layer.locations = locations(center: s.center, width: s.width)
    let p = points(angle: s.angleDegrees)
    layer.startPoint = p.0
    layer.endPoint = p.1
    layer.render(in: ctx)
    return CIImage(cgImage: ctx.makeImage()!)
}

func oriented(_ c: Channel, inv: Bool) -> (Double, Double) { inv ? (c.end, c.start) : (c.start, c.end) }

func applySide(_ image: CIImage, s: DemoSettings, startSide: Bool) -> CIImage {
    var img = image
    var contrastAmt = 0.0, satAmt = 0.0
    if s.contrast.enabled {
        let p = oriented(s.contrast, inv: s.inverted)
        contrastAmt = startSide ? p.0 : p.1
    }
    if s.saturation.enabled {
        let p = oriented(s.saturation, inv: s.inverted)
        satAmt = startSide ? p.0 : p.1
    }
    if s.contrast.enabled || s.saturation.enabled {
        let f = CIFilter.colorControls()
        f.inputImage = img
        f.contrast = Float(1.0 + contrastAmt * 0.5)
        f.saturation = Float(1.0 + satAmt)
        f.brightness = 0
        if let o = f.outputImage { img = o }
    }
    if s.sharpness.enabled {
        let p = oriented(s.sharpness, inv: s.inverted)
        let amt = startSide ? p.0 : p.1
        if amt > 0.001 {
            let u = CIFilter.unsharpMask()
            u.inputImage = img
            u.radius = Float(1.5 + amt * 3.5)
            u.intensity = Float(amt * 1.2)
            if let o = u.outputImage { img = o }
        } else if amt < -0.001 {
            let b = CIFilter.gaussianBlur()
            b.inputImage = img
            b.radius = Float(abs(amt) * 4.0)
            if let o = b.outputImage?.cropped(to: image.extent) { img = o }
        }
    }
    if s.warmth.enabled {
        let p = oriented(s.warmth, inv: s.inverted)
        let amt = startSide ? p.0 : p.1
        if abs(amt) > 0.001 {
            let t = CIFilter.temperatureAndTint()
            t.inputImage = img
            t.neutral = CIVector(x: CGFloat(6500 - amt * 2500), y: 0)
            t.targetNeutral = CIVector(x: 6500, y: 0)
            if let o = t.outputImage { img = o }
        }
    }
    let dimStart = s.inverted ? s.dimOpacity : s.brightOpacity
    let dimEnd = s.inverted ? s.brightOpacity : s.dimOpacity
    let opacity = startSide ? dimStart : dimEnd
    if opacity > 0.001 {
        let m = CIFilter.colorMatrix()
        m.inputImage = img
        let keep = CGFloat(1 - opacity)
        m.rVector = CIVector(x: keep, y: 0, z: 0, w: 0)
        m.gVector = CIVector(x: 0, y: keep, z: 0, w: 0)
        m.bVector = CIVector(x: 0, y: 0, z: keep, w: 0)
        m.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        if let o = m.outputImage { img = o }
    }
    return img
}

func process(_ cg: CGImage, s: DemoSettings) -> CGImage? {
    let input = CIImage(cgImage: cg)
    let extent = input.extent
    let mask = makeMask(size: extent.size, s: s)
    let blend = CIFilter.blendWithMask()
    blend.inputImage = applySide(input, s: s, startSide: false)
    blend.backgroundImage = applySide(input, s: s, startSide: true)
    blend.maskImage = mask
    guard let out = blend.outputImage?.cropped(to: extent) else { return nil }
    return CIContext().createCGImage(out, from: extent)
}

func save(_ cg: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: cg)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: url)
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    fputs("Usage: render-metric-demos.swift <source.png> <outdir>\n", stderr)
    exit(1)
}
let sourceURL = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

guard let src = NSImage(contentsOf: sourceURL),
      let tiff = src.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let cg = rep.cgImage else {
    fputs("Failed to load source\n", stderr)
    exit(1)
}

var contrast = DemoSettings()
contrast.contrast = Channel(enabled: true, start: 0.0, end: 0.7)
contrast.dimOpacity = 0.05
if let img = process(cg, s: contrast) {
    save(img, to: outDir.appendingPathComponent("screenshade-contrast-left.png"))
}

var sat = DemoSettings()
sat.saturation = Channel(enabled: true, start: 0.4, end: -0.7)
if let img = process(cg, s: sat) {
    save(img, to: outDir.appendingPathComponent("screenshade-saturation-left.png"))
}

var sharp = DemoSettings()
sharp.sharpness = Channel(enabled: true, start: 0.7, end: -0.6)
if let img = process(cg, s: sharp) {
    save(img, to: outDir.appendingPathComponent("screenshade-sharpness-left.png"))
}

var combo = DemoSettings()
combo.contrast = Channel(enabled: true, start: 0.0, end: 0.45)
combo.saturation = Channel(enabled: true, start: 0.2, end: -0.5)
combo.sharpness = Channel(enabled: true, start: 0.4, end: -0.3)
combo.warmth = Channel(enabled: true, start: -0.15, end: 0.4)
combo.dimOpacity = 0.1
if let img = process(cg, s: combo) {
    save(img, to: outDir.appendingPathComponent("screenshade-metrics-combo-left.png"))
}

print("Wrote demos to \(outDir.path)")
