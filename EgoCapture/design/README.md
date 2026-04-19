# Handoff: KGeN Eye — Key Visual (V1)

## Overview
A high-fidelity 9:16 vertical **key visual** for **KGeN Eye**, an egocentric (first-person POV) videos app. The visual is a single tall glassmorphism / "liquid glass" panel floating over a blurred warm-room POV backdrop, featuring the app's lens monogram, wordmark, feature pills, and accent shapes.

This is intended for **app-store hero, launch poster, or landing-page hero** use cases. It is cursor-reactive on web (refraction + subtle tilt) but reads as a strong static image when captured as a still.

## About the Design Files
The files in this bundle are **design references created in HTML** — a prototype showing intended look, proportions, and interaction. They are **not production code to copy directly**.

Your task is to **recreate this design in the target codebase's existing environment** (React web, React Native, SwiftUI, native Android, etc.) using its established component patterns, typography system, and styling conventions. If no environment exists yet, choose the framework most appropriate for the deliverable (e.g., React + Tailwind for web; SwiftUI for iOS key visual) and implement there.

For a purely static export (e.g. an App Store screenshot or poster PNG), you may also take a 1000×1778 screenshot of the reference HTML and retouch — but the HTML is the source of truth for layout, color, and typography.

## Fidelity
**High-fidelity (hifi).** Pixel-perfect mockup — final colors, typography, spacing, shape proportions, and micro-interactions are all dialed in. Recreate this pixel-perfectly using the codebase's existing glass/blur primitives if they exist, or implement the glass recipe documented below.

## Screens / Views

### 01 — KGeN Eye Key Visual (V1)
- **Name:** Key Visual V1 (single-panel vertical)
- **Purpose:** Marketing hero / app-store key art — introduces brand, tagline, and the POV nature of the product.
- **Canvas:** 1000 × 1778 px (9:16). Scales to viewport via `transform: scale()` on a fixed-size stage; on native, target 1080×1920 or 1170×2532 as appropriate.
- **Layout:** Full-bleed blurred POV background → single centered glass panel (520 × 1000 px inside the 1000 × 1778 canvas, top margin 40 px) containing stacked content.

#### Background layer
- **What:** Blurred warm-interior POV scene — hint of window light from upper-left, bokeh, warm brown/amber tones, subtle dark hand silhouette at bottom suggesting POV hands holding a device.
- **Construction (web):** Pure CSS radial + linear gradients, plus an SVG with ~22 blurred circles as bokeh. See `src/scene.jsx` → `PovScene` variant 1.
- **Key gradient:**
  ```
  radial-gradient(1200px 900px at 18% 30%, hsl(25 85% 72% / 0.9), transparent 55%),
  radial-gradient(900px 900px at 82% 70%, hsl(40 70% 40% / 0.7), transparent 60%),
  radial-gradient(600px 500px at 50% 100%, hsl(20 50% 20% / 0.9), transparent 70%),
  linear-gradient(180deg, hsl(25 40% 18%) 0%, hsl(45 30% 8%) 100%)
  ```
- **Vignette:** `radial-gradient(120% 80% at 50% 50%, transparent 55%, rgba(0,0,0,0.75) 100%)` on top.
- **For native/production:** Substitute a real blurred POV photograph (warm interior, shallow DOF) at the same mood.

#### Main glass panel (container)
- **Size:** 520 × 1000 px, centered horizontally, 40 px from top of canvas.
- **Radius:** 36 px
- **Glass recipe** (see Design Tokens → Glass):
  - `backdrop-filter: blur(22px) saturate(1.45) contrast(1.05)`
  - Tint layer: `rgba(255,255,255,0.08)` + diagonal white sheen 135°
  - Edge: 1px `rgba(255,255,255,0.32)` border + inset highlights (top `rgba(255,255,255,0.55)`, bottom `rgba(255,255,255,0.12)`, sides `rgba(255,255,255,0.18)`)
  - Outer glow: `0 30px 80px -20px rgba(47,128,237,0.33)` (blue accent glow)
  - Drop shadow: `0 24px 60px -30px rgba(0,0,0,0.8)`

