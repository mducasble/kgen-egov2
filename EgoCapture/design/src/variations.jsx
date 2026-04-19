// Three variations of the KGeN Eye key visual.
// Each fills a 9:16 canvas (stage sized by app.jsx). They share the same design language
// but explore different compositions.

const { useEffect: useEffectV, useState: useStateV } = React;

// ---------- shared atoms ----------

function FloatShape({ kind, size = 60, x, y, color, delay = 0, accent }) {
  // small floating glass shape with colored fill (like pentagon / diamond / pill)
  const shapes = {
    pentagon: (
      <svg viewBox="0 0 100 100" width={size} height={size}>
        <polygon points="50,8 92,38 76,88 24,88 8,38" fill={color} stroke="rgba(255,255,255,0.6)" strokeWidth="2"/>
      </svg>
    ),
    diamond: (
      <svg viewBox="0 0 100 100" width={size} height={size}>
        <polygon points="50,10 90,50 50,90 10,50" fill={color} stroke="rgba(255,255,255,0.6)" strokeWidth="2"/>
      </svg>
    ),
    circle: (
      <svg viewBox="0 0 100 100" width={size} height={size}>
        <circle cx="50" cy="50" r="42" fill={color} stroke="rgba(255,255,255,0.6)" strokeWidth="2"/>
      </svg>
    ),
    triangle: (
      <svg viewBox="0 0 100 100" width={size} height={size}>
        <polygon points="50,12 90,86 10,86" fill={color} stroke="rgba(255,255,255,0.6)" strokeWidth="2"/>
      </svg>
    ),
  };
  return (
    <div style={{
      position: 'absolute', left: x, top: y,
      filter: `drop-shadow(0 0 18px ${accent || color}88) drop-shadow(0 8px 20px rgba(0,0,0,0.5))`,
      animation: `float 6s ease-in-out ${delay}s infinite alternate`,
    }}>
      {shapes[kind]}
    </div>
  );
}

function CaptionMono({ children, style = {} }) {
  return <div style={{
    fontFamily: 'JetBrains Mono, monospace',
    fontSize: 11,
    letterSpacing: '0.18em',
    textTransform: 'uppercase',
    color: 'rgba(255,255,255,0.75)',
    ...style,
  }}>{children}</div>;
}

// ---------- VARIATION 1: single tall panel, homage to reference ----------

