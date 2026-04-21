import SwiftUI

// MARK: - Design tokens (Ambient Glass)
//
// Translates `design_handoff_kgen_eye/SPECS.md` into Swift. Everything in this
// file is scoped under `KE` so it can coexist with the legacy `EGOTheme` tokens
// while we A/B test the new look. Delete this file + revert the entry-point
// line in `EgoCaptureApp.swift` to roll back.

enum KE {
    // Accents
    static let accentGreen = Color(red: 127/255, green: 200/255, blue: 160/255)
    static let accentBlue  = Color(red: 140/255, green: 175/255, blue: 210/255)
    static let accentRed   = Color(red: 220/255, green: 110/255, blue: 110/255)
    static let ghostTint   = Color(red: 210/255, green: 222/255, blue: 240/255)

    // Ink
    static let ink1 = Color(red: 25/255, green: 40/255, blue: 55/255).opacity(0.92)
    static let ink2 = Color(red: 30/255, green: 45/255, blue: 65/255).opacity(0.72)
    static let ink3 = Color(red: 30/255, green: 45/255, blue: 65/255).opacity(0.55)

    // Glass rim
    static let edgeBright = Color.white.opacity(0.55)
    static let edgeShadow = Color(red: 60/255, green: 75/255, blue: 95/255).opacity(0.22)

    // Brand font. Variable Orbitron.ttf is shipped in the bundle; the PostScript
    // name for a specific weight is synthesised by CoreText.
    static func brand(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom("Orbitron", size: size).weight(weight)
    }
}

// MARK: - Glass primitives

/// Main inset pane. Goes on top of the live camera preview.
///
/// Padding defaults to the portrait Home inset (spec §3 Home). Override
/// `insets` for other layouts — e.g. landscape Recording uses 12/14/14/12.
struct GlassPane<Content: View>: View {
    var insets: EdgeInsets = EdgeInsets(top: 24, leading: 22, bottom: 28, trailing: 22)
    @ViewBuilder var content: () -> Content

    private let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)

    var body: some View {
        if #available(iOS 26.0, *) {
            // Native Apple Liquid Glass. Uses the `.clear` variant (much
            // more transparent than `.regular`) so a large pane still reads
            // as real lens glass rather than a frosted panel. `.regular`
            // adds a milky backdrop wash that is fine for small widgets but
            // overwhelms a full-screen surface.
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassEffect(.clear.interactive(), in: shape)
                .padding(insets)
        } else {
            legacyPane
                .shadow(color: Color(red: 30/255, green: 40/255, blue: 55/255).opacity(0.22),
                        radius: 20, x: 0, y: 10)
                .padding(insets)
        }
    }

    /// iOS 17/18 approximation: `.ultraThinMaterial` @ 0.75 + cool-blue
    /// top sheen + hand-drawn edge rims.
    private var legacyPane: some View {
        content()
            .background(
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 180/255, green: 205/255, blue: 235/255).opacity(0.18), location: 0.0),
                        .init(color: Color(red: 180/255, green: 205/255, blue: 235/255).opacity(0.04), location: 0.35),
                        .init(color: Color.clear, location: 0.65)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.75)
            )
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(KE.edgeBright, lineWidth: 1)
            )
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.75), .clear, KE.edgeShadow],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
                .padding(0.5)
                .blendMode(.overlay)
            )
    }
}

enum KEButtonVariant {
    case red, green, blue, ghost

    var tint: Color {
        switch self {
        case .red:   return KE.accentRed
        case .green: return KE.accentGreen
        case .blue:  return KE.accentBlue
        case .ghost: return KE.ghostTint
        }
    }
}

/// Primary pill button. 84pt tall, glass tint matching the variant.
///
/// Intentionally not a `Button` — we let the surrounding `NavigationLink` own
/// the gesture. Wrapping a Button inside a NavigationLink swallows the tap and
/// the link never activates.
struct KEPillButton: View {
    let label: LocalizedStringKey
    let systemImage: String
    var variant: KEButtonVariant = .green

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 24)
            Text(label)
                .font(.system(size: 17, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KE.ink3)
        }
        .foregroundStyle(KE.ink1)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 84)
        .modifier(KEPillSurface(tint: variant.tint, shape: shape))
        .modifier(KEPillShadows(tint: variant.tint))
        .contentShape(shape)
    }
}

