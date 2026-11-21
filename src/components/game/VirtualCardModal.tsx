import { useEffect, useState } from 'react';
import type { CardChallenge, GameSnapshot } from '../../scripts/gameApi';
import type { GameActions } from './RoomApp';

interface Props { state:GameSnapshot; actions:GameActions; disabled:boolean; error:string }
const label=(deck:string)=>deck==='chaman'?'El Chamán':'La Tómbola';

export default function VirtualCardModal({state,actions,disabled,error}:Props) {
  const pending:CardChallenge|undefined=state.cards.find(card=>card.outcome==='pending');
  const [revealed,setRevealed]=useState(false);
  const [flipping,setFlipping]=useState(false);
  useEffect(()=>{setRevealed(false);setFlipping(false);},[pending?.id]);
  if(state.room.cardMode!=='virtual'||!pending)return null;
  const player=state.players.find(p=>p.id===pending.playerId);
  const myCard=pending.playerId===state.me.id;
  function reveal(){
    if(flipping||revealed)return;
    setFlipping(true);
    window.setTimeout(()=>{setRevealed(true);setFlipping(false);},550);
  }
  return <div className="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/75 p-3 backdrop-blur-sm sm:p-6">
    <div role="dialog" aria-modal="true" aria-labelledby="virtual-card-title"
      className="w-full max-w-md rounded-3xl border-2 border-amber-300 bg-[#fcf6e7] p-5 text-stone-950 shadow-2xl sm:p-8">
      <p className="text-center text-xs font-black uppercase tracking-[.16em] text-red-800">
        {label(pending.deck)} · Monopoly Perú F3182
      </p>
      <h2 id="virtual-card-title" className="mt-2 text-center text-xl font-black text-emerald-950">
        {revealed?'Carta obtenida':'¡Te tocó sacar una carta!'}
      </h2>
      <p className="mt-2 text-center text-sm text-stone-600">Turno de {player?.alias||'Jugador'}</p>
      <div className={'mx-auto mt-5 flex min-h-60 max-w-xs flex-col items-center justify-center rounded-2xl border-[5px] p-5 text-center shadow-lg transition-transform duration-500 '+
        (revealed?'border-red-700 bg-white':'border-amber-600 bg-emerald-900 text-white')+
        (flipping?' rotate-y-180 scale-95':'')}>
        {revealed ? <>
          <p className="text-xs font-black uppercase tracking-widest text-red-800">{label(pending.deck)}</p>
          <h3 className="mt-4 text-lg font-black text-stone-950">{pending.title}</h3>
          <p className="mt-4 text-base font-semibold leading-7 text-stone-800">{pending.instruction}</p>
        </> : <>
          <span className={'text-7xl '+(flipping?'animate-spin':'animate-pulse')} aria-hidden="true">🃏</span>
          <p className="mt-5 font-black tracking-widest">F3182</p>
          <p className="mt-2 text-xs text-emerald-100">Carta boca abajo</p>
        </>}
      </div>
      {!revealed ? <button type="button" disabled={flipping}
        onClick={reveal} className="mt-6 w-full rounded-xl bg-red-700 px-5 py-3 font-black text-white disabled:opacity-60">
          {flipping?'Revelando…':'Sacar carta'}
        </button> : <>
        <p className="mt-4 text-center text-sm leading-6 text-stone-700">
          {myCard?'Confirma la instrucción para aplicar el efecto una sola vez.':
            'La carta corresponde a '+(player?.alias||'otro jugador')+'. El efecto se aplicará al finalizar.'}
        </p>
        {error && <p role="alert" className="mt-3 rounded-lg bg-red-50 p-3 text-sm font-semibold text-red-800">{error}</p>}
        <button type="button" disabled={disabled||(!myCard&&state.me.role!=='host')}
          onClick={()=>void actions.finishVirtualCard(pending.id)}
          className="mt-4 w-full rounded-xl bg-emerald-800 px-5 py-3 font-black text-white disabled:opacity-40">
          {disabled?'Aplicando…':'Cumplir y finalizar carta'}
        </button>
        {!myCard&&state.me.role!=='host'&&<p className="mt-2 text-center text-xs text-stone-600">Solo el jugador del turno o el anfitrión pueden finalizar.</p>}
      </>}
    </div>
  </div>;
}