function V1({ accents }) {
  return (
    <div className="stage-inner v1">
      <GlassPanel radius={36} accent={accents.blue + '55'} strength={1.2}
        style={{ width: 520, height: 1000, margin: '0 auto', marginTop: 40 }}>
        <div style={{ padding: '44px 36px', display:'flex', flexDirection:'column', gap: 26, height: '100%', boxSizing:'border-box' }}>
          {/* header: logo */}
          <div style={{ display:'flex', flexDirection:'column', alignItems:'center', gap: 10, marginTop: 4 }}>
            <EyeMark size={84} glow={accents.green}/>
            <Wordmark size={18} spread={0.34}/>
            <CaptionMono style={{marginTop:2, color:'rgba(255,255,255,0.55)'}}>v.04 · lens online</CaptionMono>
          </div>

          {/* top shape row */}
          <div style={{ display:'flex', alignItems:'center', gap: 18, marginTop: 6 }}>
            <GlassPanel radius={999} strength={0.6} style={{ width: 78, height: 78, display:'grid', placeItems:'center' }}>
              <svg viewBox="0 0 100 100" width="40" height="40">
                <polygon points="50,10 92,40 76,90 24,90 8,40" fill={accents.green} stroke="rgba(255,255,255,0.7)" strokeWidth="3"/>
              </svg>
            </GlassPanel>
            <div style={{ position:'relative', flex:1, height: 88 }}>
              <GlassPanel radius={22} strength={0.6} style={{ position:'absolute', left: 0, top: 8, width: 220, height: 68 }}/>
              <GlassPanel radius={22} strength={0.6} style={{ position:'absolute', left: 150, top: 0, width: 160, height: 80 }}/>
            </div>
          </div>

          {/* feature rows */}
          <GlassPill accent={accents.blue} style={{ marginTop: 6 }}>
            <div style={{ flex:1, display:'flex', flexDirection:'column' }}>
              <span style={{ fontWeight: 600, fontSize: 15, color:'#E8F1FF' }}>Capture</span>
              <span style={{ fontFamily:'JetBrains Mono', fontSize: 10, color:'rgba(255,255,255,0.7)', letterSpacing:'0.14em' }}>POV · 4K · 120fps</span>
            </div>
            <div style={{ width: 10, height: 10, borderRadius: 99, background: accents.blue, boxShadow: `0 0 12px ${accents.blue}` }}/>
          </GlassPill>

          <GlassPill accent={accents.green}>
            <div style={{ flex:1, display:'flex', flexDirection:'column' }}>
              <span style={{ fontWeight: 600, fontSize: 15, color:'#E8FFE8' }}>Relive</span>
              <span style={{ fontFamily:'JetBrains Mono', fontSize: 10, color:'rgba(255,255,255,0.7)', letterSpacing:'0.14em' }}>spatial · stereo · tactile</span>
            </div>
            <div style={{ width: 10, height: 10, borderRadius: 99, background: accents.green, boxShadow: `0 0 12px ${accents.green}` }}/>
          </GlassPill>

          <GlassPill>
            <span style={{ fontWeight: 500, fontSize: 14, color:'rgba(255,255,255,0.88)' }}>Share with a glance</span>
          </GlassPill>

          <GlassPill>
            <span style={{ fontFamily:'JetBrains Mono', fontSize: 11, letterSpacing:'0.18em', color:'rgba(255,255,255,0.72)', textTransform:'uppercase' }}>
              Experience your environment
            </span>
          </GlassPill>

          <div style={{ flex:1 }}/>

          {/* bottom diamond */}
          <div style={{ display:'flex', justifyContent:'center', marginBottom: 4 }}>
            <svg viewBox="0 0 100 100" width="54" height="54" style={{filter:`drop-shadow(0 0 16px ${accents.green}aa)`}}>
              <polygon points="50,10 90,50 50,90 10,50" fill={accents.green} stroke="rgba(255,255,255,0.7)" strokeWidth="3"/>
            </svg>
          </div>
        </div>
      </GlassPanel>
    </div>
  );
}

// ---------- VARIATION 2: floating panel cluster ----------

