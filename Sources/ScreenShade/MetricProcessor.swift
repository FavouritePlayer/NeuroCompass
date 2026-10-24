import AppKit
import QuartzCore
import CoreImage
import CoreImage.CIFilterBuiltins

/// Applies contrast / saturation / sharpness / warmth / dimming at a single strength,
/// then blends start-side and end-side results with the shared gradient mask.
enum MetricProcessor {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Build a grayscale mask CIImage matching the shared gradient geometry.
    /// Black = start/bright side, white = end/dim side.
    static func makeMask(size: CGSize, settings: ShadeSettings) -> CIImage {
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return CIImage(color: .black).cropped(to: rect)
        }

        let layer = CAGradientLayer()
        layer.frame = rect
        layer.colors = settings.maskColorsForStops().map(\.cgColor)
        layer.locations = settings.colorLocations()
        let points = settings.gradientPoints()
        layer.startPoint = points.start
        layer.endPoint = points.end
        layer.type = .axial
        layer.render(in: ctx)

        guard let cg = ctx.makeImage() else {
            return CIImage(color: .black).cropped(to: rect)
        }
        return CIImage(cgImage: cg)
    }

    /// Process a captured frame. Returns nil on failure.
    static func process(cgImage: CGImage, settings: ShadeSettings) -> CGImage? {
        let input = CIImage(cgImage: cgImage)
        let extent = input.extent
        var mask = makeMask(size: extent.size, settings: settings)
        if mask.extent.size != extent.size {
            let sx = extent.width / max(mask.extent.width, 1)
            let sy = extent.height / max(mask.extent.height, 1)
            mask = mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        }

        let startImage = applySide(input, settings: settings, side: .start)
        let endImage = applySide(input, settings: settings, side: .end)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = endImage
        blend.backgroundImage = startImage
        blend.maskImage = mask
        guard let output = blend.outputImage?.cropped(to: extent) else { return nil }

        return context.createCGImage(output, from: extent)
    }

    private enum Side { case start, end }

    private static func applySide(_ image: CIImage, settings: ShadeSettings, side: Side) -> CIImage {
        var img = image

        var contrastAmt = 0.0
        var satAmt = 0.0
        if settings.contrast.enabled {
            let pair = settings.oriented(settings.contrast)
            contrastAmt = side == .start ? pair.start : pair.end
        }
        if settings.saturation.enabled {
            let pair = settings.oriented(settings.saturation)
            satAmt = side == .start ? pair.start : pair.end
        }

        if settings.contrast.enabled || settings.saturation.enabled {
            let controls = CIFilter.colorControls()
            controls.inputImage = img
            controls.contrast = Float(1.0 + contrastAmt * 0.5)
            controls.saturation = Float(1.0 + satAmt)
            controls.brightness = 0
            if let out = controls.outputImage { img = out }
        }

        if settings.sharpness.enabled {
            let pair = settings.oriented(settings.sharpness)
            let amt = side == .start ? pair.start : pair.end
            if amt > 0.001 {
                let unsharp = CIFilter.unsharpMask()
                unsharp.inputImage = img
                unsharp.radius = Float(1.5 + amt * 3.5)
                unsharp.intensity = Float(amt * 1.2)
                if let out = unsharp.outputImage { img = out }
            } else if amt < -0.001 {
                let blur = CIFilter.gaussianBlur()
                blur.inputImage = img
                blur.radius = Float(abs(amt) * 4.0)
                if let out = blur.outputImage?.cropped(to: image.extent) { img = out }
            }
        }

        if settings.warmth.enabled {
            let pair = settings.oriented(settings.warmth)
            let amt = side == .start ? pair.start : pair.end
            if abs(amt) > 0.001 {
                let temp = CIFilter.temperatureAndTint()
                temp.inputImage = img
                let kelvin = 6500.0 - amt * 2500.0
                temp.neutral = CIVector(x: CGFloat(kelvin), y: 0)
                temp.targetNeutral = CIVector(x: 6500, y: 0)
                if let out = temp.outputImage { img = out }
            }
        }

        let dims = settings.orientedDimOpacities()
        let opacity = side == .start ? dims.start : dims.end
        if opacity > 0.001 {
            let dim = CIFilter.colorMatrix()
            dim.inputImage = img
            let keep = CGFloat(1.0 - opacity)
            dim.rVector = CIVector(x: keep, y: 0, z: 0, w: 0)
            dim.gVector = CIVector(x: 0, y: keep, z: 0, w: 0)
            dim.bVector = CIVector(x: 0, y: 0, z: keep, w: 0)
            dim.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            if let out = dim.outputImage { img = out }
        }

        return img
    }
}
