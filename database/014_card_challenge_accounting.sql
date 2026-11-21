-- Monopoly Perú F3182 | 014_card_challenge_accounting.sql
-- Guarda qué carta física de Chamán/Tómbola salió, su resultado y sus efectos.
-- Los textos e importes reales quedan SIN precargar hasta verificar las tarjetas F3182.
begin;

create table public.room_card_challenges (
 id bigint generated always as identity primary key,
 room_id uuid not null references public.rooms(id) on delete cascade,
 roll_id bigint unique references public.room_rolls(id) on delete cascade,
 player_id uuid not null references public.room_players(id) on delete cascade,
 turn_number integer not null check(turn_number >= 1),
 position smallint not null check(position between 0 and 39),
 deck text not null check(deck in ('chaman','tombola')),
 card_number smallint check(card_number between 1 and 16),
 card_title text check(card_title is null or length(btrim(card_title)) between 2 and 100),
 challenge_text text check(challenge_text is null or length(btrim(challenge_text)) between 2 and 500),
 outcome text not null default 'pending' check(outcome in ('pending','completed','failed','cancelled')),
 effect_kind text not null default 'none'
   check(effect_kind in ('none','bank_receive','bank_pay','pay_player','collect_player','move','jail','release_jail')),
 effect_amount bigint check(effect_amount is null or effect_amount between 1 and 1000000000),
 other_player_id uuid references public.room_players(id) on delete set null,
 target_position smallint check(target_position between 0 and 39),
 result_note text check(result_note is null or length(btrim(result_note)) between 2 and 500),
 source_type text not null default 'dice' check(source_type in ('dice','manual')),
 drawn_at timestamptz not null default now(),
 resolved_at timestamptz,
 resolved_by uuid references public.room_players(id) on delete set null,
 check ((outcome='pending' and resolved_at is null) or
        (outcome<>'pending' and resolved_at is not null))
);
create unique index room_card_challenges_single_pending on public.room_card_challenges(room_id)
 where outcome='pending';
create index room_card_challenges_recent on public.room_card_challenges(room_id,id desc);
create index room_card_challenges_player on public.room_card_challenges(room_id,player_id);

alter table public.room_card_challenges enable row level security;
revoke all on public.room_card_challenges from public,anon,authenticated;
revoke all on sequence public.room_card_challenges_id_seq from public,anon,authenticated;

alter table public.room_ledger
 add column card_challenge_id bigint references public.room_card_challenges(id) on delete set null;
create index room_ledger_challenge_idx on public.room_ledger(card_challenge_id)
 where card_challenge_id is not null;

-- Whenever a dice roll lands on a physical card square, create ONE pending card.
create function game_private.card_from_dice()
returns trigger language plpgsql security definer set search_path=''
as $trigger$
declare v_type text; v_deck text;
begin
 select space_type into v_type from public.room_spaces
   where room_id=new.room_id and position=new.to_position;
 v_deck:=case v_type when 'chance' then 'chaman'
                     when 'community' then 'tombola' else null end;
 if v_deck is not null then
   insert into public.room_card_challenges
     (room_id,roll_id,player_id,turn_number,position,deck,source_type)
   values(new.room_id,new.id,new.player_id,new.turn_number,new.to_position,v_deck,'dice');
   insert into public.room_events(room_id,actor_id,event_type,payload)
   values(new.room_id,new.player_id,'card_drawn',
     jsonb_build_object('deck',v_deck,'position',new.to_position,'rollId',new.id));
 end if;
 return new;
end;
$trigger$;
revoke all on function game_private.card_from_dice() from public,anon,authenticated;
create trigger room_rolls_draw_card
 after insert on public.room_rolls for each row
 execute function game_private.card_from_dice();

