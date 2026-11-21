import { useEffect, useState } from 'react';
import type { CardChallenge, GameSnapshot } from '../../scripts/gameApi';
import type { GameActions } from './RoomApp';

interface Props { state:GameSnapshot; actions:GameActions; disabled:boolean; error:string }
const deckLabel=(deck:string)=>deck==='chaman'?'El Chamán':'La Tómbola';

export default function VirtualCardModal({state,actions,disabled,error}:Props){
  const pending:CardChallenge|undefined=state.cards.find(card=>card.outcome==='pending');
  const [flipping,setFlipping]=useState(false);
  const revealed=!!pending?.revealedAt;
  const ownTurn=!!pending && pending.playerId===state.me.id &&
    state.room.currentPlayerId===state.me.id;
  useEffect(()=>{setFlipping(false);},[pending?.id]);
  if(state.room.cardMode!=='virtual'||!pending)return null;

  // Los espectadores no reciben el contenido ni el modal hasta que
  // el jugador titular revele la carta en el servidor.
  if(!revealed&&!ownTurn)return null;

  const player=state.players.find(p=>p.id===pending.playerId);
  async function reveal(){
    if(!ownTurn||revealed||disabled||flipping)return;
    setFlipping(true);
    try{await actions.revealVirtualCard(pending.id);}
    finally{window.setTimeout(()=>setFlipping(false),580);}
  }
  return <div className="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/75 p-3 backdrop-blur-sm sm:p-6">
    <div role="dialog" aria-modal="true" aria-labelledby="virtual-card-title"
      className="w-full max-w-md rounded-3xl border-2 border-amber-300 bg-[#fcf6e7] p-5 text-stone-950 shadow-2xl sm:p-8">
      <p className="text-center text-xs font-black uppercase tracking-[.16em] text-red-800">
        {deckLabel(pending.deck)} · Monopoly Perú F3182
      </p>
      <h2 id="virtual-card-title" className="mt-2 text-center text-xl font-black text-emerald-950">
        {revealed?'Carta revelada':'¡Te tocó sacar una carta!'}
      </h2>
      <p className="mt-2 text-center text-sm text-stone-600">
        Turno de {player?.alias||'Jugador'}
      </p>
      <div className={'mx-auto mt-5 flex min-h-60 max-w-xs flex-col items-center justify-center rounded-2xl border-[5px] p-5 text-center shadow-lg transition-transform duration-500 '+
        (revealed?'border-red-700 bg-white':'border-amber-600 bg-emerald-900 text-white')+
        (flipping?' scale-95':'')}
        style={{transform:flipping?'rotateY(180deg) scale(.95)':'rotateY(0deg)'}}>
        {revealed && !flipping ? <>
          <p className="text-xs font-black uppercase tracking-widest text-red-800">{deckLabel(pending.deck)}</p>
          <h3 className="mt-4 text-lg font-black text-stone-950">{pending.title}</h3>
          <p className="mt-4 text-base font-semibold leading-7 text-stone-800">{pending.instruction}</p>
        </> : <>
          <span className="animate-pulse text-7xl" aria-hidden="true">🃏</span>
          <p className="mt-5 font-black tracking-widest">F3182</p>
          <p className="mt-2 text-xs text-emerald-100">Carta boca abajo</p>
        </>}
      </div>
      {!revealed ? <>
        <button type="button" disabled={disabled||flipping||!ownTurn}
          onClick={()=>void reveal()}
          className="mt-6 w-full rounded-xl bg-red-700 px-5 py-3 font-black text-white disabled:opacity-60">
          {flipping?'Revelando…':'Sacar carta'}
        </button>
        <p className="mt-2 text-center text-xs text-stone-600">Solo el jugador de turno puede revelar esta carta.</p>
      </> : ownTurn ? <>
        <p className="mt-4 text-center text-sm leading-6 text-stone-700">
          Confirma para aplicar el efecto de la carta una sola vez.
        </p>
        {error&&<p role="alert" className="mt-3 rounded-lg bg-red-50 p-3 text-sm font-semibold text-red-800">{error}</p>}
        <button type="button" disabled={disabled||flipping} onClick={()=>void actions.finishVirtualCard(pending.id)}
          className="mt-4 w-full rounded-xl bg-emerald-800 px-5 py-3 font-black text-white disabled:opacity-40">
          {disabled?'Aplicando…':'Cumplir y finalizar carta'}
        </button>
      </> : <p role="status" className="mt-5 rounded-xl bg-emerald-50 p-4 text-center text-sm font-semibold text-emerald-950">
        {player?.alias||'El jugador del turno'} reveló esta carta. Esperando que la finalice.
      </p>}
    </div>
  </div>;
}
