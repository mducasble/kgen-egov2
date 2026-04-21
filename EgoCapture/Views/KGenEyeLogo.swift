import SwiftUI

/// Native SwiftUI recreation of the KGeN© EYE wordmark.
///
/// Renders the three glass shapes (center diamond, left / right arrows)
/// as vector paths so the logo scales crisply at any size without
/// shipping a rasterised asset. Replaces the previous ``Image("kgen-eye-logo")``
/// SVG asset that suffered from slight gradient banding when scaled up.
///
/// Usage:
/// ```swift
/// KGenEyeLogo(width: 240)
///     .shadow(color: .black.opacity(0.12), radius: 5, y: 8)
/// ```
///
/// Paths are traced from the original SVG (viewBox `0 0 1106.57 966.05`)
/// and normalised to the current frame so the geometry stays locked.
struct KGenEyeLogo: View {
    let width: CGFloat

    /// Preserves the original 1106.57 × 966.05 aspect ratio.
    private var height: CGFloat { width * (966.05 / 1106.57) }

    var body: some View {
        ZStack {
            // Left bracket is nudged 5pt to the right so its distance to the
            // diamond matches the right bracket's. The traced `LeftArrow`
            // opens slightly further out than `RightArrow`; this small
            // offset closes that visual gap without redrawing the path.
            GlassShape(fill: .clear) { LeftArrow() }
                .offset(x: 15)
            GlassShape(fill: .clear) { RightArrow() }
            GlassShape(fill: .green) { CenterDiamond() }
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Fill variants

/// Two glass body variants used by the mark. ``clear`` for the arrows,
/// ``green`` for the center diamond. Mirrors the SVG's `glassBody` /
/// `glassBodyGreen` gradients.
enum KGenEyeLogoFill {
    case clear
    case green

    var bodyGradient: LinearGradient {
        switch self {
        case .clear:
            return LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.55), location: 0),
                    .init(color: Color(red: 0.94, green: 0.96, blue: 0.99).opacity(0.32), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
        case .green:
            return LinearGradient(
                stops: [
                    .init(color: Color(red: 0.94, green: 1.00, blue: 0.75).opacity(0.72), location: 0),
                    .init(color: Color(red: 0.72, green: 0.88, blue: 0.31).opacity(0.72), location: 0.5),
                    .init(color: Color(red: 0.58, green: 0.78, blue: 0.22).opacity(0.70), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}

// MARK: - Glass treatment

/// Stacks a filled shape with the four rim passes that give each KGeN
/// mark element its glass look: outer hairline + inner specular highlight
/// + mid soft white + dark bottom edge.
///
/// ``.mask(shape)`` on the stroke passes is how we simulate SVG's `inset`
/// shadows — strokes are centered in SwiftUI, so masking trims the outer
/// half and leaves only the inner rim.
private struct GlassShape<S: Shape>: View {
    let fill: KGenEyeLogoFill
    let shape: S

    init(fill: KGenEyeLogoFill, @ViewBuilder shape: () -> S) {
        self.fill = fill
        self.shape = shape()
    }

    var body: some View {
        ZStack {
            shape.fill(fill.bodyGradient)

            shape.stroke(Color.white.opacity(0.75), lineWidth: 6)
                .mask(shape)

            shape.stroke(Color.white.opacity(0.30), lineWidth: 3)
                .mask(shape)
                .offset(x: 0, y: 1)

            shape.stroke(Color(red: 0.16, green: 0.22, blue: 0.31).opacity(0.22), lineWidth: 2)
                .mask(shape)
                .offset(x: 0, y: -1)

            shape.stroke(Color.white.opacity(0.55), lineWidth: 1.5)
        }
    }
}

// MARK: - Shapes (normalised to the 1106.57 × 966.05 viewBox)

/// Rounded square rotated 45° around its own center to form the diamond.
private struct CenterDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.width * (553.28 / 1106.57)
        let cy = rect.height * (483.02 / 966.05)
        let side = rect.width * (348.8 / 1106.57)
        let radius = rect.width * (23.7 / 1106.57)

        var p = Path()
        p.addRoundedRect(
            in: CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side),
            cornerSize: CGSize(width: radius, height: radius)
        )
        return p.applying(
            CGAffineTransform(translationX: cx, y: cy)
                .rotated(by: -.pi / 4)
                .translatedBy(x: -cx, y: -cy)
        )
    }
}

/// Left-pointing chevron with two stub feet (the decorative notches that
/// connect to the inner pair of lines in the SVG).
private struct LeftArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let sx: (CGFloat) -> CGFloat = { $0 / 1106.57 * w }
        let sy: (CGFloat) -> CGFloat = { $0 / 966.05 * h }

        var p = Path()
        p.move(to: CGPoint(x: sx(192.42), y: sy(500.04)))
        p.addLine(to: CGPoint(x: sx(377.84), y: sy(685.49)))
        p.addQuadCurve(to: CGPoint(x: sx(377.41), y: sy(708.87)),
                       control: CGPoint(x: sx(384.35), y: sy(692.00)))
        p.addLine(to: CGPoint(x: sx(284.13), y: sy(795.58)))
        p.addQuadCurve(to: CGPoint(x: sx(261.56), y: sy(795.15)),
                       control: CGPoint(x: sx(277.72), y: sy(801.54)))
        p.addLine(to: CGPoint(x: sx(3.47), y: sy(536.04)))
        p.addQuadCurve(to: CGPoint(x: sx(9.77), y: sy(520.87)),
                       control: CGPoint(x: sx(-2.12), y: sy(530.43)))
        p.addLine(to: CGPoint(x: sx(70.79), y: sy(520.87)))
        p.addQuadCurve(to: CGPoint(x: sx(87.03), y: sy(504.63)),
                       control: CGPoint(x: sx(79.76), y: sy(520.87)))
        p.addLine(to: CGPoint(x: sx(87.03), y: sy(461.43)))
        p.addQuadCurve(to: CGPoint(x: sx(70.79), y: sy(445.19)),
                       control: CGPoint(x: sx(87.03), y: sy(452.46)))
        p.addLine(to: CGPoint(x: sx(8.91), y: sy(445.19)))
        p.addQuadCurve(to: CGPoint(x: sx(2.56), y: sy(430.07)),
                       control: CGPoint(x: sx(1.03), y: sy(435.70)))
        p.addLine(to: CGPoint(x: sx(261.37), y: sy(165.94)))
        p.addQuadCurve(to: CGPoint(x: sx(284.25), y: sy(165.62)),
                       control: CGPoint(x: sx(267.61), y: sy(159.57)))
        p.addLine(to: CGPoint(x: sx(378.53), y: sy(256.53)))
        p.addQuadCurve(to: CGPoint(x: sx(378.74), y: sy(279.71)),
                       control: CGPoint(x: sx(385.07), y: sy(262.84)))
        p.addLine(to: CGPoint(x: sx(192.42), y: sy(466.03)))
        p.addQuadCurve(to: CGPoint(x: sx(192.42), y: sy(500.04)),
                       control: CGPoint(x: sx(183.03), y: sy(475.42)))
        p.closeSubpath()
        return p
    }
}

/// Right-pointing chevron mirrored around the vertical axis.
private struct RightArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let sx: (CGFloat) -> CGFloat = { $0 / 1106.57 * w }
        let sy: (CGFloat) -> CGFloat = { $0 / 966.05 * h }

        var p = Path()
        p.move(to: CGPoint(x: sx(976.45), y: sy(520.87)))
        p.addLine(to: CGPoint(x: sx(1096.88), y: sy(520.87)))
        p.addQuadCurve(to: CGPoint(x: sx(1103.72), y: sy(537.39)),
                       control: CGPoint(x: sx(1105.50), y: sy(531.29)))
        p.addLine(to: CGPoint(x: sx(680.45), y: sy(960.69)))
        p.addQuadCurve(to: CGPoint(x: sx(654.56), y: sy(960.69)),
                       control: CGPoint(x: sx(673.30), y: sy(967.84)))
        p.addLine(to: CGPoint(x: sx(531.09), y: sy(837.22)))
        p.addQuadCurve(to: CGPoint(x: sx(531.09), y: sy(811.33)),
                       control: CGPoint(x: sx(523.94), y: sy(830.07)))
        p.addLine(to: CGPoint(x: sx(840.50), y: sy(501.92)))
        p.addQuadCurve(to: CGPoint(x: sx(840.50), y: sy(464.13)),
                       control: CGPoint(x: sx(850.94), y: sy(491.48)))
        p.addLine(to: CGPoint(x: sx(531.09), y: sy(154.72)))
        p.addQuadCurve(to: CGPoint(x: sx(531.09), y: sy(128.83)),
                       control: CGPoint(x: sx(523.94), y: sy(147.57)))
        p.addLine(to: CGPoint(x: sx(654.56), y: sy(5.36)))
        p.addQuadCurve(to: CGPoint(x: sx(680.45), y: sy(5.36)),
                       control: CGPoint(x: sx(661.71), y: sy(-1.79)))
        p.addLine(to: CGPoint(x: sx(1103.72), y: sy(428.66)))
        p.addQuadCurve(to: CGPoint(x: sx(1096.88), y: sy(445.19)),
                       control: CGPoint(x: sx(1109.81), y: sy(435.17)))
        p.addLine(to: CGPoint(x: sx(976.45), y: sy(445.19)))
        p.addQuadCurve(to: CGPoint(x: sx(958.14), y: sy(463.50)),
                       control: CGPoint(x: sx(966.34), y: sy(445.19)))
        p.addLine(to: CGPoint(x: sx(958.14), y: sy(502.56)))
        p.addQuadCurve(to: CGPoint(x: sx(976.45), y: sy(520.87)),
                       control: CGPoint(x: sx(958.14), y: sy(512.67)))
        p.closeSubpath()
        return p
    }
}

#Preview {
    KGenEyeLogo(width: 240)
        .shadow(color: Color(red: 0.12, green: 0.18, blue: 0.25).opacity(0.12), radius: 5, y: 8)
        .shadow(color: Color(red: 0.12, green: 0.18, blue: 0.26).opacity(0.10), radius: 3, y: 4)
        .padding(40)
        .background(Color(red: 0.96, green: 0.97, blue: 1.0))
}
