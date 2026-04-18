import SwiftUI

// MARK: - Tokens

enum EGOTheme {
    // Neutrals
    static let canvas = Color(red: 0.09, green: 0.10, blue: 0.12)
    static let canvasTop = Color(red: 0.14, green: 0.15, blue: 0.17)
    static let canvasBottom = Color(red: 0.06, green: 0.07, blue: 0.08)

    // Text (on glass over dark canvas)
    static let textPrimary = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let textSecondary = Color(red: 0.78, green: 0.81, blue: 0.85)
    static let textMuted = Color(red: 0.58, green: 0.62, blue: 0.68)

    // Brand / UI accents
    static let brandGreen = Color(red: 0.30, green: 0.90, blue: 0.36)
    static let accentBlue = Color(red: 0.24, green: 0.60, blue: 1.00)
    static let accentGreen = Color(red: 0.33, green: 0.85, blue: 0.40)
    static let accentNeutral = Color(red: 0.82, green: 0.84, blue: 0.87)

    // Legacy pastels (still referenced elsewhere, kept for compatibility)
    static let mint = accentGreen
    static let sky = accentBlue
    static let blush = Color(red: 0.96, green: 0.78, blue: 0.82)
    static let peach = Color(red: 0.98, green: 0.86, blue: 0.72)
    static let lemon = Color(red: 0.96, green: 0.92, blue: 0.62)

    static let blobMint = accentGreen.opacity(0.22)
    static let blobSky = accentBlue.opacity(0.20)
    static let blobPink = Color(red: 0.98, green: 0.60, blue: 0.78).opacity(0.18)

    static let recordPink = Color(red: 0.98, green: 0.60, blue: 0.65)
    static let recordInner = Color(red: 0.95, green: 0.30, blue: 0.36)
    static let framingGreen = Color(red: 0.55, green: 0.88, blue: 0.65)
}

// MARK: - Background

/// Deep, moody background that lets the material really show up.
struct EGOBlobBackground: View {
    @State private var shift = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [EGOTheme.canvasTop, EGOTheme.canvas, EGOTheme.canvasBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            blob(EGOTheme.blobMint, w: 360, h: 280, x: shift ? -150 : -110, y: -220, blur: 110)
            blob(EGOTheme.blobSky,  w: 380, h: 320, x: shift ?  150 : 110,  y: 200,  blur: 120)
            blob(EGOTheme.blobPink, w: 300, h: 260, x: shift ?  120 : 80,   y: -120, blur: 90)

            // Subtle vignette to push focus inward
            RadialGradient(
                colors: [.clear, .black.opacity(0.35)],
                center: .center,
                startRadius: 180,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                shift.toggle()
            }
        }
    }

    private func blob(_ color: Color, w: CGFloat, h: CGFloat, x: CGFloat, y: CGFloat, blur: CGFloat) -> some View {
        Ellipse()
            .fill(color)
            .frame(width: w, height: h)
            .blur(radius: blur)
            .offset(x: x, y: y)
    }
}

// MARK: - Glass primitives

enum EGOGlassTint {
    case neutral
    case blue
    case green
    case custom(Color)

    var color: Color {
        switch self {
        case .neutral: return EGOTheme.accentNeutral
        case .blue: return EGOTheme.accentBlue
        case .green: return EGOTheme.accentGreen
        case .custom(let c): return c
        }
    }

    var isNeutral: Bool {
        if case .neutral = self { return true }
        return false
    }
}

/// Translucent glass surface with top highlight, gradient border and drop shadow.
struct EGOGlassBackground: View {
    let cornerRadius: CGFloat
    let tint: EGOGlassTint
    /// 0 = neutral frosted, 1 = strongly tinted (for CTAs).
    let tintStrength: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            // 1. Frosted base
            shape
                .fill(.ultraThinMaterial)

            // 2. Soft tint wash
            shape
                .fill(tint.color.opacity(0.10 + tintStrength * 0.30))

            // 3. Top-to-bottom light falloff (gives the "depth")
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22 + tintStrength * 0.10),
                            Color.white.opacity(0.04),
                            Color.black.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.plusLighter)
                .opacity(0.9)

            // 4. Inner specular highlight stripe (very thin)
            shape
                .trim(from: 0, to: 0.5)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.85), .white.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .blendMode(.plusLighter)

            // 5. Gradient border (top-left bright, bottom-right dim + tinted)
            shape
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            tint.color.opacity(0.35 + tintStrength * 0.35),
                            Color.black.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        // 6. Outer floating shadow
        .shadow(color: .black.opacity(0.35), radius: 18, y: 12)
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }
}

struct EGOGlassCapsuleBackground: View {
    let tint: EGOGlassTint
    let tintStrength: Double

    var body: some View {
        let shape = Capsule(style: .continuous)
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(tint.color.opacity(0.18 + tintStrength * 0.38))
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28 + tintStrength * 0.12),
                            Color.white.opacity(0.04),
                            Color.black.opacity(0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.plusLighter)
                .opacity(0.9)
            shape
                .trim(from: 0, to: 0.5)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
                .blendMode(.plusLighter)
            shape
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.6),
                            tint.color.opacity(0.45 + tintStrength * 0.35),
                            Color.black.opacity(0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: tint.color.opacity(0.25 + tintStrength * 0.2), radius: 14, y: 8)
        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
    }
}

/// Convenient panel wrapper.
struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var tint: EGOGlassTint = .neutral
    var tintStrength: Double = 0
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                EGOGlassBackground(cornerRadius: cornerRadius, tint: tint, tintStrength: tintStrength)
            }
    }
}

/// Tinted glass pill — used for the colored CTAs in the reference.
struct GlassPill<Content: View>: View {
    var tint: EGOGlassTint
    var tintStrength: Double = 1
    var height: CGFloat = 54
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .padding(.horizontal, 18)
            .background {
                EGOGlassCapsuleBackground(tint: tint, tintStrength: tintStrength)
            }
    }
}

// MARK: - Reused atoms

struct EGOCaptureTopPill: View {
    let title: String
    var showDot: Bool = false
    var dotColor: Color = EGOTheme.recordInner

    var body: some View {
        HStack(spacing: 8) {
            if showDot {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: dotColor.opacity(0.6), radius: 4)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(EGOTheme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            EGOGlassCapsuleBackground(tint: .neutral, tintStrength: 0.2)
        }
    }
}

/// Four mint corner brackets for viewfinder framing.
struct EGOFramingCorners: View {
    var size: CGFloat = 120
    var lineWidth: CGFloat = 3
    var length: CGFloat = 22
    var color: Color = EGOTheme.framingGreen

    var body: some View {
        ZStack {
            cornerL
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            cornerL
                .scaleEffect(x: -1, y: 1, anchor: .center)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            cornerL
                .scaleEffect(x: 1, y: -1, anchor: .center)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            cornerL
                .scaleEffect(x: -1, y: -1, anchor: .center)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: size, height: size)
    }

    private var cornerL: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: length))
            p.addLine(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: length, y: 0))
        }
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        .frame(width: length, height: length, alignment: .topLeading)
    }
}

struct EGOViewfinderGrid: View {
    var lineOpacity: Double = 0.12

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                for i in 1..<3 {
                    let x = w * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: h))
                }
                for j in 1..<3 {
                    let y = h * CGFloat(j) / 3
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: w, y: y))
                }
            }
            .stroke(.white.opacity(lineOpacity), lineWidth: 0.5)
        }
    }
}
