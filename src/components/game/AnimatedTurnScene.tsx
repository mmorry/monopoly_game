import { useEffect, useRef, useState, type CSSProperties } from 'react';
import type { GamePlayer, GameRoll, GameSpace } from '../../scripts/gameApi';

interface Props {
  spaces: GameSpace[];
  players: GamePlayer[];
  player?: GamePlayer;
  roll?: GameRoll;
  rolling: boolean;
}
const palette: Record<string,string> = {
  'marrón':'#874b30','celeste':'#42b7dc','rosa':'#dd4aa1','naranja':'#ec7a31',
  'rojo':'#ca3b40','amarillo':'#dfb92c','verde':'#358f64','azul':'#3157a8'
};
export const DICE_REVEAL_MS=1450;
export const STEP_MS=300;
export const SCENE_SETTLE_MS=420;
export function journeyMs(roll:GameRoll){const distance=((roll.from+roll.d1+roll.d2)%40)===roll.to?roll.d1+roll.d2:1;return DICE_REVEAL_MS+distance*STEP_MS+SCENE_SETTLE_MS;}
const pawnColors=['#047857','#be123c','#2563eb','#7c3aed','#c2410c','#0f766e'];
function positive(n:number){return ((n%40)+40)%40}
function tileSymbol(space:GameSpace | undefined){
  switch(space?.type){
    case 'start':return '↗';
    case 'chance':return '✦';
    case 'community':return '◇';
    case 'jail':return '▦';
    case 'go_to_jail':return '⚑';
    case 'parking':return 'P';
    case 'tax':return '₥';
    case 'utility':return '≋';
    case 'railroad':return '♜';
    default:return '⌂';
  }
}
function Tile({space,position,center,side}:{space:GameSpace|undefined;position:number;center:boolean;side:-2|-1|0|1|2}){
  const type=space?.type||'other';
  const color=palette[space?.group?.toLowerCase()||'']||(
    type==='chance'?'#b28b62':type==='community'?'#926dd0':
    type==='tax'?'#cf5656':type==='railroad'?'#526b94':
    type==='utility'?'#4a8c9b':type==='start'?'#16876b':'#768397');
  return <div className={'mp-track-tile mp-track-tile-'+Math.abs(side)+(center?' mp-track-active':'')}
    style={{'--tile-color':color} as CSSProperties}
    data-offset={side} aria-hidden={!center}>
    <div className="mp-track-band"/>
    <div className="mp-track-inner">
      <span className="mp-track-number">CASILLA {position}</span>
      <span className="mp-track-symbol" aria-hidden="true">{tileSymbol(space)}</span>
      <strong className="mp-track-name">{space?.name||'Casilla '+position}</strong>
      <span className="mp-track-type">{space?.group||(
        type==='chance'?'EL CHAMÁN':type==='community'?'LA TÓMBOLA':
        type==='tax'?'IMPUESTO':type==='railroad'?'REFUGIO':
        type==='utility'?'ÁREA PROTEGIDA':'ESPECIAL')}</span>
    </div>
  </div>;
}
function Pawn({player,color}:{player?:GamePlayer;color:string}){
  return <div className="mp-pawn-wrap" aria-label={'Ficha de '+(player?.alias||'Jugador')}>
    <div className="mp-pawn-shadow"/>
    <svg className="mp-pawn" viewBox="0 0 100 124" role="img" aria-label="Ficha de jugador estilizada con volumen">
      <defs>
        <linearGradient id="mp-pawn-metal" x1="0" y1="0" x2="1" y2=".9">
          <stop offset="0" stopColor="#fff" stopOpacity=".7"/>
          <stop offset=".34" stopColor={color}/>
          <stop offset=".74" stopColor={color}/>
          <stop offset="1" stopColor="#071b21" stopOpacity=".9"/>
        </linearGradient>
      </defs>
      <ellipse cx="50" cy="111" rx="31" ry="10" fill="#1d2b32" opacity=".18"/>
      <path d="M27 92 Q35 83 39 56 C25 49 21 28 32 15 Q50 -1 68 15 C79 28 75 49 61 56 Q65 83 73 92 L81 105 Q50 117 19 105Z"
        fill="url(#mp-pawn-metal)" stroke="#102d30" strokeWidth="2"/>
      <ellipse cx="39" cy="25" rx="10" ry="15" fill="#fff" opacity=".32"/>
      <ellipse cx="50" cy="105" rx="32" ry="10" fill={color} stroke="#102d30" strokeWidth="2"/>
      <path d="M28 101 Q50 108 72 101" fill="none" stroke="#fff" opacity=".42" strokeWidth="3"/>
    </svg>
    <span className="mp-pawn-label">{player?.alias||'Jugador'}</span>
  </div>;
}
const faceRotation:Record<number,string>={
  1:'rotateX(0deg) rotateY(0deg)',2:'rotateX(-90deg)',3:'rotateY(-90deg)',
  4:'rotateY(90deg)',5:'rotateX(90deg)',6:'rotateY(180deg)'
};
function Die({value,spin,index}:{value:number;spin:boolean;index:number}){
  return <div className="mp-die-wrap" aria-label={'Dado '+(index+1)+': '+value}>
    <div className={'mp-die-cube'+(spin?' mp-die-rolling':'')} style={{
      transform:faceRotation[value]||faceRotation[1],
      animationDelay:index?'65ms':'0ms'
    }}>
      {[1,2,3,4,5,6].map(face=><div key={face} className={'mp-die-side mp-die-side-'+face}>
        {Array.from({length:face},(_,i)=><span key={i} className={'mp-dot mp-dot-'+face+'-'+i}/>)}
      </div>)}
    </div>
  </div>;
}

