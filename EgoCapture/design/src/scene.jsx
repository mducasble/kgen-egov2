// POV / egocentric background scene — pure CSS + SVG, no external assets.
// Paints a blurred first-person view: a warm room with light spill, window bloom, hands holding a device silhouette.
// Designed to live behind glass; the richness lets the backdrop-filter earn its keep.

function PovScene({ hue = 25, variant = 1 }) {
  // Three subtly different POV scenes for the three variations.
  const scenes = {
    1: (
      <>
        {/* Warm interior — window light from left, bokeh */}
        <div className="scene-layer" style={{
          background: `
            radial-gradient(1200px 900px at 18% 30%, hsl(${hue} 85% 72% / 0.9), transparent 55%),
            radial-gradient(900px 900px at 82% 70%, hsl(${hue + 15} 70% 40% / 0.7), transparent 60%),
            radial-gradient(600px 500px at 50% 100%, hsl(${hue - 5} 50% 20% / 0.9), transparent 70%),
            linear-gradient(180deg, hsl(${hue} 40% 18%) 0%, hsl(${hue + 20} 30% 8%) 100%)
          `
        }}/>
        {/* bokeh dots */}
        <svg className="scene-layer" viewBox="0 0 1000 1778" preserveAspectRatio="xMidYMid slice" style={{opacity:0.7, filter:'blur(18px)'}}>
          {Array.from({length: 22}).map((_,i)=>{
            const x = (i*137)%1000, y=(i*211)%1778, r=18+((i*17)%50);
            const h = hue + (i%3)*18;
            return <circle key={i} cx={x} cy={y} r={r} fill={`hsl(${h} 90% 70%)`} opacity={0.45}/>
          })}
        </svg>
        {/* window stripe suggestion */}
        <div className="scene-layer" style={{
          background: `linear-gradient(92deg, hsl(${hue+10} 95% 88% / 0.55) 0%, transparent 35%)`,
          mixBlendMode: 'screen', filter: 'blur(40px)'
        }}/>
        {/* hand silhouette hint at bottom (POV hands gripping a device) */}
        <svg className="scene-layer" viewBox="0 0 1000 1778" preserveAspectRatio="xMidYMax slice" style={{opacity:0.55, filter:'blur(22px)'}}>
          <path d="M -50 1900 Q 150 1500 300 1520 L 320 1600 Q 500 1560 520 1620 Q 700 1560 720 1640 Q 900 1580 1100 1660 L 1100 1900 Z"
            fill={`hsl(${hue-5} 30% 12%)`}/>
        </svg>
      </>
    ),
    2: (
      <>
        {/* Urban dusk — POV walking a city street, blue hour with street lamps */}
        <div className="scene-layer" style={{
          background: `
            radial-gradient(900px 700px at 30% 20%, hsl(215 90% 65% / 0.6), transparent 60%),
            radial-gradient(800px 700px at 75% 40%, hsl(25 95% 60% / 0.7), transparent 55%),
            radial-gradient(700px 600px at 50% 90%, hsl(220 60% 15% / 0.95), transparent 70%),
            linear-gradient(180deg, hsl(220 55% 14%) 0%, hsl(230 45% 6%) 100%)
          `
        }}/>
        {/* vertical light streaks (street lamps / signage) */}
        <svg className="scene-layer" viewBox="0 0 1000 1778" preserveAspectRatio="xMidYMid slice" style={{opacity:0.8, filter:'blur(12px)'}}>
          {[120,260,430,610,790,920].map((x,i)=>(
            <rect key={i} x={x} y={-40} width={3+(i%3)*2} height={1800} fill={i%2? 'hsl(30 95% 68%)':'hsl(215 95% 72%)'} opacity={0.5}/>
          ))}
          {Array.from({length: 30}).map((_,i)=>{
            const x = (i*97+i*i*3)%1000, y=(i*263)%1778, r=10+((i*13)%40);
            return <circle key={i} cx={x} cy={y} r={r} fill={i%3? 'hsl(30 95% 68%)':'hsl(210 90% 70%)'} opacity={0.35}/>
          })}
        </svg>
        <div className="scene-layer" style={{
          background: `linear-gradient(180deg, transparent 55%, hsl(220 40% 5% / 0.85) 100%)`
        }}/>
      </>
    ),
    3: (
      <>
        {/* Outdoor golden hour — POV riding bike / trail, sun flare */}
        <div className="scene-layer" style={{
          background: `
            radial-gradient(1000px 700px at 70% 25%, hsl(40 100% 72% / 0.95), transparent 55%),
            radial-gradient(900px 800px at 25% 60%, hsl(18 80% 35% / 0.8), transparent 60%),
            radial-gradient(800px 600px at 50% 100%, hsl(145 40% 18% / 0.9), transparent 70%),
            linear-gradient(180deg, hsl(35 70% 60%) 0%, hsl(20 60% 14%) 60%, hsl(140 30% 8%) 100%)
          `
        }}/>
        {/* sun flare */}
        <div className="scene-layer" style={{
          background: `radial-gradient(200px 200px at 72% 23%, white 0%, hsl(45 100% 75% / 0.8) 20%, transparent 60%)`,
          mixBlendMode: 'screen', filter:'blur(8px)'
        }}/>
        {/* horizon leaves / foliage silhouettes */}
        <svg className="scene-layer" viewBox="0 0 1000 1778" preserveAspectRatio="xMidYMid slice" style={{opacity:0.65, filter:'blur(20px)'}}>
          {Array.from({length: 40}).map((_,i)=>{
            const x = (i*89)%1000, y=600+(i*41)%1000, r=30+((i*23)%80);
            return <circle key={i} cx={x} cy={y} r={r} fill={`hsl(${120+(i%5)*15} 40% ${10+(i%4)*5}%)`} opacity={0.7}/>
          })}
        </svg>
      </>
    ),
  };

  return (
    <div className="scene-root" aria-hidden="true">
      {scenes[variant] || scenes[1]}
      {/* vignette */}
      <div className="scene-layer" style={{
        background: 'radial-gradient(120% 80% at 50% 50%, transparent 55%, rgba(0,0,0,0.75) 100%)'
      }}/>
      <style>{`
        .scene-root { position: absolute; inset: 0; overflow: hidden; }
        .scene-layer { position: absolute; inset: -2%; }
      `}</style>
    </div>
  );
}

window.PovScene = PovScene;
