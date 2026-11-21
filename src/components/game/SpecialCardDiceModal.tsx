import { useEffect, useRef, useState } from 'react';
import { money, type GameSnapshot } from '../../scripts/gameApi';
import type { GameActions, SpecialDiceResult } from './RoomApp';

interface Props {state:GameSnapshot;actions:GameActions;disabled:boolean;error:string}
const dots = ['','⚀','⚁','⚂','⚃','⚄','⚅'];

export default function SpecialCardDiceModal({state,actions,disabled,error}:Props){
  const pending=state.cards.find(card=>card.specialDicePending && card.arrivalStatus==='special_dice');
  const [d1,setD1]=useState(1),[d2,setD2]=useState(1);
  const [result,setResult]=useState<SpecialDiceResult|null>(null);
  const [resultCard,setResultCard]=useState<number|null>(null);
  const [rolling,setRolling]=useState(false);
  const timer=useRef<ReturnType<typeof setTimeout>|null>(null);
  useEffect(()=>()=>{if(timer.current)clearTimeout(timer.current)},[]);
  const mine=pending?.playerId===state.me.id && state.room.currentPlayerId===state.me.id;
  const active=!!pending && mine;
  if(!active && !result)return null;
  const target=pending ? state.spaces.find(s=>s.position===pending.targetPosition) :
    state.spaces.find(s=>s.position===state.cards.find(c=>c.id===resultCard)?.targetPosition);
  async function submit(){
    if(!pending || !mine || disabled || rolling)return;
    setRolling(true);
    const output=await actions.specialCardDice(pending.id,
      state.room.diceMode==='physical'?d1:undefined,
      state.room.diceMode==='physical'?d2:undefined);
    if(!output){setRolling(false);return;}
    setResultCard(pending.id);
    // Mostrar el lanzamiento visual antes de revelar sus valores.
    timer.current=setTimeout(()=>{setResult(output);setRolling(false);timer.current=null;},1100);
  }
  return <div className="fixed inset-0 z-[55] flex items-center justify-center overflow-y-auto bg-stone-950/80 p-3 backdrop-blur-sm">
    <section role="dialog" aria-modal="true" aria-labelledby="special-dice-title"
      className="w-full max-w-md rounded-3xl border-2 border-emerald-400 bg-[#fff9e8] p-5 text-center shadow-2xl sm:p-7">
      <p className="text-xs font-black uppercase tracking-widest text-emerald-800">El Chamán · Regla especial</p>
      <h2 id="special-dice-title" className="mt-2 text-2xl font-black text-emerald-950">
        Dados por área protegida
      </h2>
      <p className="mt-2 text-sm text-stone-600">{target?.name||'Área natural protegida'} pertenece a otro jugador.</p>
      <p className="mt-3 rounded-xl bg-emerald-50 p-3 text-sm font-bold text-emerald-950">
        Lanza dos dados adicionales. El alquiler será 10 veces la suma.
      </p>
      <div className="mx-auto mt-5 flex justify-center gap-5" aria-live="polite">
        {[result?.d1??d1,result?.d2??d2].map((value,index)=>
          <div key={index} className={'grid size-20 place-items-center rounded-2xl border-2 border-stone-300 bg-white text-6xl text-stone-950 shadow-lg '+
            (rolling?'animate-[special-dice-tumble_320ms_ease-in-out_infinite_alternate]':'')}
            style={{animationDelay:index?'100ms':'0ms'}}
            aria-label={'Dado '+(index+1)+(result?' resultado '+value:'')}>
            {rolling?dots[(Math.floor(Date.now()/100+index*3)%6)+1]:dots[value]}
          </div>)}
      </div>
      <style>{`@keyframes special-dice-tumble{
        from{transform:translateY(5px) rotate(-23deg) scale(.92)}
        to{transform:translateY(-22px) rotate(30deg) scale(1.1)}
      }@media(prefers-reduced-motion:reduce){.animate-\\[special-dice-tumble_320ms_ease-in-out_infinite_alternate\\]{animation:none!important}}`}</style>
      {result?<div className="mt-5">
        <p className="text-xl font-black text-emerald-950">{result.d1} + {result.d2} = {result.total}</p>
        <p className="mt-2 text-3xl font-black text-red-800">{money(result.rent)}</p>
        <p className="mt-1 text-xs font-bold text-stone-600">Alquiler registrado. Págalo para continuar el turno.</p>
        <button type="button" className="mt-5 w-full rounded-xl bg-emerald-800 px-4 py-3 font-bold text-white"
          onClick={()=>{setResult(null);setResultCard(null)}}>Continuar al pago</button>
      </div>:<>
        {state.room.diceMode==='physical' && !rolling &&
          <div className="mt-5 flex justify-center gap-4">
            {[{name:'Dado 1',value:d1,set:setD1},{name:'Dado 2',value:d2,set:setD2}].map(d=>
              <label className="grid gap-1 text-sm font-bold" key={d.name}>{d.name}
                <select aria-label={d.name} className="rounded-xl border border-emerald-300 bg-white px-4 py-3"
                  value={d.value} onChange={e=>d.set(Number(e.target.value))}>
                  {[1,2,3,4,5,6].map(n=><option value={n} key={n}>{n}</option>)}
                </select>
              </label>)}
          </div>}
        {error&&<p role="alert" className="mt-3 rounded-lg bg-red-50 p-3 text-sm text-red-800">{error}</p>}
        <button type="button" disabled={disabled||rolling}
          className="mt-5 w-full rounded-xl bg-red-700 px-4 py-3 font-bold text-white disabled:opacity-50"
          onClick={()=>void submit()}>
          {rolling?'Lanzando…':state.room.diceMode==='physical'?'Registrar tirada especial':'Lanzar dados virtuales'}
        </button>
      </>}
    </section>
  </div>;
}