export default function AnimatedTurnScene({spaces,players,player,roll,rolling}:Props){
  const firstRollRef=useRef(roll?.id);
  const [phase,setPhase]=useState<'idle'|'dice'|'travel'>('idle');
  const [step,setStep]=useState(player?.position??0);
  const [rollId,setRollId]=useState(roll?.id);
  const total=roll?roll.d1+roll.d2:0;
  const normal=!!roll && positive(roll.from+total)===roll.to;
  useEffect(()=>{
    if(!roll || firstRollRef.current===roll.id)return;
    firstRollRef.current=roll.id;
    setRollId(roll.id);
    setStep(roll.from);
    setPhase('dice');
    const timers:ReturnType<typeof setTimeout>[]=[];
    const duration=normal?total:1;
    timers.push(setTimeout(()=>{
      setPhase('travel');
      for(let i=1;i<=duration;i++){
        timers.push(setTimeout(()=>{
          setStep(normal?positive(roll.from+i):roll.to);
          if(i===duration)setPhase('idle');
        },i*STEP_MS));
      }
    },DICE_REVEAL_MS));
    return ()=>timers.forEach(clearTimeout);
  },[roll?.id,roll?.from,roll?.to,normal,total]);
  // Avoid replaying an old roll when a user reloads the page or reconnects.
  const activePosition=roll && roll.id===rollId && phase!=='idle' ? step : (player?.position??0);
  const actor=player;
  const actorIndex=players.findIndex(p=>p.id===player?.id);
  const actorColor=pawnColors[Math.max(0,actorIndex)%pawnColors.length];
  const moving=phase==='travel';
  const diceMoving=rolling||phase==='dice';
  return <section className="mp-scene-root" aria-label="Recorrido de la ficha por las casillas" aria-live="off">
    <style>{`
    .mp-scene-root{width:100%;min-width:0;overflow:hidden}
    .mp-stage{position:relative;isolation:isolate;overflow:hidden;height:316px;border-radius:24px;
      background:radial-gradient(circle at 50% 24%,#e8f7ec 0,#d7ebdb 40%,#a6c8ad 100%);
      border:1px solid #b2d0b9;perspective:850px}
    .mp-stage:before{content:"";position:absolute;inset:0;opacity:.3;
      background:linear-gradient(135deg,transparent 48%,#fff 49%,transparent 50%),
      repeating-linear-gradient(0deg,transparent 0 31px,#54886a18 32px 33px)}
    .mp-stage-heading{position:absolute;z-index:5;left:14px;top:12px;font-size:10px;
      font-weight:900;letter-spacing:.15em;color:#215944}
    .mp-stage-count{position:absolute;z-index:5;right:12px;top:11px;border-radius:20px;
      background:#ffffffbd;padding:5px 9px;font-size:10px;font-weight:800;color:#1a5c44}
    .mp-stage-floor{position:absolute;bottom:-31px;left:-10%;width:120%;height:100px;
      border-radius:50%;background:radial-gradient(ellipse,#396b4880 0%,transparent 70%);transform:rotateX(58deg)}
    .mp-rail{position:absolute;inset:0;transform-style:preserve-3d;display:flex;align-items:center;justify-content:center}
    .mp-track-tile{position:absolute;top:94px;left:50%;width:min(40vw,153px);height:161px;
      transform-origin:center bottom;transform:translateX(-50%) translateZ(0) scale(1.02);
      border-radius:15px;background:linear-gradient(150deg,#fff 30%,#e7eee9 100%);
      border:2px solid #fff;box-shadow:0 12px 17px #23432b42;overflow:hidden;transition:transform .15s ease,filter .15s ease}
    .mp-track-tile[data-offset="-2"]{transform:translateX(calc(-50% - 219px)) translateZ(-120px) rotateY(24deg) scale(.76)}
    .mp-track-tile[data-offset="-1"]{transform:translateX(calc(-50% - 115px)) translateZ(-50px) rotateY(13deg) scale(.88)}
    .mp-track-tile[data-offset="1"]{transform:translateX(calc(-50% + 115px)) translateZ(-50px) rotateY(-13deg) scale(.88)}
    .mp-track-tile[data-offset="2"]{transform:translateX(calc(-50% + 219px)) translateZ(-120px) rotateY(-24deg) scale(.76)}
    .mp-track-tile-2{opacity:.54;filter:blur(.6px)}
    .mp-track-tile-1{opacity:.83}
    .mp-track-active{z-index:3;filter:brightness(1.03);box-shadow:0 16px 27px #23432b6a,0 0 0 3px #f6de8d}
    .mp-track-band{height:21px;background:var(--tile-color);box-shadow:inset 0 -3px #ffffff52}
    .mp-track-inner{height:calc(100% - 21px);display:flex;flex-direction:column;align-items:center;padding:7px;text-align:center;overflow:hidden}
    .mp-track-number{font-size:9px;font-weight:900;color:#5b6d63}
    .mp-track-symbol{font-size:29px;line-height:36px;font-weight:900;color:var(--tile-color)}
    .mp-track-name{font-size:11px;line-height:1.12;color:#153b31;display:-webkit-box;
      -webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden;max-width:100%;overflow-wrap:anywhere}
    .mp-track-type{margin-top:auto;font-size:8px;color:#64766b;font-weight:800;letter-spacing:.03em}
    .mp-pawn-wrap{position:absolute;z-index:6;left:50%;bottom:16px;width:120px;
      transform:translateX(-50%);display:flex;align-items:center;flex-direction:column;filter:drop-shadow(0 7px 6px #18372965)}
    .mp-pawn{width:94px;height:116px;transform:rotateX(7deg);transform-origin:bottom center}
    .mp-pawn-shadow{position:absolute;bottom:20px;width:82px;height:19px;border-radius:50%;
      background:#0d36296c;filter:blur(5px)}
    .mp-pawn-moving .mp-pawn{animation:mp-pawn-step .34s ease-in-out infinite alternate}
    .mp-pawn-label{margin-top:-11px;border:1px solid #b7e0c8;border-radius:20px;
      background:#073f31;color:#fff;font-size:11px;font-weight:900;padding:5px 13px;
      max-width:115px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .mp-caption{margin-top:9px;display:flex;align-items:center;justify-content:space-between;gap:8px;font-size:12px;color:#215744;font-weight:800}
    .mp-dice-bay{padding:14px 8px 5px;text-align:center}
    .mp-dice-pair{display:flex;justify-content:center;gap:25px;margin:16px 0 11px}
    .mp-die-wrap{width:56px;height:56px;perspective:400px;filter:drop-shadow(0 7px 6px #213d3360)}
    .mp-die-cube{width:54px;height:54px;position:relative;transform-style:preserve-3d;
      transition:transform .4s ease-out}
    .mp-die-rolling{animation:mp-die-spin 850ms cubic-bezier(.18,.68,.2,1.14) infinite}
    .mp-die-side{width:54px;height:54px;position:absolute;inset:0;border:2px solid #c1c8bb;
      border-radius:9px;background:linear-gradient(145deg,#fff,#f4f4ed 70%,#d2dacf);
      display:grid;grid-template-columns:repeat(3,1fr);grid-template-rows:repeat(3,1fr);padding:8px;gap:1px}
    .mp-dot{width:9px;height:9px;border-radius:50%;background:#123b30;align-self:center;justify-self:center;
      box-shadow:inset 0 1px 2px #0008}
    .mp-dot-1-0{grid-area:2/2}
    .mp-dot-2-0{grid-area:1/1}.mp-dot-2-1{grid-area:3/3}
    .mp-dot-3-0{grid-area:1/1}.mp-dot-3-1{grid-area:2/2}.mp-dot-3-2{grid-area:3/3}
    .mp-dot-4-0{grid-area:1/1}.mp-dot-4-1{grid-area:1/3}.mp-dot-4-2{grid-area:3/1}.mp-dot-4-3{grid-area:3/3}
    .mp-dot-5-0{grid-area:1/1}.mp-dot-5-1{grid-area:1/3}.mp-dot-5-2{grid-area:2/2}.mp-dot-5-3{grid-area:3/1}.mp-dot-5-4{grid-area:3/3}
    .mp-dot-6-0{grid-area:1/1}.mp-dot-6-1{grid-area:1/3}.mp-dot-6-2{grid-area:2/1}
    .mp-dot-6-3{grid-area:2/3}.mp-dot-6-4{grid-area:3/1}.mp-dot-6-5{grid-area:3/3}
    .mp-die-side-1{transform:translateZ(27px)}.mp-die-side-2{transform:rotateX(90deg) translateZ(27px)}
    .mp-die-side-3{transform:rotateY(90deg) translateZ(27px)}.mp-die-side-4{transform:rotateY(-90deg) translateZ(27px)}
    .mp-die-side-5{transform:rotateX(-90deg) translateZ(27px)}.mp-die-side-6{transform:rotateY(180deg) translateZ(27px)}
    @keyframes mp-die-spin{0%{transform:translateY(0) rotateX(0deg) rotateY(0deg) rotateZ(0deg)}
      38%{transform:translateY(-27px) rotateX(450deg) rotateY(520deg) rotateZ(110deg)}
      73%{transform:translateY(6px) rotateX(820deg) rotateY(830deg) rotateZ(210deg)}
      100%{transform:translateY(0) rotateX(1080deg) rotateY(1080deg) rotateZ(360deg)}}
    @keyframes mp-pawn-step{0%{transform:translateY(0) rotate(-4deg)}100%{transform:translateY(-17px) rotate(4deg)}}
    @media(min-width:600px){.mp-stage{height:355px}.mp-track-tile{width:160px;height:175px;top:100px}
      .mp-pawn-wrap{bottom:18px}.mp-track-name{font-size:12px}}
    @media(max-width:359px){.mp-stage{height:292px}.mp-track-tile{width:124px;height:150px;top:88px}
      .mp-track-tile[data-offset="-1"]{transform:translateX(calc(-50% - 97px)) translateZ(-50px) rotateY(13deg) scale(.88)}
      .mp-track-tile[data-offset="1"]{transform:translateX(calc(-50% + 97px)) translateZ(-50px) rotateY(-13deg) scale(.88)}
      .mp-track-name{font-size:10px}.mp-pawn{width:83px;height:103px}.mp-pawn-wrap{bottom:10px}}
    @media(prefers-reduced-motion:reduce){.mp-die-rolling,.mp-pawn-moving .mp-pawn{animation:none!important}
      .mp-track-tile,.mp-die-cube{transition:none!important}}
    `}</style>
    <div className="mp-stage">
      <span className="mp-stage-heading">RECORRIDO DE LA FICHA</span>
      <span className="mp-stage-count">{rolling||phase==='dice'?'Dados en movimiento':moving?'Avanzando…':'Tu ubicación'}</span>
      <div className="mp-stage-floor"/>
      <div className="mp-rail">
        {([-2,-1,0,1,2] as const).map(offset=>{
          const position=positive(activePosition+offset);
          return <Tile key={offset} position={position} space={spaces.find(s=>s.position===position)}
            center={offset===0} side={offset}/>;
        })}
      </div>
      <div className={moving?'mp-pawn-moving':''}><Pawn player={actor} color={actorColor}/></div>
    </div>
    <div className="mp-caption">
      <span>{actor?.alias||'Ficha en espera'}</span>
      <span>Casilla #{activePosition}{moving?' · avanzando':''}</span>
    </div>
    <div className="mp-dice-bay">
      <p className="text-[11px] font-black uppercase tracking-[.18em] text-emerald-800">
        {diceMoving?'Dados girando y rebotando…':roll?'Tu última tirada':'Dados de tu partida'}
      </p>
      <div className="mp-dice-pair">
        <Die value={roll?.d1??1} spin={diceMoving} index={0}/>
        <Die value={roll?.d2??1} spin={diceMoving} index={1}/>
      </div>
      <p className="text-xl font-black text-emerald-950" aria-live="polite">
        {diceMoving?'Girando…':roll?roll.d1+' + '+roll.d2+' = '+total:'Lanza los dados para comenzar'}
      </p>
      {roll&&!diceMoving&&<p className="mt-1 text-xs font-bold text-stone-500">
        {normal?'Movimiento de '+total+' casillas':'Movimiento especial hacia #'+roll.to}
        {roll.d1===roll.d2?' · Dobles':''}
      </p>}
    </div>
  </section>;
}