#### Panel contents (top → bottom, 26 px gap, 44 px top / 36 px side padding)

1. **Header block** (centered column, 10 px gap)
   - **Eye monogram** — 84 px square. Rounded-square bezel (22 px radius) with concentric lens, 6 aperture blades, dark pupil, catchlight. Lens fill: radial gradient from `#CFFFD9` → `#3AE05C` → `#0c3a14`. Soft green bloom behind (`radial-gradient(closest-side, #3AE05C55, transparent 70%)`, 10 px blur).
   - **Wordmark:** `KGeN · EYE` — Space Grotesk 600, 18 px, uppercase, letter-spacing 0.34em, color white, subtle text-shadow `0 1px 0 rgba(0,0,0,0.25)`. The `·` separator at opacity 0.7.
   - **Version caption:** `v.04 · lens online` — JetBrains Mono 11 px, letter-spacing 0.18em, uppercase, `rgba(255,255,255,0.55)`.

2. **Shape row** (horizontal, 18 px gap, 6 px top margin, 88 px tall)
   - **Left:** Circular glass chip 78×78 px (radius 999). Contains a green pentagon (40×40) — fill `#3AE05C`, stroke `rgba(255,255,255,0.7)` at 3px.
   - **Right:** Two overlapping glass rectangles floating in a 220-ish wide area:
     - Back rect: 220×68 px, radius 22, offset `left:0, top:8`
     - Front rect: 160×80 px, radius 22, offset `left:150, top:0`
     - Both use the same glass recipe (no content).

3. **Feature pill — "Capture"** (52 px tall, radius 16, 18 px horizontal padding, blue accent glow `rgba(47,128,237,0.33)`)
   - Left column (flex 1):
     - Label: "Capture" — Space Grotesk 600, 15 px, color `#E8F1FF`
     - Mono subline: "POV · 4K · 120fps" — JetBrains Mono 10 px, letter-spacing 0.14em, `rgba(255,255,255,0.7)`
   - Right: 10×10 px circle dot, fill `#2F80ED`, glow `0 0 12px #2F80ED`

4. **Feature pill — "Relive"** (same dimensions, green accent glow `rgba(58,224,92,0.33)`)
   - Left: "Relive" (Space Grotesk 600, 15 px, `#E8FFE8`) / "spatial · stereo · tactile" (JetBrains Mono 10 px)
   - Right: 10×10 px circle, `#3AE05C`, glow `0 0 12px #3AE05C`

5. **Feature pill — "Share with a glance"** (52 px, no accent glow, neutral glass)
   - Single-line label, Space Grotesk 500, 14 px, `rgba(255,255,255,0.88)`.

6. **Tagline pill** (52 px, no accent glow)
   - Mono tagline: `EXPERIENCE YOUR ENVIRONMENT` — JetBrains Mono 11 px, letter-spacing 0.18em, uppercase, `rgba(255,255,255,0.72)`.

7. **Flex spacer** — pushes bottom shape down.

8. **Bottom diamond** (centered, 4 px bottom margin)
   - 54×54 SVG diamond. Fill `#3AE05C`, stroke `rgba(255,255,255,0.7)` @ 3px.
   - Drop-shadow filter: `drop-shadow(0 0 16px #3AE05Caa)`.

### States (hover / cursor-reactive)
The panel has a subtle **cursor-reactive refraction**:
- On mousemove anywhere in viewport, compute normalized `(dx, dy)` from panel center.
- Tilt the panel `rotateX(dy * -3deg) rotateY(dx * 3deg)` via CSS 3D transform.
- Move the specular highlight: `--px: dx*50%`, `--py: dy*50%` — feeds a radial-gradient shine.
- A proximity factor `prox = max(0, 1 - dist*0.6)` drives the shine opacity (`0.28 * prox`).
- Transition: `transform 280ms cubic-bezier(.2,.9,.2,1)`.