function V2({ accents }) {
  return (
    <div className="stage-inner v2" style={{ position:'relative', width: 1000, height: 1778 }}>
      {/* ambient floating shapes */}
      <FloatShape kind="pentagon" size={54} x={80} y={140} color={accents.green} accent={accents.green} delay={0}/>
      <FloatShape kind="circle" size={34} x={880} y={260} color={accents.blue} accent={accents.blue} delay={1.2}/>
      <FloatShape kind="diamond" size={70} x={820} y={1520} color={accents.green} accent={accents.green} delay={2.1}/>
      <FloatShape kind="triangle" size={38} x={110} y={1620} color={accents.blue} accent={accents.blue} delay={0.8}/>

      {/* HERO panel — logo + tagline */}
      <GlassPanel radius={40} accent={accents.blue + '66'}
        style={{ position:'absolute', left: 140, top: 220, width: 720, height: 420 }}>
        <div style={{ padding: '56px 48px', display:'flex', flexDirection:'column', gap: 22, height:'100%', boxSizing:'border-box' }}>
          <CaptionMono>POV · 2026 · release 04</CaptionMono>
          <div style={{ display:'flex', alignItems:'center', gap: 22 }}>
            <EyeMark size={112} glow={accents.green}/>
            <div style={{ display:'flex', flexDirection:'column', gap: 6 }}>
              <div style={{
                fontFamily:'Space Grotesk', fontWeight: 700, fontSize: 68,
                lineHeight: 0.95, letterSpacing: '-0.02em', color:'white',
              }}>
                KGeN<span style={{color: accents.green}}>.</span>
              </div>
              <div style={{
                fontFamily:'Space Grotesk', fontWeight: 500, fontSize: 28,
                letterSpacing: '0.3em', color:'rgba(255,255,255,0.8)', textTransform:'uppercase',
              }}>
                Eye
              </div>
            </div>
          </div>
          <div style={{
            fontFamily:'Space Grotesk', fontWeight: 400, fontSize: 26,
            color:'rgba(255,255,255,0.92)', lineHeight: 1.3, textWrap:'pretty', marginTop: 6,
          }}>
            Experience your<br/>environment.
          </div>
        </div>
      </GlassPanel>

      {/* stats pill */}
      <GlassPanel radius={28} accent={accents.green + '55'}
        style={{ position:'absolute', left: 560, top: 680, width: 360, height: 120 }}>
        <div style={{ padding: 20, display:'flex', alignItems:'center', gap: 18, height:'100%', boxSizing:'border-box' }}>
          <div style={{ width: 60, height: 60, borderRadius: 16, background: `radial-gradient(circle at 40% 35%, ${accents.green}, #0a3a14)`, border: '1px solid rgba(255,255,255,0.4)' }}/>
          <div style={{ display:'flex', flexDirection:'column' }}>
            <span style={{ fontFamily:'JetBrains Mono', fontSize: 12, letterSpacing:'0.14em', color:'rgba(255,255,255,0.65)', textTransform:'uppercase' }}>Recording</span>
            <span style={{ fontFamily:'Space Grotesk', fontWeight: 600, fontSize: 26, color:'white' }}>00:04:12</span>
          </div>
          <div style={{ marginLeft:'auto', width: 14, height: 14, borderRadius: 99, background: accents.green, boxShadow: `0 0 16px ${accents.green}` }}/>
        </div>
      </GlassPanel>

      {/* feed card — mock video thumbnails */}
      <GlassPanel radius={36}
        style={{ position:'absolute', left: 120, top: 820, width: 760, height: 520 }}>
        <div style={{ padding: 28, display:'flex', flexDirection:'column', gap: 18, height:'100%', boxSizing:'border-box' }}>
          <div style={{ display:'flex', justifyContent:'space-between', alignItems:'center' }}>
            <CaptionMono>your feed</CaptionMono>
            <CaptionMono style={{color:'rgba(255,255,255,0.45)'}}>·  ·  ·</CaptionMono>
          </div>
          <div style={{ display:'grid', gridTemplateColumns:'1fr 1fr', gap: 16, flex:1 }}>
            {[
              {t:'Morning run', tag:'OUTDOOR · 04:21', h1: 35, h2: 60, accent: accents.green},
              {t:'Studio jam',  tag:'INDOOR  · 12:08', h1: 215, h2: 30, accent: accents.blue},
              {t:'Sunset trail',tag:'OUTDOOR · 06:55', h1: 22, h2: 75, accent: accents.green},
              {t:'Coffee walk', tag:'URBAN   · 09:42', h1: 200, h2: 45, accent: accents.blue},
            ].map((c,i)=>(
              <div key={i} style={{
                position:'relative', borderRadius: 20, overflow:'hidden',
                background: `linear-gradient(135deg, hsl(${c.h1} 55% 22%), hsl(${c.h2} 65% 35%))`,
                border: '1px solid rgba(255,255,255,0.2)',
                boxShadow: `inset 0 1px 0 rgba(255,255,255,0.3), 0 10px 30px -10px rgba(0,0,0,0.6)`,
              }}>
                {/* diagonal sheen */}
                <div style={{position:'absolute', inset:0, background:'linear-gradient(135deg, rgba(255,255,255,0.22) 0%, transparent 40%)'}}/>
                {/* bokeh */}
                <div style={{position:'absolute', right:-20, top:-20, width:120, height:120, borderRadius:99, background:`radial-gradient(${c.accent}66, transparent 70%)`, filter:'blur(10px)'}}/>
                <div style={{position:'absolute', left:14, bottom:14, right:14, display:'flex', flexDirection:'column', gap:4}}>
                  <span style={{fontFamily:'JetBrains Mono', fontSize: 10, letterSpacing:'0.14em', color:'rgba(255,255,255,0.8)'}}>{c.tag}</span>
                  <span style={{fontFamily:'Space Grotesk', fontWeight: 600, fontSize: 18, color:'white'}}>{c.t}</span>
                </div>
                <div style={{position:'absolute', right:14, top:14, width:10, height:10, borderRadius:99, background:c.accent, boxShadow:`0 0 10px ${c.accent}`}}/>
              </div>
            ))}
          </div>
        </div>
      </GlassPanel>

      {/* CTA — record */}
      <GlassPanel radius={999} accent={accents.green + '99'} strength={1.4}
        style={{ position:'absolute', left: '50%', bottom: 130, transform: 'translateX(-50%)', width: 180, height: 180 }}>
        <div style={{
          position:'absolute', inset: 24, borderRadius: 999,
          background: `radial-gradient(circle at 40% 30%, #9dffb1, ${accents.green} 50%, #0f5720 100%)`,
          boxShadow: `inset 0 2px 8px rgba(255,255,255,0.8), 0 10px 40px ${accents.green}99`,
          display:'grid', placeItems:'center',
        }}>
          <div style={{ width: 60, height: 60, borderRadius: 14, background:'rgba(255,255,255,0.9)', boxShadow:'0 2px 10px rgba(0,0,0,0.3)' }}/>
        </div>
      </GlassPanel>

      {/* bottom caption */}
      <div style={{ position:'absolute', left: 0, right: 0, bottom: 56, textAlign:'center' }}>
        <CaptionMono style={{color:'rgba(255,255,255,0.6)'}}>tap to capture · hold to live</CaptionMono>
      </div>
    </div>
  );
}

