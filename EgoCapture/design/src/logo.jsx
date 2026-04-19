// Original KGeN Eye monogram — a lens/aperture glyph inside a rounded square.
// No brand recreation. This is original geometry: concentric rings + pupil,
// plus a minimal "EYE" wordmark set in Space Grotesk.

function EyeMark({ size = 72, glow = '#3AE05C' }) {
  return (
    <div style={{ width: size, height: size, position: 'relative' }}>
      <svg viewBox="0 0 100 100" width={size} height={size} style={{ display: 'block' }}>
        <defs>
          <radialGradient id="lens-grad" cx="50%" cy="45%" r="55%">
            <stop offset="0%" stopColor="#CFFFD9" stopOpacity="1"/>
            <stop offset="55%" stopColor={glow} stopOpacity="0.95"/>
            <stop offset="100%" stopColor="#0c3a14" stopOpacity="1"/>
          </radialGradient>
          <linearGradient id="bezel" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0" stopColor="rgba(255,255,255,0.95)"/>
            <stop offset="1" stopColor="rgba(255,255,255,0.35)"/>
          </linearGradient>
        </defs>
        {/* rounded-square bezel */}
        <rect x="4" y="4" width="92" height="92" rx="22" ry="22"
          fill="rgba(255,255,255,0.06)" stroke="url(#bezel)" strokeWidth="1.5"/>
        {/* outer ring */}
        <circle cx="50" cy="50" r="34" fill="none" stroke="rgba(255,255,255,0.55)" strokeWidth="1.2"/>
        {/* lens */}
        <circle cx="50" cy="50" r="26" fill="url(#lens-grad)"/>
        {/* aperture blades — 6 thin wedges */}
        <g stroke="rgba(255,255,255,0.35)" strokeWidth="0.8" fill="none">
          {[0,60,120,180,240,300].map(a=>(
            <line key={a}
              x1={50 + Math.cos(a*Math.PI/180)*10}
              y1={50 + Math.sin(a*Math.PI/180)*10}
              x2={50 + Math.cos(a*Math.PI/180)*25}
              y2={50 + Math.sin(a*Math.PI/180)*25}/>
          ))}
        </g>
        {/* pupil */}
        <circle cx="50" cy="50" r="7" fill="#0a1a0e"/>
        {/* catchlight */}
        <circle cx="44" cy="44" r="3" fill="rgba(255,255,255,0.9)"/>
        <circle cx="58" cy="56" r="1.6" fill="rgba(255,255,255,0.6)"/>
      </svg>
      {/* soft bloom behind */}
      <div style={{
        position:'absolute', inset:-10, borderRadius: 28, zIndex:-1,
        background: `radial-gradient(closest-side, ${glow}55, transparent 70%)`, filter:'blur(10px)'
      }}/>
    </div>
  );
}

function Wordmark({ size = 22, color = 'white', weight = 600, spread = 0.32 }) {
  return (
    <div style={{
      fontFamily: 'Space Grotesk, sans-serif',
      fontWeight: weight,
      fontSize: size,
      letterSpacing: `${spread}em`,
      color,
      textTransform: 'uppercase',
      textShadow: '0 1px 0 rgba(0,0,0,0.25)',
    }}>
      KGeN <span style={{opacity: 0.7}}>·</span> EYE
    </div>
  );
}

window.EyeMark = EyeMark;
window.Wordmark = Wordmark;