**Mobile:** No cursor. Substitute with device-tilt (`DeviceOrientationEvent`) or a slow autonomous ambient drift (e.g. 8s sine on `--px/--py`).

## Interactions & Behavior
This view is a **single key visual**, not a multi-screen flow. The only interactive behavior is the cursor-reactive panel shimmer/tilt described above. No navigation, no forms.

If used as a static export (poster, app-store screenshot), capture at 1× pixel ratio for 1000×1778, or 2–3× for print/retina.

## State Management
None. Stateless visual. (The HTML reference has a `variation` tweak state for exploring V1/V2/V3, but **only V1** is part of this handoff — ignore V2 and V3.)

## Design Tokens

### Colors

| Token | Hex | Usage |
|---|---|---|
| `--bg-0` | `oklch(0.12 0.03 260)` ≈ `#0A0E1A` | deepest background fallback |
| `--bg-1` | `oklch(0.18 0.05 260)` ≈ `#121A2D` | mid background |
| `--ink` | `#FFFFFF` (near-white, `oklch(0.98 0.01 260)`) | primary text on glass |
| `--ink-dim` | `rgba(255,255,255,0.82)` | secondary text |
| `--ink-mute` | `rgba(255,255,255,0.62)` | tertiary / caption |
| `--accent-green` | `#3AE05C` | brand green / Relive |
| `--accent-blue` | `#2F80ED` | brand blue / Capture |
| `--glass-tint` | `rgba(255,255,255,0.08)` | base glass fill |
| `--glass-stroke` | `rgba(255,255,255,0.32)` | glass 1px border |
| `--glass-highlight-top` | `rgba(255,255,255,0.55)` | inset top 1px |
| `--glass-highlight-bottom` | `rgba(255,255,255,0.12)` | inset bottom 1px |

Scene (background) palette uses HSL hues 15–45° (warm interior) for V1.

### Typography

- **Display / UI:** Space Grotesk (Google Fonts), weights 400 / 500 / 600 / 700
- **Mono / technical captions:** JetBrains Mono, weights 400 / 500

| Role | Font | Size | Weight | Letter-spacing | Example |
|---|---|---|---|---|---|
| Wordmark | Space Grotesk | 18 px | 600 | 0.34em | KGeN · EYE |
| Pill label | Space Grotesk | 15 px | 600 | normal | Capture |
| Pill body (neutral) | Space Grotesk | 14 px | 500 | normal | Share with a glance |
| Caption mono | JetBrains Mono | 10–11 px | 500 | 0.14em–0.18em | POV · 4K · 120fps |
| Section caption mono | JetBrains Mono | 11 px | 500 | 0.18em | v.04 · lens online |

### Spacing
Canvas-relative (based on 520 px panel width):
- Panel padding: 44 px top/bottom, 36 px sides
- Vertical gap between content blocks: 26 px
- Pill inner horizontal padding: 18 px
- Shape row gap: 18 px

### Border radius
- Main panel: 36 px
- Pills: 16 px
- Floating glass rectangles: 22 px
- Circular chip: 999 px
- Eye monogram bezel: 22 px

### Shadows & glows (the "glass recipe")

Apply in this stacking order on a glass surface:
```css
box-shadow:
  /* outer colored glow (optional, per accent) */
  0 30px 80px -20px rgba(47,128,237,0.33),
  /* outer drop shadow */
  0 24px 60px -30px rgba(0,0,0,0.8),
  /* very faint inner top */
  0 2px 0 rgba(255,255,255,0.06) inset;

/* the following must be applied as a 1px-border child OR via layered insets: */
border: 1px solid rgba(255,255,255,0.32);
box-shadow:
  inset 0  1px 0 rgba(255,255,255,0.55), /* top highlight */
  inset 0 -1px 0 rgba(255,255,255,0.12), /* bottom shade */
  inset 1px 0 0 rgba(255,255,255,0.18),  /* left rim */
  inset -1px 0 0 rgba(255,255,255,0.18); /* right rim */

backdrop-filter: blur(22px) saturate(1.45) contrast(1.05);
```