/// Pills rely on the ambient `GlassEffectContainer` for depth on iOS 26, so
/// skip the manual drop shadows (which force SwiftUI to snapshot the pill as
/// an opaque layer for shadow rendering and break Liquid Glass refraction).
private struct KEPillShadows: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .shadow(color: tint.opacity(0.45), radius: 16, y: 4)
                .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
        }
    }
}

/// Glass surface for the Home-style pill.
///
/// On iOS 26 the surrounding `GlassPane` already has a native `.glassEffect`.
/// Adding a second Liquid Glass layer here causes the outer glass to
/// composite the pills as part of its own blur source — the whole pane then
/// reads as one uniformly milky frost. Instead, on iOS 26 the pills are a
/// simple translucent colour tile: the pane's glass provides the backdrop
/// blur, the pills provide the chroma. Older OSes keep the hand-crafted
/// sheen + rim recipe.
private struct KEPillSurface<S: InsettableShape>: ViewModifier {
    let tint: Color
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.22), location: 0.0),
                            .init(color: .white.opacity(0.0),  location: 0.55)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .background(tint.opacity(0.72))
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 1))
        } else {
            content
                .background(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.30), location: 0.0),
                            .init(color: .white.opacity(0.0),  location: 0.6)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .background(tint.opacity(0.55))
                .clipShape(shape)
                .overlay(shape.strokeBorder(tint.opacity(0.55), lineWidth: 1))
                .overlay(
                    shape.inset(by: 1)
                        .stroke(Color.white.opacity(0.55), lineWidth: 1.2)
                        .blendMode(.overlay)
                        .mask(
                            LinearGradient(
                                colors: [.white, .clear],
                                startPoint: .top, endPoint: .center
                            )
                        )
                )
                .overlay(
                    shape.inset(by: 1)
                        .stroke(Color.black.opacity(0.18), lineWidth: 1.2)
                        .blendMode(.overlay)
                        .mask(
                            LinearGradient(
                                colors: [.clear, .white],
                                startPoint: .center, endPoint: .bottom
                            )
                        )
                )
        }
    }
}

// MARK: - Brand lockup

/// KGeN Eye mark at the top of the Home pane. The artwork is drawn as a
/// native SwiftUI vector (see ``KGenEyeLogo``) so it stays sharp at every
/// scale factor and the glass rims can be tuned in code without exporting
/// a new SVG. The drop shadows match the mockup spec — one broad, soft
/// pass for ambient depth and one tight pass for edge contact.
struct GlassLogoBadge: View {
    /// Width of the mark. The aspect-preserving ``KGenEyeLogo`` derives its
    /// height from this (≈ ``width * 0.873``).
    private let artworkWidth: CGFloat = 240

    var body: some View {
        KGenEyeLogo(width: artworkWidth)
            .shadow(color: Color(red: 0.12, green: 0.18, blue: 0.25).opacity(0.12),
                    radius: 5, y: 8)
            .shadow(color: Color(red: 0.12, green: 0.18, blue: 0.26).opacity(0.10),
                    radius: 3, y: 4)
            .accessibilityHidden(true)
    }
}

struct BrandLockup: View {
    var body: some View {
        VStack(spacing: 6) {
            Text(verbatim: "KGeN© EYE")
                .font(KE.brand(23, weight: .bold))
                .tracking(2.4)
                .foregroundStyle(KE.ink1)
            Text("EGOCENTRIC YIELD ENGINE")
                .font(KE.brand(14, weight: .medium))
                .tracking(2.0)
                .foregroundStyle(KE.ink2)
        }
    }
}

// MARK: - Backdrop
//
// The design handoff ships with a static photograph (`bg-kitchen.jpg`) that
// stands in for the camera feed. Using it instead of a live `AVCaptureSession`
// keeps the Home screen fast, avoids requesting camera permission just to
// show a background, and matches the mockups exactly.