// ---------- VARIATION 3: radial HUD / lens-inspired ----------

function V3({ accents }) {
  return (
    <div className="stage-inner v3" style={{ position:'relative', width: 1000, height: 1778 }}>
      {/* outer concentric rings */}
      <svg viewBox="0 0 1000 1778" width="1000" height="1778" style={{ position:'absolute', inset:0, pointerEvents:'none' }}>
        <defs>
          <radialGradient id="ring-fade" cx="50%" cy="42%" r="55%">
            <stop offset="0" stopColor="rgba(255,255,255,0.5)"/>
            <stop offset="1" stopColor="rgba(255,255,255,0)"/>
          </radialGradient>
        </defs>
        {[320, 420, 520, 640].map((r,i)=>(
          <circle key={i} cx="500" cy="750" r={r} fill="none" stroke="url(#ring-fade)" strokeWidth={i===1?1.5:0.8} strokeDasharray={i===2?'3 6':'none'} opacity={0.7 - i*0.1}/>
        ))}
        {/* crosshair ticks */}
        {[0,45,90,135,180,225,270,315].map(a=>{
          const rad = a*Math.PI/180;
          const x1 = 500 + Math.cos(rad)*640, y1 = 750 + Math.sin(rad)*640;
          const x2 = 500 + Math.cos(rad)*660, y2 = 750 + Math.sin(rad)*660;
          return <line key={a} x1={x1} y1={y1} x2={x2} y2={y2} stroke="rgba(255,255,255,0.4)" strokeWidth="1.2"/>;
        })}
      </svg>

      {/* top header */}
      <div style={{ position:'absolute', left: 0, right: 0, top: 80, display:'flex', justifyContent:'center' }}>
        <GlassPanel radius={999} style={{ padding: '12px 28px' }}>
          <div style={{ display:'flex', alignItems:'center', gap: 14, padding:'4px 6px' }}>
            <div style={{ width: 8, height: 8, borderRadius: 99, background: accents.green, boxShadow:`0 0 10px ${accents.green}` }}/>
            <span style={{ fontFamily:'JetBrains Mono', fontSize: 12, letterSpacing:'0.22em', color:'rgba(255,255,255,0.85)', textTransform:'uppercase' }}>KGeN · EYE</span>
            <span style={{ fontFamily:'JetBrains Mono', fontSize: 11, letterSpacing:'0.18em', color:'rgba(255,255,255,0.5)' }}>v.04.0</span>
          </div>
        </GlassPanel>
      </div>

      {/* CENTER — big lens */}
      <div style={{ position:'absolute', left: '50%', top: 750, transform: 'translate(-50%, -50%)' }}>
        <GlassPanel radius={999} accent={accents.green + 'aa'} strength={1.6}
          style={{ width: 520, height: 520 }}>
          <div style={{
            position:'absolute', inset: 40, borderRadius: 999,
            background: `
              radial-gradient(circle at 38% 32%, rgba(255,255,255,0.9) 0%, transparent 18%),
              radial-gradient(circle at 50% 50%, ${accents.green}ee 0%, #0a2a14 65%, #030806 100%)
            `,
            boxShadow: `inset 0 4px 20px rgba(255,255,255,0.5), inset 0 -10px 40px rgba(0,0,0,0.6), 0 0 80px ${accents.green}66`,
            display:'grid', placeItems:'center',
          }}>
            {/* aperture blades */}
            <svg viewBox="0 0 200 200" width="100%" height="100%" style={{position:'absolute', inset:0}}>
              {[0,60,120,180,240,300].map(a=>{
                const rad = a*Math.PI/180;
                return (
                  <line key={a}
                    x1={100 + Math.cos(rad)*40} y1={100 + Math.sin(rad)*40}
                    x2={100 + Math.cos(rad)*90} y2={100 + Math.sin(rad)*90}
                    stroke="rgba(255,255,255,0.28)" strokeWidth="1.5"/>
                );
              })}
              <circle cx="100" cy="100" r="32" fill="#050a07" stroke="rgba(255,255,255,0.25)" strokeWidth="1"/>
              <circle cx="92" cy="92" r="8" fill="rgba(255,255,255,0.9)"/>
            </svg>
          </div>
        </GlassPanel>
      </div>

      {/* orbiting label pills */}
      {[
        {label:'CAPTURE', mono:'01 · POV', x: 80, y: 620, accent: accents.blue},
        {label:'RELIVE',  mono:'02 · SPATIAL', x: 720, y: 620, accent: accents.green},
        {label:'SHARE',   mono:'03 · GLANCE', x: 80, y: 940, accent: accents.green},
        {label:'MEMORY',  mono:'04 · INFINITE', x: 720, y: 940, accent: accents.blue},
      ].map((p,i)=>(
        <GlassPanel key={i} radius={18} accent={p.accent + '55'}
          style={{ position:'absolute', left: p.x, top: p.y, width: 200, height: 72 }}>
          <div style={{ padding:'12px 16px', display:'flex', flexDirection:'column', gap: 2, height:'100%', boxSizing:'border-box' }}>
            <span style={{ fontFamily:'JetBrains Mono', fontSize: 10, letterSpacing:'0.18em', color:'rgba(255,255,255,0.55)' }}>{p.mono}</span>
            <span style={{ fontFamily:'Space Grotesk', fontWeight: 600, fontSize: 20, letterSpacing:'0.14em', color:'white' }}>{p.label}</span>
          </div>
        </GlassPanel>
      ))}

      {/* bottom tagline block */}
      <div style={{ position:'absolute', left: 80, right: 80, bottom: 180 }}>
        <GlassPanel radius={32} accent={accents.blue + '55'}
          style={{ width: '100%', padding: 0 }}>
          <div style={{ padding: '38px 40px', display:'flex', flexDirection:'column', gap: 10 }}>
            <CaptionMono>tagline</CaptionMono>
            <div style={{
              fontFamily:'Space Grotesk', fontWeight: 500, fontSize: 44,
              color:'white', lineHeight: 1.05, letterSpacing: '-0.01em',
            }}>
              Experience<br/>your <span style={{color: accents.green}}>environment</span>.
            </div>
          </div>
        </GlassPanel>
      </div>

      {/* corner ticks */}
      {[
        {s:'TL', x: 24, y: 24},
        {s:'TR', x: 924, y: 24},
        {s:'BL', x: 24, y: 1716},
        {s:'BR', x: 924, y: 1716},
      ].map(c=>(
        <div key={c.s} style={{
          position:'absolute', left: c.x, top: c.y, width: 40, height: 40,
          borderTop: c.s[0]==='T'?'1px solid rgba(255,255,255,0.4)':'none',
          borderBottom: c.s[0]==='B'?'1px solid rgba(255,255,255,0.4)':'none',
          borderLeft: c.s[1]==='L'?'1px solid rgba(255,255,255,0.4)':'none',
          borderRight: c.s[1]==='R'?'1px solid rgba(255,255,255,0.4)':'none',
        }}/>
      ))}
    </div>
  );
}

window.Variations = { V1, V2, V3 };
