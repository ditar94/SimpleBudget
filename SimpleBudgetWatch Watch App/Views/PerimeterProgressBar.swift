import SwiftUI

/// A rounded rectangle progress bar that hugs the watch screen perimeter.
/// Matches main app's dial styling with primaryBlue color scheme.
struct PerimeterProgressBar: View {
    let progress: Double
    let isOverBudget: Bool
    let indicatorProgress: Double

    private let lineWidth: CGFloat = 6
    private let cornerRadius: CGFloat = 54

    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 1
            let rect = CGRect(
                x: inset,
                y: inset,
                width: geometry.size.width - inset * 2,
                height: geometry.size.height - inset * 2
            )

            ZStack {
                // Background track matching main app's dial (primaryBlue.opacity(0.12))
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        Self.primaryBlue.opacity(0.12),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .padding(inset)

                // Main progress stroke (no glow)
                if isOverBudget {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            Color.red,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .padding(inset)
                } else if progress > 0 {
                    PerimeterShape(cornerRadius: cornerRadius, progress: min(max(progress, 0), 1))
                        .stroke(
                            progressGradient,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .padding(inset)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: progress)
                }

                // Indicator dot (no glow)
                if indicatorProgress > 0 {
                    PerimeterIndicator(
                        cornerRadius: cornerRadius,
                        progress: indicatorProgress,
                        rect: rect,
                        dotSize: lineWidth + 2,
                        fillColor: Self.primaryText
                    )
                    .animation(Animation.spring(response: 0.3, dampingFraction: 0.7), value: indicatorProgress)
                }
            }
        }
    }

    // Color palette matching main app exactly
    private static let primaryBlue = Color(red: 0.25, green: 0.55, blue: 1.0)
    private static let primaryText = Color(red: 0.12, green: 0.14, blue: 0.2)

    // Gradient matching main app's angular gradient on the dial
    private var progressGradient: LinearGradient {
        LinearGradient(
            colors: [Self.primaryBlue.opacity(0.3), Self.primaryBlue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Indicator Dot

struct PerimeterIndicator: View {
    let cornerRadius: CGFloat
    let progress: Double
    let rect: CGRect
    let dotSize: CGFloat
    var fillColor: Color = .white

    var body: some View {
        Circle()
            .fill(fillColor)
            .frame(width: dotSize, height: dotSize)
            .position(pointOnPerimeter(progress: progress, in: rect, cornerRadius: cornerRadius))
    }

    private func pointOnPerimeter(progress: Double, in rect: CGRect, cornerRadius: CGFloat) -> CGPoint {
        let cr = min(cornerRadius, min(rect.width, rect.height) / 2)
        let straightSections = 2 * (rect.width - 2 * cr) + 2 * (rect.height - 2 * cr)
        let cornerArcs = 2 * .pi * cr
        let totalLength = straightSections + cornerArcs

        let wrappedProgress = progress.truncatingRemainder(dividingBy: 1.0)
        let targetDistance = wrappedProgress * totalLength

        let topHalf = (rect.width - 2 * cr) / 2
        let cornerLength = (.pi / 2) * cr

        var distance = targetDistance

        // Top edge (from center to right)
        if distance <= topHalf {
            return CGPoint(x: rect.midX + distance, y: rect.minY)
        }
        distance -= topHalf

        // Top-right corner
        if distance <= cornerLength {
            let angle = -(.pi / 2) + (distance / cr)
            return CGPoint(
                x: rect.maxX - cr + cr * cos(angle),
                y: rect.minY + cr + cr * sin(angle)
            )
        }
        distance -= cornerLength

        // Right edge
        let rightEdge = rect.height - 2 * cr
        if distance <= rightEdge {
            return CGPoint(x: rect.maxX, y: rect.minY + cr + distance)
        }
        distance -= rightEdge

        // Bottom-right corner
        if distance <= cornerLength {
            let angle = 0 + (distance / cr)
            return CGPoint(
                x: rect.maxX - cr + cr * cos(angle),
                y: rect.maxY - cr + cr * sin(angle)
            )
        }
        distance -= cornerLength

        // Bottom edge
        let bottomEdge = rect.width - 2 * cr
        if distance <= bottomEdge {
            return CGPoint(x: rect.maxX - cr - distance, y: rect.maxY)
        }
        distance -= bottomEdge

        // Bottom-left corner
        if distance <= cornerLength {
            let angle = (.pi / 2) + (distance / cr)
            return CGPoint(
                x: rect.minX + cr + cr * cos(angle),
                y: rect.maxY - cr + cr * sin(angle)
            )
        }
        distance -= cornerLength

        // Left edge
        let leftEdge = rect.height - 2 * cr
        if distance <= leftEdge {
            return CGPoint(x: rect.minX, y: rect.maxY - cr - distance)
        }
        distance -= leftEdge

        // Top-left corner
        if distance <= cornerLength {
            let angle = .pi + (distance / cr)
            return CGPoint(
                x: rect.minX + cr + cr * cos(angle),
                y: rect.minY + cr + cr * sin(angle)
            )
        }
        distance -= cornerLength

        // Back to top center
        return CGPoint(x: rect.minX + cr + distance, y: rect.minY)
    }
}

// MARK: - Perimeter Shape

struct PerimeterShape: Shape {
    let cornerRadius: CGFloat
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let fullPath = createRoundedRectPath(in: rect)
        return fullPath.trimmedPath(from: 0, to: progress)
    }

    private func createRoundedRectPath(in rect: CGRect) -> Path {
        var path = Path()
        let minDimension = min(rect.width, rect.height)
        let cr = min(cornerRadius, minDimension / 2)

        path.move(to: CGPoint(x: rect.midX, y: rect.minY))

        path.addLine(to: CGPoint(x: rect.maxX - cr, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - cr, y: rect.minY + cr),
            radius: cr,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cr))
        path.addArc(
            center: CGPoint(x: rect.maxX - cr, y: rect.maxY - cr),
            radius: cr,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: rect.minX + cr, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + cr, y: rect.maxY - cr),
            radius: cr,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cr))
        path.addArc(
            center: CGPoint(x: rect.minX + cr, y: rect.minY + cr),
            radius: cr,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))

        return path
    }
}

#Preview {
    ZStack {
        Color(red: 0.96, green: 0.97, blue: 0.99)
        PerimeterProgressBar(progress: 0.6, isOverBudget: false, indicatorProgress: 0.6)
    }
}
