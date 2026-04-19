// GlassPanel — liquid-glass surface with cursor-reactive refraction.
// Uses:
//  - backdrop-filter for real blur of what's behind it
//  - SVG feDisplacementMap tied to mouse proximity for refraction/warp
//  - layered inner highlight + edge specular + outer glow

const { useEffect, useRef, useState } = React;

function GlassPanel({
  children,
  radius = 28,
  tintOpacity,
  blurPx,
  accent,              // optional accent color for outer glow
  accentSide = 'all',  // 'top'|'bottom'|'all'
  interactive = true,
  style = {},
  className = '',
  shine = true,
  strength = 1,        // refraction strength multiplier
}) {
  const ref = useRef(null);
  const [hover, setHover] = useState(false);

  useEffect(() => {
    if (!interactive) return;
    const el = ref.current;
    if (!el) return;
    const onMove = (e) => {
      const r = el.getBoundingClientRect();
      const cx = r.left + r.width/2, cy = r.top + r.height/2;
      const dx = (e.clientX - cx) / (r.width/2);
      const dy = (e.clientY - cy) / (r.height/2);
      const dist = Math.min(1, Math.hypot(dx, dy));
      // proximity falloff
      const inside = e.clientX >= r.left - 200 && e.clientX <= r.right + 200 && e.clientY >= r.top - 200 && e.clientY <= r.bottom + 200;
      const prox = inside ? Math.max(0, 1 - dist*0.6) : 0;
      el.style.setProperty('--px', (dx*50).toFixed(2) + '%');
      el.style.setProperty('--py', (dy*50).toFixed(2) + '%');
      el.style.setProperty('--prox', prox.toFixed(3));
      el.style.setProperty('--tiltX', (dy*-3*strength).toFixed(2) + 'deg');
      el.style.setProperty('--tiltY', (dx*3*strength).toFixed(2) + 'deg');
    };
    window.addEventListener('mousemove', onMove);
    return () => window.removeEventListener('mousemove', onMove);
  }, [interactive, strength]);

  const t = tintOpacity ?? (window.__TWEAKS?.tint ?? 0.08);
  const b = blurPx ?? (window.__TWEAKS?.blur ?? 22);

  const glowMap = {
    all: `0 30px 80px -20px ${accent || 'rgba(47,128,237,0.45)'}, 0 0 0 1px rgba(255,255,255,0.18) inset`,
    top: `0 -20px 60px -20px ${accent || 'rgba(47,128,237,0.55)'} inset, 0 30px 60px -30px rgba(0,0,0,0.6)`,
    bottom: `0 20px 60px -20px ${accent || 'rgba(58,224,92,0.55)'} inset, 0 30px 60px -30px rgba(0,0,0,0.6)`,
  };

  return (
    <div
      ref={ref}
      className={`glass-panel ${className}`}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        '--radius': radius + 'px',
        '--tint': `rgba(255,255,255,${t})`,
        '--blur': b + 'px',
        '--glow': accent ? glowMap[accentSide] || glowMap.all : 'none',
        ...style,
      }}
    >
      <div className="glass-refract" />
      <div className="glass-tint" />
      {shine && <div className="glass-shine" />}
      <div className="glass-edge" />
      <div className="glass-content">{children}</div>

      <style>{`
        .glass-panel {
          position: relative;
          border-radius: var(--radius);
          isolation: isolate;
          transform: translate3d(0,0,0) perspective(900px) rotateX(var(--tiltX,0)) rotateY(var(--tiltY,0));
          transition: transform 280ms cubic-bezier(.2,.9,.2,1);
          box-shadow:
            var(--glow, none),
            0 24px 60px -30px rgba(0,0,0,0.8),
            0 2px 0 rgba(255,255,255,0.06) inset;
        }
        .glass-refract, .glass-tint, .glass-shine, .glass-edge {
          position: absolute; inset: 0; border-radius: inherit; pointer-events: none;
        }
        .glass-refract {
          backdrop-filter: blur(var(--blur)) saturate(1.45) contrast(1.05);
          -webkit-backdrop-filter: blur(var(--blur)) saturate(1.45) contrast(1.05);
          z-index: 0;
        }
        .glass-tint {
          background:
            linear-gradient(135deg, rgba(255,255,255,0.22) 0%, rgba(255,255,255,0.02) 45%, rgba(255,255,255,0.16) 100%),
            var(--tint);
          z-index: 1;
        }
        /* moving highlight that tracks cursor proximity */
        .glass-shine {
          background:
            radial-gradient(60% 45% at calc(50% + var(--px, 0%)) calc(30% + var(--py, 0%)),
              rgba(255,255,255,calc(0.28 * var(--prox, 0.25))) 0%,
              rgba(255,255,255,0) 60%),
            linear-gradient(180deg, rgba(255,255,255,0.28) 0%, rgba(255,255,255,0) 22%);
          mix-blend-mode: overlay;
          z-index: 2;
        }
        /* crisp 1px edge + subtle rim light */
        .glass-edge {
          border: 1px solid rgba(255,255,255,0.32);
          box-shadow:
            inset 0 1px 0 rgba(255,255,255,0.55),
            inset 0 -1px 0 rgba(255,255,255,0.12),
            inset 1px 0 0 rgba(255,255,255,0.18),
            inset -1px 0 0 rgba(255,255,255,0.18);
          z-index: 3;
        }
        .glass-content { position: relative; z-index: 4; border-radius: inherit; }
      `}</style>
    </div>
  );
}

// A simple glass "pill" (used for rows inside panels)
function GlassPill({ children, accent, height = 52, radius = 16, style = {} }) {
  return (
    <GlassPanel radius={radius} accent={accent} interactive={false} shine={true}
      style={{ height, display: 'flex', alignItems: 'center', padding: '0 18px', ...style }}>
      {children}
    </GlassPanel>
  );
}

window.GlassPanel = GlassPanel;
window.GlassPill = GlassPill;
