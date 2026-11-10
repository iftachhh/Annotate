import AppKit

/// Eraser + rasterization, split out of OverlayView.swift.
///
/// Text/counter are erased whole (they're discrete objects, not strokes). Pen/highlighter are
/// already point lists, so erasing them just subtracts a NaN-marked gap in place (same
/// annotation/layer, same id). Line/arrow/rectangle/circle are parametric (2 corner points, no
/// interior points to remove) — erasing those instead rasterizes the exact vector rendering to
/// a bitmap and clears a real hole out of the pixels, which is what keeps a line perfectly
/// straight and an arrowhead a real triangle right up to the erased edge, rather than degrading
/// into a lumpy round-jointed polyline approximation. Once rasterized it becomes `.image` kind;
/// further erasing on it just clears more pixels from the same bitmap.
extension OverlayView {
    private var eraseRadius: CGFloat { appState.toolSettings.width(for: .eraser) }

    /// Erasing only clears a circle at the exact cursor point — on a fast drag, consecutive
    /// `mouseDragged` events land far apart, leaving unerased gaps between them (a dotted trail
    /// instead of a continuous one). Stepping along the segment from the last point closes those gaps.
    func eraseAlongPath(to global: CGPoint) {
        defer { lastEraseGlobal = global }
        guard let last = lastEraseGlobal else { eraseHit(at: global); return }
        let distance = last.distance(to: global)
        let step = max(eraseRadius / 2, 1)
        let steps = max(1, Int((distance / step).rounded(.up)))
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            eraseHit(at: CGPoint(x: last.x + (global.x - last.x) * t, y: last.y + (global.y - last.y) * t))
        }
    }

    func eraseHit(at point: CGPoint) {
        for index in appState.annotations.indices.reversed() {
            let annotation = appState.annotations[index]
            guard annotation.hitTest(point) else { continue }

            switch annotation.kind {
            case .text, .counter:
                appState.annotations.remove(at: index)
                redrawAll()

            case .pen, .highlighter:
                guard Annotation.strokeContains(annotation.points, point, within: eraseRadius) else { continue }
                let gapped = Annotation.subtract(annotation.points, erasing: point, radius: eraseRadius)
                if Annotation.hasVisibleContent(gapped) {
                    appState.annotations[index].points = gapped
                } else {
                    appState.annotations.remove(at: index)
                }
                redrawAll()

            case .line, .arrow, .rectangle, .circle:
                if let rasterized = rasterize(annotation, erasingAt: point) {
                    appState.annotations[index] = rasterized
                } else {
                    appState.annotations.remove(at: index)
                }
                redrawAll()

            case .image:
                if let erased = eraseFromImage(annotation, at: point) {
                    appState.annotations[index] = erased
                } else {
                    appState.annotations.remove(at: index)
                }
                redrawAll()
            }
        }
    }

    /// Renders `annotation` (its exact existing vector geometry — line/arrow/rectangle/circle) into
    /// an offscreen bitmap via the same AnnotationRenderer code used for live drawing, then clears a
    /// circular hole at `point`. Returns nil if nothing survives (fully erased).
    private func rasterize(_ annotation: Annotation, erasingAt point: CGPoint) -> Annotation? {
        // Generous padding: an arrowhead can extend well past its raw 2-point bounding box.
        let pad = max(annotation.lineWidth * 5, 20)
        let box = annotation.boundingBox.insetBy(dx: -pad, dy: -pad)
        guard box.width > 0, box.height > 0 else { return nil }

        let scale: CGFloat = 2
        let pixelWidth = max(1, Int(box.width * scale))
        let pixelHeight = max(1, Int(box.height * scale))
        guard let ctx = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.scaleBy(x: scale, y: scale)

        AnnotationRenderer.draw(annotation, in: ctx, offset: box.origin)
        clearCircle(in: ctx, atGlobal: point, boxOrigin: box.origin)

        guard let cgImage = ctx.makeImage(), imageHasVisibleContent(cgImage) else { return nil }
        var result = annotation
        result.kind = .image
        result.image = cgImage
        result.points = [box.origin, CGPoint(x: box.maxX, y: box.maxY)]
        return result
    }

    /// Same idea as rasterize(_:erasingAt:), but the annotation is already a bitmap — redraw the
    /// existing image into a fresh context (never mutate the old CGImage in place, since past undo
    /// snapshots may still reference it) and clear another hole in it.
    private func eraseFromImage(_ annotation: Annotation, at point: CGPoint) -> Annotation? {
        guard let image = annotation.image, annotation.points.count == 2 else { return nil }
        let rect = CGRect(point: annotation.points[0], point: annotation.points[1])
        guard rect.width > 0, rect.height > 0 else { return nil }

        guard let ctx = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return annotation }
        ctx.scaleBy(x: CGFloat(image.width) / rect.width, y: CGFloat(image.height) / rect.height)

        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        clearCircle(in: ctx, atGlobal: point, boxOrigin: rect.origin)

        guard let newImage = ctx.makeImage(), imageHasVisibleContent(newImage) else { return nil }
        var result = annotation
        result.image = newImage
        return result
    }

    private func clearCircle(in ctx: CGContext, atGlobal point: CGPoint, boxOrigin: CGPoint) {
        ctx.setBlendMode(.clear)
        let local = CGPoint(x: point.x - boxOrigin.x, y: point.y - boxOrigin.y)
        ctx.fillEllipse(in: CGRect(x: local.x - eraseRadius, y: local.y - eraseRadius, width: eraseRadius * 2, height: eraseRadius * 2))
        ctx.setBlendMode(.normal)
    }

    /// Cheap approximate "is this bitmap fully transparent" check — downsamples to 8x8 and scans
    /// for any surviving alpha, instead of scanning every pixel of a potentially large bitmap on
    /// every drag tick while erasing.
    private func imageHasVisibleContent(_ image: CGImage) -> Bool {
        let side = 8
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = ctx.data else { return true }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let buffer = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        for i in 0..<(side * side) where buffer[i * 4 + 3] > 0 { return true }
        return false
    }
}
