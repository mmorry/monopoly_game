import { useState, type FormEvent } from 'react';
import { money, type GameSnapshot, type GameSpace, type SpaceType } from '../../scripts/gameApi';
import type { GameActions } from './RoomApp';
interface Props { state: GameSnapshot; actions: GameActions; disabled: boolean }
const card='rounded-2xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6';
const field='min-h-11 w-full rounded-xl border-2 border-stone-300 px-3 py-2 text-base focus-visible:outline-emerald-700';
const btn='rounded-xl bg-emerald-700 px-4 py-3 text-sm font-bold text-white disabled:opacity-40';
const groups: Record<string,string> = {
  marrón:'#8b4513',celeste:'#38bdf8',rosa:'#ec4899',naranja:'#f97316',
  rojo:'#dc2626',amarillo:'#eab308',verde:'#15803d',azul:'#1d4ed8'
};
const spaceTypes: [SpaceType,string][]=[
  ['start','Salida'],['property','Terreno'],['railroad','Estación / transporte'],
  ['utility','Servicio público'],['tax','Impuesto'],['chance','La Tómbola'],
  ['community','El Chamán'],['jail','Cárcel'],['go_to_jail','Ve a la cárcel'],
  ['parking','Estacionamiento'],['other','Otra casilla']
];
const numberOrNull = (value: FormDataEntryValue | null) => {
  const raw = String(value??'').trim();
  return raw==='' ? null : Number(raw);
};
export default function BoardPanel({state,actions,disabled}:Props) {
  const [selection,setSelection]=useState(0);
  const selected=state.spaces.find(s=>s.position===selection);
  const waiting=state.room.status==='waiting';
  const active=state.room.status==='active';
  const host=state.me.role==='host';
  const mine=state.me.id;
  const myPlayer=state.players.find(p=>p.id===mine);
  const myTurn=state.room.currentPlayerId===mine;
  const unconfigured=state.spaces.filter(s=>['property','railroad','utility'].includes(s.type) && !s.price).length;
  const owned=selected?.ownerId===mine;
  const holder=state.players.find(p=>p.id===selected?.ownerId);

  function saveSpace(event:FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const data=new FormData(event.currentTarget);
    const rentsRaw=String(data.get('rents') || '').trim();
    let rents: number[] | null=null;
    if(rentsRaw) {
      rents=rentsRaw.split(',').map(value=>Number(value.trim()));
      if (rents.length!==6 || rents.some(value=>!Number.isSafeInteger(value)||value<0)) {
        window.alert('El alquiler debe contener seis importes enteros no negativos separados por coma.');
        return;
      }
    }
    const name=String(data.get('name') || '').trim();
    if(!name) return;
    void actions.setSpace({
      p_position: selection,
      p_name: name,
      p_type: String(data.get('type') || 'other'),
      p_group: String(data.get('group') || '').trim() || null,
      p_price: numberOrNull(data.get('price')),
      p_rents: rents,
      p_build_cost: numberOrNull(data.get('buildCost')),
      p_mortgage: numberOrNull(data.get('mortgage'))
    });
  }

  return <div className="grid gap-5">
    {waiting && <section className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm leading-6 text-amber-950">
      <strong>Configuración de tu edición física.</strong> Las 40 posiciones son una plantilla genérica, no una reproducción exacta del tablero peruano.
      El anfitrión debe copiar nombres, precios y alquileres de las tarjetas reales.
      {unconfigured>0 && <span className="mt-1 block font-bold">Propiedades sin precio: {unconfigured}.</span>}
    </section>}
    <section className={card}>
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-xl font-black text-emerald-950">Tablero digital · 40 casillas</h2>
        <p className="text-xs font-semibold text-stone-500">Toca una casilla para verla</p>
      </div>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-8">
        {state.spaces.map(s=>{
          const occupants=state.players.filter(p=>!p.bankrupt && p.position===s.position);
          const owner=state.players.find(p=>p.id===s.ownerId);
          return <button type="button" key={s.position} aria-pressed={selection===s.position}
            onClick={()=>setSelection(s.position)}
            className={'min-h-28 overflow-hidden rounded-xl border-2 bg-stone-50 p-2 text-left shadow-sm transition hover:bg-stone-100 focus-visible:outline-2 focus-visible:outline-emerald-700 '+
              (selection===s.position?'border-emerald-800 ring-2 ring-emerald-300':'border-stone-200')}>
            <div className="mb-2 h-2 rounded-full" style={{backgroundColor: s.group?groups[s.group]||'#94a3b8':'#d6d3d1'}}/>
            <span className="block text-[11px] font-black text-stone-500">#{s.position}</span>
            <span className="mt-1 line-clamp-2 block text-xs font-bold leading-tight text-emerald-950">{s.name}</span>
            {s.price!==null && <span className="mt-1 block text-xs font-bold text-stone-600">{money(s.price)}</span>}
            {owner && <span className="mt-1 block truncate text-[11px] text-stone-600">Dueño: {owner.alias}</span>}
            {s.mortgaged && <span className="mt-1 block text-[11px] font-bold text-red-700">Hipotecada</span>}
            {s.level>0 && <span className="mt-1 block text-[11px] font-semibold text-emerald-700">{s.level===5?'Hotel':s.level+' casas'}</span>}
            {occupants.length>0 && <div className="mt-2 flex flex-wrap gap-1">
              {occupants.map(p=><span key={p.id} title={p.alias} className="grid size-6 place-items-center rounded-full bg-emerald-700 text-[10px] font-black text-white">{p.alias[0]?.toUpperCase()}</span>)}
            </div>}
          </button>;
        })}
      </div>
    </section>
    {selected && <section className={card}>
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="text-xs font-black uppercase tracking-widest text-red-700">Casilla {selected.position}</p>
          <h2 className="mt-1 text-2xl font-black text-emerald-950">{selected.name}</h2>
          <p className="mt-1 text-sm text-stone-600">
            {spaceTypes.find(([type])=>type===selected.type)?.[1] || selected.type}
            {selected.group ? ' · Grupo '+selected.group : ''}
          </p>
        </div>
        <div className="text-right">
          <p className="text-xl font-black text-emerald-900">{selected.price!==null?money(selected.price):'Sin precio'}</p>
          {holder && <p className="text-sm font-semibold text-stone-700">Dueño: {holder.alias}</p>}
        </div>
      </div>
      {selected.rents && <div className="mt-4">
        <p className="text-sm font-bold text-emerald-950">Alquiler base / 1–4 casas / hotel</p>
        <div className="mt-2 flex flex-wrap gap-2">
          {selected.rents.map((n,i)=><span key={i} className="rounded-lg bg-stone-100 px-2 py-1 text-xs font-semibold">{i===0?'Base':i===5?'Hotel':i+' casa(s)'}: {money(n)}</span>)}
        </div>
      </div>}
      {selected.buildCost!==null && <p className="mt-3 text-sm">Construcción: {money(selected.buildCost)} · Hipoteca: {money(selected.mortgage??Math.floor((selected.price||0)/2))}</p>}
      {selected.mortgaged && <p className="mt-2 font-bold text-red-700">Esta propiedad está hipotecada y no cobra alquiler.</p>}
      {active && ['property','railroad','utility'].includes(selected.type) && <div className="mt-5 flex flex-wrap gap-2">
        {!selected.ownerId && selected.price!==null && selected.price>0 && myTurn && state.room.turnRolled &&
          myPlayer?.position===selected.position && state.room.pendingAmount===0 &&
          <button className={btn} disabled={disabled || !myPlayer || myPlayer.balance<selected.price}
            onClick={()=>void actions.property('buy',selected.position)}>Comprar</button>}
        {owned && <>
          {selected.mortgaged
            ? <button className={btn} disabled={disabled} onClick={()=>void actions.property('unmortgage',selected.position)}>Levantar hipoteca</button>
            : <button className={btn} disabled={disabled} onClick={()=>void actions.property('mortgage',selected.position)}>Hipotecar</button>}
          {selected.type==='property' && <>
            <button className={btn} disabled={disabled || selected.level>=5} onClick={()=>void actions.property('build',selected.position)}>Construir casa/hotel</button>
            <button className={btn} disabled={disabled || selected.level===0} onClick={()=>void actions.property('sell_building',selected.position)}>Vender construcción</button>
          </>}
        </>}
      </div>}
      {host && waiting && <form key={selected.position+'-'+state.room.revision} onSubmit={saveSpace} className="mt-6 grid gap-4 rounded-xl border border-emerald-100 bg-emerald-50 p-4">
        <h3 className="text-lg font-black text-emerald-950">Editar casilla {selected.position}</h3>
        <label className="grid gap-1 text-sm font-semibold">Nombre real de la casilla
          <input className={field} name="name" required maxLength={80} defaultValue={selected.name}/></label>
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="grid gap-1 text-sm font-semibold">Tipo
            <select className={field} name="type" defaultValue={selected.type}>
              {spaceTypes.map(([type,label])=><option key={type} value={type}>{label}</option>)}
            </select></label>
          <label className="grid gap-1 text-sm font-semibold">Grupo de color
            <select className={field} name="group" defaultValue={selected.group || ''}>
              <option value="">Sin color</option>
              {Object.keys(groups).map(group=><option key={group} value={group}>{group}</option>)}
            </select></label>
          <label className="grid gap-1 text-sm font-semibold">Precio / impuesto
            <input className={field} name="price" type="number" min="0" step="1" defaultValue={selected.price??''}/></label>
          <label className="grid gap-1 text-sm font-semibold">Valor de hipoteca
            <input className={field} name="mortgage" type="number" min="0" step="1" defaultValue={selected.mortgage??''}/></label>
          <label className="grid gap-1 text-sm font-semibold">Costo por casa/hotel
            <input className={field} name="buildCost" type="number" min="0" step="1" defaultValue={selected.buildCost??''}/></label>
          <label className="grid gap-1 text-sm font-semibold">6 alquileres, separados por comas
            <input className={field} name="rents" placeholder="2, 10, 30, 90, 160, 250"
              defaultValue={selected.rents?.join(', ') || ''}/></label>
        </div>
        <p className="text-xs text-stone-600">Para estaciones, los cuatro primeros alquileres corresponden a tener 1, 2, 3 y 4 estaciones. Para servicios, el importe se calcula según los dados.</p>
        <button type="submit" disabled={disabled} className={btn}>Guardar casilla</button>
      </form>}
    </section>}
  </div>;
}
