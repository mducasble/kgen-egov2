// Tweaks UI — appears when the host toggles edit mode on.
// Exposes: variation, blur, tint, accent colors, scene hue, "surprise me".

const { useEffect: useEffectT, useState: useStateT } = React;

function TweaksPanel({ tweaks, setTweaks, variation, setVariation }) {
  const [open, setOpen] = useStateT(false);

  useEffectT(() => {
    const onMsg = (e) => {
      const d = e.data || {};
      if (d.type === '__activate_edit_mode') setOpen(true);
      if (d.type === '__deactivate_edit_mode') setOpen(false);
    };
    window.addEventListener('message', onMsg);
    window.parent.postMessage({ type: '__edit_mode_available' }, '*');
    return () => window.removeEventListener('message', onMsg);
  }, []);

  const update = (patch) => {
    const next = { ...tweaks, ...patch };
    setTweaks(next);
    window.__TWEAKS = next;
    window.parent.postMessage({ type: '__edit_mode_set_keys', edits: patch }, '*');
  };

  const surprise = () => {
    const hues = [15, 25, 200, 215, 280, 320, 45];
    const greens = ['#3AE05C','#6EFFA5','#29D9A2','#A8FF3E'];
    const blues  = ['#2F80ED','#56A0FF','#7A5CFF','#00D0FF'];
    const patch = {
      blur: 14 + Math.floor(Math.random()*20),
      tint: +(0.04 + Math.random()*0.14).toFixed(2),
      accentGreen: greens[Math.floor(Math.random()*greens.length)],
      accentBlue:  blues [Math.floor(Math.random()*blues.length)],
      sceneHue:    hues  [Math.floor(Math.random()*hues.length)],
    };
    update(patch);
  };

  if (!open) return null;

  const row = (label, children) => (
    <div style={{ display:'flex', flexDirection:'column', gap: 6 }}>
      <div style={{ fontFamily:'JetBrains Mono', fontSize: 10, letterSpacing:'0.16em', textTransform:'uppercase', color:'rgba(255,255,255,0.55)' }}>{label}</div>
      {children}
    </div>
  );

  const chip = (active, onClick, children, extra={}) => (
    <button onClick={onClick} style={{
      padding: '8px 12px', borderRadius: 10,
      background: active ? 'rgba(255,255,255,0.16)' : 'rgba(255,255,255,0.04)',
      color: active ? 'white' : 'rgba(255,255,255,0.75)',
      border: `1px solid ${active? 'rgba(255,255,255,0.4)':'rgba(255,255,255,0.1)'}`,
      fontFamily:'Space Grotesk', fontSize: 12, fontWeight: 500,
      cursor:'pointer', ...extra,
    }}>{children}</button>
  );

  return (
    <div style={{
      position:'fixed', right: 20, bottom: 20, zIndex: 100,
      width: 280, padding: 18,
      background: 'rgba(12,16,24,0.78)',
      backdropFilter: 'blur(20px) saturate(1.4)',
      WebkitBackdropFilter: 'blur(20px) saturate(1.4)',
      border: '1px solid rgba(255,255,255,0.14)',
      borderRadius: 18,
      color:'white',
      fontFamily:'Space Grotesk, sans-serif',
      boxShadow: '0 24px 60px -20px rgba(0,0,0,0.7)',
      display:'flex', flexDirection:'column', gap: 14,
    }}>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between' }}>
        <div style={{ fontFamily:'JetBrains Mono', fontSize: 11, letterSpacing:'0.22em', color:'rgba(255,255,255,0.7)' }}>TWEAKS</div>
        <button onClick={surprise} style={{
          fontFamily:'JetBrains Mono', fontSize: 10, letterSpacing:'0.16em', textTransform:'uppercase',
          padding:'6px 10px', borderRadius: 8,
          background: 'linear-gradient(135deg, #3AE05C, #2F80ED)',
          color:'white', border:'none', cursor:'pointer', fontWeight:600,
        }}>Surprise me</button>
      </div>

      {row('Variation', (
        <div style={{ display:'flex', gap: 6 }}>
          {[1,2,3].map(v => chip(variation === v, () => setVariation(v), `V${v}`, { flex: 1 }))}
        </div>
      ))}

      {row(`Blur — ${tweaks.blur}px`, (
        <input type="range" min="0" max="40" value={tweaks.blur}
          onChange={e => update({ blur: +e.target.value })}
          style={{ accentColor: tweaks.accentGreen, width: '100%' }}/>
      ))}

      {row(`Glass tint — ${tweaks.tint.toFixed(2)}`, (
        <input type="range" min="0" max="0.25" step="0.01" value={tweaks.tint}
          onChange={e => update({ tint: +e.target.value })}
          style={{ accentColor: tweaks.accentGreen, width: '100%' }}/>
      ))}

      {row('Accents', (
        <div style={{ display:'flex', gap: 10, alignItems:'center' }}>
          <label style={{ display:'flex', flexDirection:'column', alignItems:'center', gap: 4, flex:1 }}>
            <input type="color" value={tweaks.accentGreen} onChange={e => update({ accentGreen: e.target.value })}
              style={{ width: '100%', height: 32, border:'none', background:'transparent', cursor:'pointer' }}/>
            <span style={{ fontFamily:'JetBrains Mono', fontSize: 9, color:'rgba(255,255,255,0.5)' }}>GREEN</span>
          </label>
          <label style={{ display:'flex', flexDirection:'column', alignItems:'center', gap: 4, flex:1 }}>
            <input type="color" value={tweaks.accentBlue} onChange={e => update({ accentBlue: e.target.value })}
              style={{ width: '100%', height: 32, border:'none', background:'transparent', cursor:'pointer' }}/>
            <span style={{ fontFamily:'JetBrains Mono', fontSize: 9, color:'rgba(255,255,255,0.5)' }}>BLUE</span>
          </label>
        </div>
      ))}

      {row(`Scene hue — ${tweaks.sceneHue}°`, (
        <input type="range" min="0" max="360" value={tweaks.sceneHue}
          onChange={e => update({ sceneHue: +e.target.value })}
          style={{ accentColor: tweaks.accentBlue, width: '100%' }}/>
      ))}
    </div>
  );
}

window.TweaksPanel = TweaksPanel;
