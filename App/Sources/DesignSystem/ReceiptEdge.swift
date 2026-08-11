import SwiftUI

/// The totals card: rounded on three sides, torn along the bottom into repeating
/// triangular notches 10 pt wide and 6 pt deep. A `Shape`, so it recolours with
/// appearance and resizes with the card instead of being a fixed image.
struct ReceiptEdge: Shape {
    /// Card corner radius, from the layout scale.
    var cornerRadius: CGFloat = 20
    /// Width of one notch along the bottom.
    var notchWidth: CGFloat = 10
    /// How far each notch dips below the card's baseline.
    var notchDepth: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Bottom edge sits above the frame so the notch tips land on rect.maxY.
        let baseline = max(rect.minY, rect.maxY - notchDepth)
        let radius = min(cornerRadius, min(rect.width, baseline - rect.minY) / 2)

        // Top edge, left to right, with rounded top corners.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
            radius: radius, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false
        )

        // Right side down to the tear.
        path.addLine(to: CGPoint(x: rect.maxX, y: baseline))

        // Tear: walk right to left, alternating tip and baseline.
        let step = max(notchWidth, 1) / 2
        var x = rect.maxX - step
        var atTip = true
        while x > rect.minX {
            path.addLine(to: CGPoint(x: x, y: atTip ? rect.maxY : baseline))
            atTip.toggle()
            x -= step
        }
        path.addLine(to: CGPoint(x: rect.minX, y: baseline))

        path.closeSubpath()
        return path
    }
}

/// The totals card background: receipt shape, hairline outline, one soft shadow
/// in light appearance and none in dark.
struct ReceiptCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ReceiptEdge()
            .fill(Palette.surface)
            .overlay(ReceiptEdge().stroke(Palette.separator, lineWidth: 1))
            .shadow(
                color: Palette.CardShadow.color(for: colorScheme),
                radius: Palette.CardShadow.radius,
                x: 0,
                y: Palette.CardShadow.yOffset
            )
    }
}

#Preview {
    VStack {
        Text("$49.99")
            .typography(Typography.display)
            .foregroundStyle(Palette.primary)
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(ReceiptCardBackground())
    }
    .padding(20)
    .background(Palette.background)
}
