import AppKit

enum AnnotationRenderer {
    static func draw(_ annotation: Annotation, in ctx: CGContext, offset: CGPoint) {
        func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - offset.x, y: p.y - offset.y) }
        let points = annotation.points.map(local)

        ctx.saveGState()
        defer { ctx.restoreGState() }

        switch annotation.kind {
        case .pen:
            drawPath(points, color: annotation.color, width: annotation.lineWidth, alpha: 1, dash: annotation.lineStyle, in: ctx)
        case .highlighter:
            drawPath(points, color: annotation.color, width: annotation.lineWidth * 3, alpha: 0.35, dash: annotation.lineStyle, cap: .butt, in: ctx)
        case .line:
            guard points.count == 2 else { return }
            drawPath(points, color: annotation.color, width: annotation.lineWidth, alpha: 1, dash: annotation.lineStyle, in: ctx)
        case .arrow:
            guard points.count == 2 else { return }
            drawArrow(from: points[0], to: points[1], color: annotation.color, width: annotation.lineWidth, dash: annotation.lineStyle, in: ctx)
        case .rectangle:
            guard points.count == 2 else { return }
            let rect = CGRect(point: points[0], point: points[1])
            if annotation.lineStyle == .filled {
                ctx.setFillColor(annotation.color.cgColor)
                ctx.fill(rect)
            } else {
                ctx.setStrokeColor(annotation.color.cgColor)
                ctx.setLineWidth(annotation.lineWidth)
                // Round cap so `.dotted`'s near-zero dash segments actually render as visible dots
                // instead of vanishing — without it a dotted border was invisible.
                ctx.setLineCap(.round)
                applyDash(annotation.lineStyle, width: annotation.lineWidth, in: ctx)
                ctx.stroke(rect)
            }
        case .circle:
            guard points.count == 2 else { return }
            let rect = CGRect(point: points[0], point: points[1])
            if annotation.lineStyle == .filled {
                ctx.setFillColor(annotation.color.cgColor)
                ctx.fillEllipse(in: rect)
            } else {
                ctx.setStrokeColor(annotation.color.cgColor)
                ctx.setLineWidth(annotation.lineWidth)
                // Same fix as rectangle: round cap so `.dotted`'s near-zero dash segments render as
                // visible dots instead of vanishing.
                ctx.setLineCap(.round)
                applyDash(annotation.lineStyle, width: annotation.lineWidth, in: ctx)
                ctx.strokeEllipse(in: rect)
            }
        case .text:
            guard let anchor = points.first else { return }
            let font = annotation.fontStyle.font(size: annotation.fontSize, bold: annotation.isBold, text: annotation.text)
            let attrString = NSAttributedString(string: annotation.text, attributes: [.font: font, .foregroundColor: annotation.color])
            let size = attrString.size()
            // RTL (Hebrew) text is anchored/grown from its right edge while editing (see
            // OverlayView.repositionActiveTextField) — mirror that here so the committed drawing
            // lands exactly where it visibly sat during editing.
            let origin = annotation.text.isRTLText ? CGPoint(x: anchor.x - size.width, y: anchor.y) : anchor
            // draw(in:) anchors to a fully-specified rect (unlike draw(at:), whose vertical anchor is
            // ambiguous in a non-flipped view) so this lines up exactly with where the live editor sat.
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            attrString.draw(in: CGRect(origin: origin, size: size))
            NSGraphicsContext.restoreGraphicsState()
        case .counter:
            guard let origin = points.first else { return }
            let diameter: CGFloat = annotation.fontSize * 1.6
            let rect = CGRect(x: origin.x - diameter / 2, y: origin.y - diameter / 2, width: diameter, height: diameter)
            ctx.setStrokeColor(annotation.color.cgColor)
            // Border scales with the circle itself (not the fixed lineWidth setting) — otherwise a
            // small counter's border eats the whole circle while a large one's looks paper-thin.
            ctx.setLineWidth(max(2, diameter * 0.14))
            ctx.strokeEllipse(in: rect)
            let text = "\(annotation.counterValue)"
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: diameter * 0.5), .foregroundColor: annotation.color]
            let size = (text as NSString).size(withAttributes: attrs)
            drawString(text, at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), attributes: attrs, in: ctx)
        case .image:
            guard let cgImage = annotation.image, points.count == 2 else { return }
            ctx.draw(cgImage, in: CGRect(point: points[0], point: points[1]))
        }
    }

    /// Sets (or clears) the context's dash pattern for the given style. `.filled` has no meaning
    /// for a stroked path (only rectangle/circle honor it, by filling instead of stroking), so it
    /// falls back to solid here — reachable only if a shape's stored style is later reused by a
    /// line-based tool via the shared sync group.
    private static func applyDash(_ style: LineStyle, width: CGFloat, in ctx: CGContext) {
        switch style {
        case .solid, .filled:
            ctx.setLineDash(phase: 0, lengths: [])
        case .dashed:
            ctx.setLineDash(phase: 0, lengths: [width * 3, width * 2])
        case .dotted:
            ctx.setLineDash(phase: 0, lengths: [0.1, width * 2])
        }
    }

    private static func drawPath(_ points: [CGPoint], color: NSColor, width: CGFloat, alpha: CGFloat, dash: LineStyle = .solid, cap: CGLineCap = .round, in ctx: CGContext) {
        guard points.contains(where: { !$0.x.isNaN }) else { return }
        ctx.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(cap)
        ctx.setLineJoin(.round)
        applyDash(dash, width: width, in: ctx)
        ctx.beginPath()
        // A NaN point marks an eraser gap — lift the pen and start a new subpath after it, instead
        // of drawing a line across the erased hole.
        var needsMove = true
        var drewSegment = false
        var lastPoint: CGPoint?
        for p in points {
            if p.x.isNaN { needsMove = true; continue }
            if needsMove { ctx.move(to: p); needsMove = false } else { ctx.addLine(to: p); drewSegment = true }
            lastPoint = p
        }
        ctx.strokePath()
        // A click with no drag leaves a single point and no line segment — stroking that draws
        // nothing at all, so fall back to a filled dot the same width as the stroke would be.
        if !drewSegment, let p = lastPoint {
            let radius = width / 2
            ctx.setFillColor(color.withAlphaComponent(alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
        }
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, color: NSColor, width: CGFloat, dash: LineStyle = .solid, in ctx: CGContext) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        // Open "›" chevron, not a filled triangle — two short strokes meeting at the tip.
        let headLength: CGFloat = max(10, width * 3)
        let headSpread: CGFloat = .pi / 7

        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        applyDash(dash, width: width, in: ctx)
        ctx.beginPath()
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()
        // Head is always solid — a dashed/dotted chevron would look broken.
        ctx.setLineDash(phase: 0, lengths: [])

        let leftWing = CGPoint(x: end.x - headLength * cos(angle - headSpread), y: end.y - headLength * sin(angle - headSpread))
        let rightWing = CGPoint(x: end.x - headLength * cos(angle + headSpread), y: end.y - headLength * sin(angle + headSpread))

        ctx.beginPath()
        ctx.move(to: leftWing)
        ctx.addLine(to: end)
        ctx.addLine(to: rightWing)
        ctx.strokePath()
    }

    private static func drawString(_ string: String, at point: CGPoint, attributes: [NSAttributedString.Key: Any], in ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        (string as NSString).draw(at: point, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }
}

extension CGRect {
    init(point a: CGPoint, point b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