-- Stop a turn from advancing before the physical card has been accounted for.
do $patch$
declare definition text;
begin
 definition := pg_get_functiondef('public.game_action(text,text,text,jsonb)'::regprocedure);
 if position('if v_room.pending_amount>0 then raise exception ''Debes saldar el pago pendiente'';end if;' in definition)=0 then
   raise exception 'Unexpected game_action source. Patch aborted to avoid breaking turns';
 end if;
 definition := replace(definition,
   'if v_room.pending_amount>0 then raise exception ''Debes saldar el pago pendiente'';end if;',
   'if v_room.pending_amount>0 then raise exception ''Debes saldar el pago pendiente'';end if;
   if exists(select 1 from public.room_card_challenges
      where room_id=v_room.id and player_id=v_me and outcome=''pending'') then
      raise exception ''Primero registra y resuelve la carta de El Chamán o La Tómbola'';
   end if;');
 execute definition;
end;
$patch$;

create function public.game_card_snapshot(p_code text,p_token text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_room uuid;v_me uuid;
begin
 select room_id,player_id into v_room,v_me from game_private.member(p_code,p_token);
 if v_me is null then raise exception 'Sesión inválida o expirada';end if;
 return jsonb_build_object(
   'cards',coalesce((
     select jsonb_agg(c.payload order by c.id desc)
     from (
       select d.id,
         jsonb_build_object(
          'id',d.id,'playerId',d.player_id,'turn',d.turn_number,
          'position',d.position,'deck',d.deck,'cardNumber',d.card_number,
          'title',d.card_title,'instruction',d.challenge_text,
          'outcome',d.outcome,'effect',d.effect_kind,'amount',d.effect_amount,
          'otherPlayerId',d.other_player_id,'targetPosition',d.target_position,
          'note',d.result_note,'source',d.source_type,
          'drawnAt',d.drawn_at,'resolvedAt',d.resolved_at
         ) as payload
       from public.room_card_challenges d
       where d.room_id=v_room
       order by d.id desc limit 80
     ) c
   ),'[]'::jsonb),
   'totals',(
     select jsonb_build_object(
       'chaman',count(*) filter(where d.deck='chaman'),
       'tombola',count(*) filter(where d.deck='tombola'),
       'pending',count(*) filter(where d.outcome='pending'),
       'completed',count(*) filter(where d.outcome='completed'),
       'failed',count(*) filter(where d.outcome='failed'),
       'cancelled',count(*) filter(where d.outcome='cancelled')
     ) from public.room_card_challenges d where d.room_id=v_room
   )
 );
end;
$function$;
revoke all on function public.game_card_snapshot(text,text) from public;
grant execute on function public.game_card_snapshot(text,text) to anon,authenticated;

-- All settlements are atomic and only a validated host session can apply them.
-- card_title and instruction must be transcribed from the physical card.
create function public.game_card_action(p_code text,p_token text,p_action text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare
 v_room public.rooms%rowtype;v_me uuid;v_role text;
 v_id bigint;v_card public.room_card_challenges%rowtype;
 v_deck text;v_effect text;v_outcome text;v_title text;v_instruction text;v_note text;
 v_amount bigint;v_other uuid;v_position smallint;v_balance bigint;v_other_balance bigint;
 v_description text;
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'Datos inválidos';end if;
 select room_id,player_id,player_role into v_room.id,v_me,v_role from game_private.member(p_code,p_token);
 if v_me is null or v_role<>'host' then raise exception 'Solo el anfitrión administra las cartas';end if;
 select * into v_room from public.rooms where id=v_room.id for update;
 if v_room.status<>'active' then raise exception 'La partida no está activa';end if;

 if p_action='draw_manual' then
   if v_room.current_player_id is null then raise exception 'No hay jugador de turno';end if;
   if exists(select 1 from public.room_card_challenges where room_id=v_room.id and outcome='pending')
     then raise exception 'Primero resuelve la carta pendiente';end if;
   v_deck:=p_data->>'deck';
   if v_deck not in ('chaman','tombola') or v_deck is null then
     raise exception 'Selecciona El Chamán o La Tómbola';end if;
   select board_position into v_position from public.room_players where id=v_room.current_player_id;
   insert into public.room_card_challenges(room_id,player_id,turn_number,position,deck,source_type)
     values(v_room.id,v_room.current_player_id,v_room.turn_number,v_position,v_deck,'manual')
     returning id into v_id;
   insert into public.room_events(room_id,actor_id,event_type,payload)
     values(v_room.id,v_me,'card_drawn',
       jsonb_build_object('cardId',v_id,'deck',v_deck,'manual',true));
 elsif p_action in ('resolve','cancel') then
   v_id:=(p_data->>'id')::bigint;
   select * into v_card from public.room_card_challenges where id=v_id and room_id=v_room.id for update;
   if not found or v_card.outcome<>'pending' then
     raise exception 'La carta ya está resuelta o no existe';end if;
   if v_room.current_player_id is distinct from v_card.player_id then
     raise exception 'La carta debe resolverse en el turno del jugador';end if;
   v_note:=nullif(btrim(coalesce(p_data->>'note','')),'');
   if length(coalesce(v_note,''))>500 then raise exception 'Nota demasiado larga';end if;
   if p_action='cancel' then
     if length(coalesce(v_note,''))<2 then raise exception 'Explica por qué se anuló la carta';end if;
     update public.room_card_challenges set outcome='cancelled',
       result_note=v_note,resolved_at=now(),resolved_by=v_me where id=v_id;
   else
     v_title:=btrim(coalesce(p_data->>'title',''));
     v_instruction:=btrim(coalesce(p_data->>'instruction',''));
     v_outcome:=p_data->>'outcome';
     v_effect:=coalesce(p_data->>'effect','none');
     if length(v_title) not between 2 and 100 or length(v_instruction) not between 2 and 500
       then raise exception 'Registra el nombre y la instrucción real de la carta';end if;
     if v_outcome not in ('completed','failed') or v_outcome is null
       then raise exception 'Selecciona reto cumplido o no cumplido';end if;
     if v_effect not in ('none','bank_receive','bank_pay','pay_player','collect_player',
                          'move','jail','release_jail')
       then raise exception 'Efecto de carta desconocido';end if;
     v_amount:=nullif(p_data->>'amount','')::bigint;
     v_other:=nullif(p_data->>'otherPlayerId','')::uuid;
     v_position:=nullif(p_data->>'targetPosition','')::smallint;
     if v_effect in ('bank_receive','bank_pay','pay_player','collect_player') then
       if v_amount is null or v_amount not between 1 and 1000000000
         then raise exception 'Importe inválido de la carta';end if;
     else
       v_amount:=null;
     end if;
     if v_effect='move' and (v_position is null or v_position not between 0 and 39)
       then raise exception 'Selecciona una casilla destino entre 0 y 39';end if;
     if v_effect in ('pay_player','collect_player') then
       if v_other is null or v_other=v_card.player_id
         or not exists(select 1 from public.room_players
           where id=v_other and room_id=v_room.id and not bankrupt and participant_status<>'left')
         then raise exception 'El destinatario de la carta no es válido';end if;
     else
       v_other:=null;
     end if;
     -- Record completion and the bank operation in one transaction.
     if v_effect='bank_receive' then
       update public.room_players set balance=balance+v_amount where id=v_card.player_id;
       insert into public.room_ledger(room_id,to_player,amount,description,card_challenge_id)
         values(v_room.id,v_card.player_id,v_amount,'Carta '||v_card.deck||': '||v_title,v_id);
     elsif v_effect='bank_pay' then
       select balance into v_balance from public.room_players where id=v_card.player_id;
       if v_balance<v_amount then raise exception 'Saldo insuficiente: hipoteca antes de resolver la carta';end if;
       update public.room_players set balance=balance-v_amount where id=v_card.player_id;
       insert into public.room_ledger(room_id,from_player,amount,description,card_challenge_id)
         values(v_room.id,v_card.player_id,v_amount,'Carta '||v_card.deck||': '||v_title,v_id);
     elsif v_effect in ('pay_player','collect_player') then
       if v_effect='pay_player' then
         select balance into v_balance from public.room_players where id=v_card.player_id;
         if v_balance<v_amount then raise exception 'Saldo insuficiente para pagar la carta';end if;
         update public.room_players set balance=balance-v_amount where id=v_card.player_id;
         update public.room_players set balance=balance+v_amount where id=v_other;
         insert into public.room_ledger(room_id,from_player,to_player,amount,description,card_challenge_id)
           values(v_room.id,v_card.player_id,v_other,v_amount,'Carta '||v_card.deck||': '||v_title,v_id);
       else
         select balance into v_other_balance from public.room_players where id=v_other;
         if v_other_balance<v_amount then raise exception 'El otro jugador no tiene saldo suficiente';end if;
         update public.room_players set balance=balance-v_amount where id=v_other;
         update public.room_players set balance=balance+v_amount where id=v_card.player_id;
         insert into public.room_ledger(room_id,from_player,to_player,amount,description,card_challenge_id)
           values(v_room.id,v_other,v_card.player_id,v_amount,'Carta '||v_card.deck||': '||v_title,v_id);
       end if;
     elsif v_effect='move' then
       update public.room_players set board_position=v_position where id=v_card.player_id;
       -- Direct card moves require any GO bonus to be applied separately by the banker.
     elsif v_effect='jail' then
       update public.room_players set board_position=10,in_jail=true,jail_attempts=0
         where id=v_card.player_id;
       update public.rooms set last_roll_double=false,doubles_streak=0 where id=v_room.id;
     elsif v_effect='release_jail' then
       update public.room_players set in_jail=false,jail_attempts=0 where id=v_card.player_id;
     end if;
     update public.room_card_challenges set
       card_number=nullif(p_data->>'cardNumber','')::smallint,
       card_title=v_title,challenge_text=v_instruction,
       outcome=v_outcome,effect_kind=v_effect,effect_amount=v_amount,
       other_player_id=v_other,
       target_position=case when v_effect='move' then v_position else null end,
       result_note=v_note,resolved_at=now(),resolved_by=v_me
       where id=v_id;
     -- card_number is intentionally optional until cards can be identified.
   end if;
   insert into public.room_events(room_id,actor_id,event_type,payload)
     values(v_room.id,v_me,case when p_action='cancel' then 'card_cancelled' else 'card_resolved' end,
       jsonb_build_object('cardId',v_id,'deck',v_card.deck,'playerId',v_card.player_id,
                          'outcome',case when p_action='cancel' then 'cancelled' else v_outcome end,
                          'effect',case when p_action='cancel' then 'none' else v_effect end,
                          'amount',case when p_action='cancel' then null else v_amount end));
 else
   raise exception 'Operación de carta desconocida';
 end if;
 perform game_private.notify(v_room.id);
 return jsonb_build_object('ok',true,'cardId',v_id);
end;
$function$;
revoke all on function public.game_card_action(text,text,text,jsonb) from public;
grant execute on function public.game_card_action(text,text,text,jsonb) to anon,authenticated;
commit;
