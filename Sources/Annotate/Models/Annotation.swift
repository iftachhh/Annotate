import AppKit

enum AnnotationKind {
    case pen, line, arrow, highlighter, rectangle, circle, text, counter, image
}

struct Annotation: Identifiable {
    let id = UUID()
    var kind: AnnotationKind
    var points: [CGPoint]
    var color: NSColor
    var lineWidth: CGFloat
    var text: String = ""
    var counterValue: Int = 0
    var fontSize: CGFloat = 17
    var isBold: Bool = true
    var lineStyle: LineStyle = .solid
    var fontStyle: TextFontStyle = .sansSerif
    /// Only used when kind == .image — set once the eraser rasterizes a line/arrow/rectangle/circle
    /// (see OverlayView.rasterize). points[0]/points[1] give this image's placement rect.
    var image: CGImage?

    private var textFont: NSFont {
        fontStyle.font(size: fontSize, bold: isBold, text: text)
    }

    var boundingBox: CGRect {
        switch kind {
        case .text:
            guard let anchor = points.first else { return .zero }
            let size = (text as NSString).size(withAttributes: [.font: textFont])
            // RTL text is anchored at its right edge — see AnnotationRenderer.
            let origin = text.isRTLText ? CGPoint(x: anchor.x - size.width, y: anchor.y) : anchor
            return CGRect(origin: origin, size: size)
        case .counter:
            guard let origin = points.first else { return .zero }
            let diameter: CGFloat = fontSize * 1.6
            return CGRect(x: origin.x - diameter / 2, y: origin.y - diameter / 2, width: diameter, height: diameter)
        case .image:
            guard points.count == 2 else { return .zero }
            return CGRect(point: points[0], point: points[1])
        default:
            // NaN sentinels (eraser gap markers within pen/highlighter points) must be excluded
            // here — Swift's min/max comparisons are undefined in the presence of NaN.
            let clean = points.filter { !$0.x.isNaN }
            guard !clean.isEmpty else { return .zero }
            let xs = clean.map(\.x), ys = clean.map(\.y)
            let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
            return CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
                .insetBy(dx: -lineWidth, dy: -lineWidth)
        }
    }

    func hitTest(_ point: CGPoint) -> Bool {
        switch kind {
        case .pen, .highlighter:
            return Self.strokeContains(points, point, within: max(lineWidth, 8))
        case .line, .arrow:
            guard points.count == 2 else { return false }
            return point.distanceToSegment(points[0], points[1]) <= max(lineWidth, 8)
        case .text, .counter:
            // Wider margin than shapes: a miss here doesn't just fail to select — it silently
            // starts a brand-new text annotation (with current tool defaults) right on top of the
            // one the user meant to reopen, which reads as "its styling reset for no reason."
            return boundingBox.insetBy(dx: -8, dy: -8).contains(point)
        case .rectangle, .circle, .image:
            return boundingBox.insetBy(dx: -4, dy: -4).contains(point)
        }
    }

    mutating func translate(by delta: CGVector) {
        points = points.map { CGPoint(x: $0.x + delta.dx, y: $0.y + delta.dy) }
    }

    /// True if `point` lies within `radius` of the stroke — checked against every stored point AND
    /// every segment between consecutive (non-gap) points, not just the points themselves. Freehand
    /// strokes sample densely enough that point-only proximity used to be equivalent, but a
    /// shift-constrained straight pen/highlighter segment is stored as just its two endpoints —
    /// point-only checking would miss the entire middle of the line.
    static func strokeContains(_ points: [CGPoint], _ point: CGPoint, within radius: CGFloat) -> Bool {
        for i in points.indices {
            let p = points[i]
            if p.x.isNaN { continue }
            if p.distance(to: point) <= radius { return true }
            if i > 0, !points[i - 1].x.isNaN, point.distanceToSegment(points[i - 1], p) <= radius { return true }
        }
        return false
    }

    /// Inserts interpolated points along any segment between consecutive (non-gap) points longer
    /// than `step` — a shift-constrained straight pen/highlighter segment is stored as just its two
    /// endpoints, so without this, subtract(_:erasing:radius:) below would find no interior points
    /// to remove and erasing the middle of the line would silently do nothing.
    private static func densified(_ points: [CGPoint], step: CGFloat = 4) -> [CGPoint] {
        guard points.count > 1 else { return points }
        var result: [CGPoint] = [points[0]]
        for i in 1..<points.count {
            let prev = points[i - 1], curr = points[i]
            if !prev.x.isNaN, !curr.x.isNaN {
                let distance = prev.distance(to: curr)
                let steps = Int((distance / step).rounded(.up))
                if steps > 1 {
                    for s in 1..<steps {
                        let t = CGFloat(s) / CGFloat(steps)
                        result.append(CGPoint(x: prev.x + (curr.x - prev.x) * t, y: prev.y + (curr.y - prev.y) * t))
                    }
                }
            }
            result.append(curr)
        }
        return result
    }

    /// Removes every point within `radius` of `erasePoint`, marking the resulting gap with a NaN
    /// sentinel (rather than splitting into separate arrays/annotations) — this is what lets the
    /// eraser carve a hole out of a pen/highlighter stroke while it stays exactly one
    /// Annotation/layer throughout, same id and everything.
    static func subtract(_ points: [CGPoint], erasing erasePoint: CGPoint, radius: CGFloat) -> [CGPoint] {
        var result: [CGPoint] = []
        var justRemoved = false
        for p in densified(points) {
            if p.distance(to: erasePoint) <= radius {
                justRemoved = true
                continue
            }
            if justRemoved, !result.isEmpty, !result.last!.x.isNaN {
                result.append(CGPoint(x: CGFloat.nan, y: CGFloat.nan))
            }
            result.append(p)
            justRemoved = false
        }
        return result
    }

    /// True if any contiguous (non-gap) run in a NaN-marked point list has enough points to
    /// actually draw something — used to tell "still has visible ink" from "fully erased."
    static func hasVisibleContent(_ points: [CGPoint]) -> Bool {
        var runLength = 0
        for p in points {
            if p.x.isNaN { runLength = 0; continue }
            runLength += 1
            if runLength >= 2 { return true }
        }
        return false
    }
}

extension AnnotationKind {
    /// Maps a placed annotation back to the tool that draws its kind, so the context menu can
    /// look up which controls (color/width/style) apply when editing an existing layer directly.
    /// `.image` (eraser-rasterized shapes) has no editable appearance, hence nil.
    var asToolType: ToolType? {
        switch self {
        case .pen: return .pen
        case .line: return .line
        case .arrow: return .arrow
        case .highlighter: return .highlighter
        case .rectangle: return .rectangle
        case .circle: return .circle
        case .text: return .text
        case .counter: return .counter
        case .image: return nil
        }
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }

    func distanceToSegment(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0 { return distance(to: a) }
        var t = ((x - a.x) * dx + (y - a.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        let projection = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return distance(to: projection)
    }
}
