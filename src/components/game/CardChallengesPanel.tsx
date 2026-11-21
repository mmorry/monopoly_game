import { useEffect, useState, type FormEvent } from 'react';
import { getF3182Cards, money, type CardChallenge, type F3182PhysicalCard, type GameSnapshot } from '../../scripts/gameApi';
import type { GameActions } from './RoomApp';

interface Props { state:GameSnapshot; actions:GameActions; disabled:boolean; compact?:boolean }
const card='rounded-2xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6';
const input='min-h-11 w-full rounded-xl border-2 border-stone-300 bg-white px-3 py-2 text-base text-stone-900 focus-visible:outline-2 focus-visible:outline-emerald-700';
const button='rounded-xl bg-emerald-700 px-4 py-3 text-sm font-bold text-white disabled:cursor-not-allowed disabled:opacity-40';
const effects=[
  ['none','Sin efecto bancario (registrar reto)'],
  ['bank_receive','El banco paga al jugador'],
  ['bank_pay','El jugador paga al banco'],
  ['pay_player','El jugador paga a otro'],
  ['collect_player','Otro jugador paga al jugador'],
  ['move','Mover a otra casilla'],
  ['jail','Enviar a la cárcel'],
  ['release_jail','Salir de la cárcel']
] as const;
const getDeck=(deck:string)=>deck==='chaman'?'El Chamán':'La Tómbola';
const getOutcome=(outcome:string)=>{
  if(outcome==='pending')return 'Por resolver';
  if(outcome==='completed')return 'Cumplido';
  if(outcome==='failed')return 'No cumplido';
  return 'Anulado';
};
function countMoneyEffect(c:CardChallenge){return c.amount && c.effect!=='none' ? money(c.amount):'';}

