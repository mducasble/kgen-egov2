// App shell — wires tweaks, variation, and the 9:16 stage (fixed 1000x1778, scaled to fit viewport).

const { useEffect: useEffectA, useState: useStateA, useLayoutEffect, useRef: useRefA } = React;

const STAGE_W = 1000;
const STAGE_H = 1778; // 9:16

function App() {
  const [tweaks, setTweaks] = useStateA({ ...window.__TWEAKS });
  const [variation, setVariation] = useStateA(tweaks.variation || 1);

  // persist variation in localStorage too (survives edit-mode reload)
  useEffectA(() => {
    const v = +localStorage.getItem('kgen_variation');
    if (v && [1,2,3].includes(v)) setVariation(v);
  }, []);
  useEffectA(() => {
    localStorage.setItem('kgen_variation', String(variation));
    window.parent.postMessage({ type: '__edit_mode_set_keys', edits: { variation } }, '*');
    window.__TWEAKS = { ...window.__TWEAKS, variation };
  }, [variation]);

  // scale stage to viewport
  const stageRef = useRefA(null);
  useLayoutEffect(() => {
    const fit = () => {
      const el = stageRef.current;
      if (!el) return;
      const s = Math.min(window.innerWidth / STAGE_W, window.innerHeight / STAGE_H);
      el.style.transform = `translate(-50%,-50%) scale(${s})`;
    };
    fit();
    window.addEventListener('resize', fit);
    return () => window.removeEventListener('resize', fit);
  }, []);

  const accents = { green: tweaks.accentGreen, blue: tweaks.accentBlue };

  const V = window.Variations[`V${variation}`] || window.Variations.V1;

  return (
    <>
      {/* subtle variation indicator / switcher (always visible, minimal) */}
      <div style={{
        position:'fixed', top: 20, left: '50%', transform:'translateX(-50%)', zIndex: 50,
        display:'flex', gap: 8, padding: 6,
        background: 'rgba(12,16,24,0.6)', backdropFilter:'blur(14px)', WebkitBackdropFilter:'blur(14px)',
        border:'1px solid rgba(255,255,255,0.12)', borderRadius: 999,
      }}>
        {[1,2,3].map(v=>(
          <button key={v} onClick={()=>setVariation(v)} style={{
            width: 32, height: 32, borderRadius: 999, border:'none', cursor:'pointer',
            fontFamily:'JetBrains Mono', fontSize: 11, fontWeight:600, letterSpacing:'0.1em',
            background: variation===v ? 'linear-gradient(135deg,#3AE05C,#2F80ED)' : 'transparent',
            color: variation===v ? 'white' : 'rgba(255,255,255,0.65)',
          }}>{`V${v}`}</button>
        ))}
      </div>

      {/* stage */}
      <div ref={stageRef} style={{
        position:'absolute', left: '50%', top: '50%',
        width: STAGE_W, height: STAGE_H, transformOrigin: '50% 50%',
        overflow:'hidden', borderRadius: 0,
      }} data-screen-label={`0${variation} Variation`}>
        <PovScene hue={tweaks.sceneHue} variant={variation}/>
        <div style={{ position:'absolute', inset: 0 }}>
          <V accents={accents}/>
        </div>
      </div>

      <TweaksPanel
        tweaks={tweaks}
        setTweaks={(t)=>{ setTweaks(t); window.__TWEAKS = t; }}
        variation={variation}
        setVariation={setVariation}
      />

      <style>{`
        @keyframes float {
          0%   { transform: translate(0, 0) rotate(0deg); }
          100% { transform: translate(8px, -14px) rotate(3deg); }
        }
        .stage-inner { width: 100%; height: 100%; position:absolute; inset:0; }
      `}</style>
    </>
  );
}

ReactDOM.createRoot(document.getElementById('app')).render(<App/>);
