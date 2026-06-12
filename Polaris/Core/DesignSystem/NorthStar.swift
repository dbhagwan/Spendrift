import SwiftUI

/// The app mark: a concave four-point star (astroid — |cos|ᵃ, |sin|ᵃ), the
/// same curve the app icon uses, points at the compass directions.
struct NorthStarShape: Shape {
    var exponent: CGFloat = 3.4

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        let samples = 240
        for i in 0...samples {
            let theta = CGFloat(i) / CGFloat(samples) * 2 * .pi
            let c = cos(theta), s = sin(theta)
            let point = CGPoint(
                x: center.x + radius * pow(abs(c), exponent) * (c < 0 ? -1 : 1),
                y: center.y + radius * pow(abs(s), exponent) * (s < 0 ? -1 : 1)
            )
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

/// The onboarding hero: a market line climbing from the lower-left to the
/// point where the North Star ignites. Drawn with `.trim` so it animates
/// like a chart coming to life. `endPoint` is exposed so the star can sit
/// exactly where the line finishes.
struct TrendToStarShape: Shape {
    /// Normalized waypoints of the climb (a believable market walk).
    static let waypoints: [CGPoint] = [
        CGPoint(x: 0.04, y: 0.94),
        CGPoint(x: 0.20, y: 0.78),
        CGPoint(x: 0.32, y: 0.86),
        CGPoint(x: 0.48, y: 0.56),
        CGPoint(x: 0.58, y: 0.66),
        CGPoint(x: 0.74, y: 0.26),
    ]

    static var endPoint: CGPoint { waypoints[waypoints.count - 1] }

    func path(in rect: CGRect) -> Path {
        let points = Self.waypoints.map {
            CGPoint(x: $0.x * rect.width, y: $0.y * rect.height)
        }
        var path = Path()
        path.move(to: points[0])
        // Smooth through midpoints so the walk reads as one fluid stroke.
        for i in 1..<points.count {
            let previous = points[i - 1]
            let current = points[i]
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}