Glass fill layer (stacked between backdrop-filter and border):
```css
background:
  linear-gradient(135deg, rgba(255,255,255,0.22) 0%, rgba(255,255,255,0.02) 45%, rgba(255,255,255,0.16) 100%),
  rgba(255,255,255,0.08); /* tint */
```

### Glow map (by accent)
- **Blue glow:** `0 30px 80px -20px rgba(47,128,237,0.33)`
- **Green glow:** `0 30px 80px -20px rgba(58,224,92,0.33)`
- **Neutral (no accent):** omit outer colored glow; keep only the black drop shadow.

## Assets

All assets in this design are **generated in code**, no external imagery:

- **Eye monogram** — inline SVG (see `src/logo.jsx`). 100×100 viewBox. Contains bezel rect, concentric circles, 6 aperture lines, pupil, catchlight. For native, export this as a vector (SVG / PDF) or re-implement in code.
- **Floating shapes (pentagon, diamond, circle)** — inline SVG polygons/circles.
- **Background POV scene** — CSS gradients + SVG bokeh circles (no photo). For production, **swap in a real blurred POV photo** for more authenticity.

### Fonts
- [Space Grotesk](https://fonts.google.com/specimen/Space+Grotesk) — Google Fonts, SIL OFL.
- [JetBrains Mono](https://fonts.google.com/specimen/JetBrains+Mono) — Google Fonts, SIL OFL.

## Implementation notes

1. **`backdrop-filter` support** — well-supported on modern web and iOS (`-webkit-backdrop-filter`). For Android WebView or older contexts, fall back to a pre-blurred scaled background-image snippet behind each glass surface. On native Android, use `RenderEffect.createBlurEffect` (API 31+) or a pre-blurred bitmap.

2. **Element layering** — the glass panel is a composite of 5 absolutely-positioned layers inside a relative parent:
   1. `.glass-refract` — `backdrop-filter`
   2. `.glass-tint` — fill + diagonal gradient
   3. `.glass-shine` — moving specular highlight (cursor-driven radial)
   4. `.glass-edge` — 1px border + inset highlights
   5. `.glass-content` — the actual children (text, icons, nested glass)

   Keep the layer order; reordering breaks the specular reading.

3. **Nested glass** — pills inside the main panel also use the glass recipe. Nested `backdrop-filter` is valid in modern Safari/Chrome. The effective blur stacks, which is intentional (it reads as "thicker" glass where pills overlap the main panel).

4. **Performance** — 9 glass surfaces in V1 is fine on desktop. On mobile, consider reducing to 4 (main panel + 3 pills) and faking the others with static `rgba` fills if FPS drops during tilt.

5. **Text legibility on glass** — we rely on the inner tint + blur to keep contrast. Don't remove the `rgba(255,255,255,0.08)` tint; it's what gives text enough background to pass AA.

## Files included in this handoff

- `KGeN Eye.html` — entry HTML (loads Space Grotesk, JetBrains Mono, React, Babel, all source files)
- `src/scene.jsx` — POV background component (only V1 scene is relevant here)
- `src/glass.jsx` — `<GlassPanel>` and `<GlassPill>` primitives with cursor-reactive tilt/shine
- `src/logo.jsx` — `<EyeMark>` lens monogram and `<Wordmark>` component
- `src/variations.jsx` — contains `V1` component (lines covering the `V1` function). V2/V3 are **not** in scope for this handoff; you can ignore them.
- `src/app.jsx` — shell wiring, stage sizing, variation selector

The developer should **read V1 and the primitives** (`glass.jsx`, `logo.jsx`, `scene.jsx`) and **ignore V2, V3, and the Tweaks UI** (`src/tweaks.jsx`) — those were exploration scaffolding.