export default function CardChallengesPanel({state,actions,disabled,compact=false}:Props){
 const host=state.me.role==='host';
 const active=state.room.status==='active';
 const current=state.players.find(p=>p.id===state.room.currentPlayerId);
 const pending=state.cards.find(c=>c.outcome==='pending') || null;
 const [effect,setEffect]=useState('none');
 const [manualDeck,setManualDeck]=useState<'chaman'|'tombola'>('chaman');
 const [manualNote,setManualNote]=useState('');
 const [cardNumber,setCardNumber]=useState('');
 const [outcome,setOutcome]=useState('completed');
 const [other,setOther]=useState('');
 const [numberAmount,setNumberAmount]=useState('');
 const [newPosition,setNewPosition]=useState('');
 const [title,setTitle]=useState('');
 const [instruction,setInstruction]=useState('');
 const [physicalCards,setPhysicalCards]=useState<F3182PhysicalCard[]>([]);
 const [selectedPhysical,setSelectedPhysical]=useState('');
 const [catalogFailure,setCatalogFailure]=useState('');
 useEffect(()=>{
   let live=true;
   void getF3182Cards().then(cards=>{if(live)setPhysicalCards(cards);})
     .catch(e=>{if(live)setCatalogFailure(e instanceof Error?e.message:'Sin conexión al catálogo');});
   return ()=>{live=false;};
 },[]);
 const catalogForDeck=physicalCards.filter(card=>card.deck===pending?.deck);
 const physicalSelected=physicalCards.find(card=>card.deck+':'+card.number===selectedPhysical);
 function choosePhysical(value:string){
   setSelectedPhysical(value);
   const found=physicalCards.find(c=>c.deck+':'+c.number===value);
   if(!found)return;
   setCardNumber(String(found.number));
   setTitle(found.title);
   setInstruction(found.instruction);
   const direct=['bank_receive','bank_pay','move','move_pass_go','move_collect','jail'];
   const action=direct.includes(found.effect)?(found.effect.startsWith('move')?'move':found.effect):'none';
   setEffect(action);
   setNumberAmount(action==='bank_receive'||action==='bank_pay'?String(found.value??''):'');
   if(action==='move')setNewPosition(String(found.value??0));
   setManualNote('');
 }
 useEffect(()=>{
   if(state.room.cardMode!=='virtual' || !pending) return;
   const found=physicalCards.find(item=>item.deck===pending.deck && item.number===pending.cardNumber);
   if(!found) return;
   choosePhysical(found.deck+':'+found.number);
 },[state.room.cardMode,pending?.id,pending?.cardNumber,physicalCards]);
 const eligible=state.players.filter(p=>p.id!==pending?.playerId && !p.bankrupt);
 const moneyEffect=['bank_receive','bank_pay','pay_player','collect_player'].includes(effect);
 const otherEffect=['pay_player','collect_player'].includes(effect);

 function resolve(e:FormEvent<HTMLFormElement>){
   e.preventDefault();
   if(!pending)return;
   if(!window.confirm('¿Registrar el resultado y aplicar el efecto seleccionado? La operación no se puede repetir.'))return;
   void actions.card('resolve',{
     id:pending.id,
     cardNumber:cardNumber || null,
     title:title.trim(),instruction:instruction.trim(),outcome,
     effect,amount:moneyEffect?Number(numberAmount):null,
     otherPlayerId:otherEffect?other:null,
     targetPosition:effect==='move'?Number(newPosition):null,
     note:manualNote.trim()||null
   });
 }
 function cancel(){
   if(!pending || !host || !manualNote.trim())return;
   if(!window.confirm('¿Anular esta carta? El registro quedará en el historial.'))return;
   void actions.card('cancel',{id:pending.id,note:manualNote.trim()});
 }

 const summary=state.cardTotals;
 return <div className="grid gap-5">
   <section className={card}>
     <div className="flex flex-wrap items-start justify-between gap-3">
       <div>
         <p className="text-xs font-black uppercase tracking-widest text-red-700">Monopoly Perú F3182</p>
         <h2 className="mt-1 text-xl font-black text-emerald-950">El Chamán y La Tómbola</h2>
         <p className="mt-2 text-sm text-stone-600">{state.room.cardMode==='virtual'
           ? 'Modo virtual: el servidor reparte cada baraja por separado, sin repetir ninguna de sus 16 cartas hasta completar la vuelta. El anfitrión confirma los efectos.'
           : 'Modo físico: lee la carta del mazo real, selecciónala en la aplicación y registra sus consecuencias.'}</p>
       </div>
       <span className="rounded-xl bg-amber-100 px-3 py-2 text-xs font-bold text-amber-950">16 cartas por baraja</span>
     </div>
     <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-5">
       {[
         ['Chamán',summary.chaman],
         ['Tómbola',summary.tombola],
         ['Pendientes',summary.pending],
         ['Cumplidos',summary.completed],
         ['No cumplidos',summary.failed]
       ].map(([name,n])=><div className="rounded-xl bg-stone-50 p-3" key={String(name)}>
         <p className="text-xs font-semibold text-stone-600">{name}</p>
         <p className="mt-1 text-2xl font-black text-emerald-950">{n}</p>
       </div>)}
     </div>
   </section>

   {pending && <section className={card+' border-2 border-amber-400'}>
     <p className="text-xs font-black uppercase tracking-widest text-red-700">Carta pendiente · turno {pending.turn}</p>
     <h2 className="mt-1 text-2xl font-black text-emerald-950">{getDeck(pending.deck)}</h2>
     <p className="mt-2 text-sm text-stone-700">Jugador: <strong>{state.players.find(p=>p.id===pending.playerId)?.alias || 'Jugador'}</strong>.
       {pending.source==='dice'?' Carta generada al caer en la casilla '+pending.position+'.':' Registro manual del anfitrión.'}
     </p>
     {!host && <p role="status" className="mt-4 rounded-xl bg-amber-50 p-4 text-sm font-semibold text-amber-950">
       Esperando al anfitrión para registrar el reto y sus efectos. No se puede finalizar el turno hasta resolverlo.
     </p>}
     {host && <form key={pending.id} className="mt-5 grid gap-4" onSubmit={resolve}>
       <label className="grid gap-1 text-sm font-semibold">{state.room.cardMode==='virtual'?'Carta virtual asignada por el servidor':'Seleccionar carta F3182 fotografiada'}
         <select aria-label="Tarjeta física F3182" className={input} value={selectedPhysical}
           disabled={state.room.cardMode==='virtual'}
           onChange={e=>choosePhysical(e.target.value)}>
           <option value="">Selecciona la carta que apareció en el mazo físico</option>
           {catalogForDeck.map(item=><option key={item.number} value={item.deck+':'+item.number}>
             {String(item.number).padStart(2,'0')} · {item.title}</option>)}
         </select>
       </label>
       {catalogFailure && <p role="alert" className="text-sm text-red-700">{catalogFailure}</p>}
       {physicalSelected && !['bank_receive','bank_pay','move','jail'].includes(physicalSelected.effect) &&
         <p className="rounded-xl border border-amber-300 bg-amber-50 p-3 text-sm text-amber-950">
           Esta tarjeta tiene un efecto especial ({physicalSelected.effect}).
           El catálogo conserva la instrucción original, pero el efecto completo todavía requiere
           gestión manual del anfitrión. No marques la carta como liquidada sin comprobar
           también todos sus pagos, bonificaciones y movimientos en la banca.
         </p>}
       {state.room.cardMode==='virtual' && <p className="rounded-xl bg-blue-50 p-3 text-sm text-blue-900">
         Carta asignada automáticamente. Si corresponde mover a la Salida, cobrar a todos o reparar propiedades,
         verifica que se apliquen todas las consecuencias antes de resolverla.
       </p>}
       <label className="grid gap-1 text-sm font-semibold">Número de carta (opcional, 1 a 16)
         <input className={input} type="number" min="1" max="16" step="1" value={cardNumber}
           readOnly={state.room.cardMode==='virtual'}
           onChange={e=>setCardNumber(e.target.value)} placeholder="Si las cartas están numeradas"/></label>
       <label className="grid gap-1 text-sm font-semibold">Nombre o encabezado de la carta
         <input className={input} required minLength={2} maxLength={100} value={title}
           onChange={e=>setTitle(e.target.value)} placeholder="Escribe el título visible en la carta"/></label>
       <label className="grid gap-1 text-sm font-semibold">Reto o instrucción real
         <textarea className={input+' min-h-24'} required minLength={2} maxLength={500}
           value={instruction} onChange={e=>setInstruction(e.target.value)}
           placeholder="Transcribe o resume la instrucción de la carta física"/></label>
       <div className="grid gap-4 sm:grid-cols-2">
         <label className="grid gap-1 text-sm font-semibold">¿Se cumplió el reto?
           <select className={input} value={outcome} onChange={e=>setOutcome(e.target.value)}>
             <option value="completed">Sí, cumplido</option>
             <option value="failed">No, incumplido</option>
           </select></label>
         <label className="grid gap-1 text-sm font-semibold">Efecto a aplicar
           <select className={input} value={effect} onChange={e=>setEffect(e.target.value)}>
             {effects.map(([v,label])=><option key={v} value={v}>{label}</option>)}
           </select></label>
       </div>
       {moneyEffect && <label className="grid gap-1 text-sm font-semibold">Importe de la tarjeta (M)
         <input className={input} required type="number" min="1" max="1000000000" step="1"
           value={numberAmount} onChange={e=>setNumberAmount(e.target.value)} placeholder="Ej. 50"/></label>}
       {otherEffect && <label className="grid gap-1 text-sm font-semibold">Otro jugador
         <select className={input} required value={other} onChange={e=>setOther(e.target.value)}>
           <option value="">Selecciona jugador</option>
           {eligible.map(p=><option key={p.id} value={p.id}>{p.alias} · {money(p.balance)}</option>)}
         </select></label>}
       {effect==='move' && <label className="grid gap-1 text-sm font-semibold">Casilla de destino
         <input className={input} required type="number" min="0" max="39" step="1" value={newPosition}
           onChange={e=>setNewPosition(e.target.value)}/></label>}
       <label className="grid gap-1 text-sm font-semibold">Observación (opcional)
         <textarea className={input} maxLength={500} value={manualNote}
           onChange={e=>setManualNote(e.target.value)} placeholder="Ej. Completó el reto en el tiempo indicado"/></label>
       <p className="rounded-lg bg-stone-50 p-3 text-xs text-stone-700">
         El resultado y el efecto son independientes: si la carta cobra por perder el reto, marca «No, incumplido» y «El jugador paga al banco».
         Los movimientos de la tarjeta se ejecutan una sola vez y quedan registrados.
       </p>
       <div className="flex flex-wrap gap-3">
         <button disabled={disabled||!active} className={button} type="submit">Resolver carta y contabilizar</button>
         <button disabled={disabled||!active||manualNote.trim().length<2} className="rounded-xl border-2 border-red-200 px-4 py-2 text-sm font-bold text-red-800 disabled:opacity-40" type="button"
           onClick={cancel}>Anular con motivo</button>
       </div>
     </form>}
   </section>}

   {!pending && !compact && active && host && <section className={card}>
     <h3 className="text-lg font-black text-emerald-950">Registrar una carta manualmente</h3>
     <p className="mt-1 text-sm text-stone-600">Para movimientos físicos o instrucciones especiales que no provengan de la tirada de dados.</p>
     <div className="mt-3 flex flex-wrap gap-3">
       <select aria-label="Baraja para registro manual" className={input+' max-w-52'} value={manualDeck}
         onChange={e=>setManualDeck(e.target.value as 'chaman'|'tombola')}>
         <option value="chaman">El Chamán</option>
         <option value="tombola">La Tómbola</option>
       </select>
       <button disabled={disabled||!current} className={button} type="button"
         onClick={()=>void actions.card('draw_manual',{deck:manualDeck})}>
         Registrar carta para {current?.alias || 'jugador actual'}
       </button>
     </div>
   </section>}

   {!compact && <section className={card}>
     <h3 className="text-xl font-black text-emerald-950">Historial de cartas y retos</h3>
     <p className="mt-1 text-sm text-stone-600">Cada carta queda asociada al turno, jugador, resultado y operación bancaria.</p>
     {state.cards.length===0 && <p className="mt-4 text-sm text-stone-500">Aún no se ha registrado ninguna carta.</p>}
     <ol className="mt-4 grid gap-3">
       {state.cards.map(c=><li key={c.id} className="rounded-xl border border-stone-200 bg-stone-50 p-4">
         <div className="flex flex-wrap items-center justify-between gap-2">
           <span className="font-bold text-emerald-950">{getDeck(c.deck)} · {c.title || 'Carta sin leer'}</span>
           <span className={'rounded-full px-3 py-1 text-xs font-bold '+
             (c.outcome==='pending'?'bg-amber-100 text-amber-900':
              c.outcome==='completed'?'bg-emerald-100 text-emerald-900':'bg-stone-200 text-stone-800')}>
             {getOutcome(c.outcome)}</span>
         </div>
         <p className="mt-1 text-xs text-stone-500">Turno {c.turn} · {state.players.find(p=>p.id===c.playerId)?.alias||'Jugador'}</p>
         {c.instruction && <p className="mt-2 text-sm text-stone-700">{c.instruction}</p>}
         {c.amount && <p className="mt-2 text-sm font-bold text-emerald-900">Movimiento: {countMoneyEffect(c)}</p>}
         {c.note && <p className="mt-1 text-xs text-stone-600">Nota: {c.note}</p>}
       </li>)}
     </ol>
   </section>}
 </div>;
}