/// Static photographic backdrop used by every Home/nav scene.
///
/// SwiftUI's `Image.scaledToFill()` does *not* clip overflow by default, so
/// we pin the image to a `GeometryReader`-measured frame and clip it
/// explicitly. Otherwise the picture's wide aspect ratio bleeds past the
/// screen bounds and breaks the glass pane's layout.
///
/// A subtle top-to-bottom dark veil pushes the photograph's brightness down
/// so the glass pane's `ink1` / `ink2` text tokens stay readable — the spec's
/// ink alphas (0.92 / 0.72) were tuned for a live camera feed, not a bright
/// interior photo.
struct AmbientImageBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("bg-kitchen")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                LinearGradient(
                    colors: [
                        Color(red: 18/255, green: 26/255, blue: 40/255).opacity(0.10),
                        Color(red: 18/255, green: 26/255, blue: 40/255).opacity(0.04)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}

/// Full-screen backdrop for non-home scenes.
///
/// Now an alias for `AmbientImageBackdrop` — once internal screens were
/// ported to the light Ambient Glass chrome (dark ink on light glass cards)
/// the dark scrim became unnecessary.
struct AmbientStageBackdrop: View {
    var body: some View { AmbientImageBackdrop() }
}

// MARK: - Glass card
//
// Denser than the main pane. Mirrors `SPECS.md` §1 "Card" surface
// (rgba(240,246,254,0.30) + ultraThinMaterial, r:22). Used for list rows,
// settings groups and detail tiles on the non-home screens.

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            content().glassEffect(.regular, in: shape)
        } else {
            content()
                .background(
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 180/255, green: 205/255, blue: 235/255).opacity(0.14), location: 0.0),
                            .init(color: Color.clear, location: 0.55)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.75)
                )
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 1))
                .shadow(color: Color(red: 40/255, green: 55/255, blue: 80/255).opacity(0.14),
                        radius: 16, x: 0, y: 8)
        }
    }
}

// MARK: - Home view

struct KGenEyeHomeView: View {
    /// The pane's insets + corner radius. Duplicated here so the masked
    /// "extra blur" layer behind the glass lines up pixel-perfect with the
    /// `GlassPane` on top — both use the same padding and rounded rect.
    private let paneInsets = EdgeInsets(top: 24, leading: 22, bottom: 28, trailing: 22)
    private let paneCornerRadius: CGFloat = 36

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientImageBackdrop()

                // A second, blurred copy of the backdrop, masked to the
                // pane's exact shape. `.glassEffect(.clear)` has no blur
                // radius knob, so this layer is how we bump the perceived
                // blur inside the pane without blurring the entire screen
                // (which reads as "two sheets of glass stacked").
                AmbientImageBackdrop()
                    .blur(radius: 12)
                    .mask(
                        RoundedRectangle(cornerRadius: paneCornerRadius, style: .continuous)
                            .padding(paneInsets)
                    )
                    .allowsHitTesting(false)

                glassStack
            }
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.light)
    }

    /// Earlier we tried a `GlassEffectContainer` here to fuse pane + pill
    /// glass refractions. Empirically that produced the opposite of Liquid
    /// Glass — the container composited everything into one flat frosted
    /// block. Dropping it lets each glass surface capture the backdrop on
    /// its own, which is how Apple's own iOS 26 apps read.
    @ViewBuilder private var glassStack: some View {
        homePane
    }

    private var homePane: some View {
        GlassPane {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 66)
                        GlassLogoBadge()
                        Spacer().frame(height: 18)
                        BrandLockup()
                        Spacer(minLength: 24)

                        VStack(spacing: 14) {
                            NavigationLink {
                                ScenarioPickerView()
                            } label: {
                                KEPillButton(
                                    label: "Start Recording",
                                    systemImage: "play.fill",
                                    variant: .red
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                SessionListView()
                            } label: {
                                KEPillButton(
                                    label: "View Sessions",
                                    systemImage: "folder.fill",
                                    variant: .blue
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                SettingsView()
                            } label: {
                                KEPillButton(
                                    label: "Settings",
                                    systemImage: "gearshape.fill",
                                    variant: .ghost
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer().frame(height: 28)

                        Image("kgen-logo")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36)
                            .foregroundStyle(KE.accentBlue)
                            .opacity(0.85)

                        Spacer().frame(height: 20)
                    }
                    .padding(.horizontal, 44)
                }
    }
}

#Preview {
    KGenEyeHomeView()
}
