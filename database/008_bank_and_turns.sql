-- Monopoly Perú | Version 008 | Turn engine and transactional bank operations
begin;
alter table public.rooms
 add column pending_amount bigint not null default 0 check(pending_amount>=0),
 add column pending_player_id uuid references public.room_players(id),
 add column pending_to_id uuid references public.room_players(id),
 add column pending_reason text,
 add column last_roll_total smallint not null default 0 check(last_roll_total between 0 and 12);
create index room_players_active_turn_idx on public.room_players(room_id,turn_order) where bankrupt=false and participant_status<>'left';

create or replace function public.game_snapshot(p_code text,p_token text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_room_id uuid; v_pid uuid; v_base jsonb; v_room public.rooms%rowtype;
begin
 select room_id,player_id into v_room_id,v_pid from game_private.member(p_code,p_token);
 if v_pid is null then raise exception 'Sesión inválida'; end if;
 v_base:=public.game_get_room(p_code,p_token);
 select * into v_room from public.rooms where id=v_room_id;
 return jsonb_set(v_base,'{room}',(v_base->'room')||jsonb_build_object(
 'pendingAmount',v_room.pending_amount,'pendingPlayerId',v_room.pending_player_id,
 'pendingToId',v_room.pending_to_id,'pendingReason',v_room.pending_reason,'lastRollTotal',v_room.last_roll_total));
end;$$;
revoke all on function public.game_snapshot(text,text) from public;
grant execute on function public.game_snapshot(text,text) to anon,authenticated;

create or replace function public.game_action(p_code text,p_token text,p_action text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_room public.rooms%rowtype; v_me uuid; v_role text; v_p public.room_players%rowtype;
 v_target uuid; v_target_p public.room_players%rowtype;
 v_amount bigint; v_due bigint; v_position smallint; v_new_position smallint;
 v_die1 smallint; v_die2 smallint; v_total int; v_double boolean; v_streak int;
 v_space public.room_spaces%rowtype; v_rent bigint; v_owned int; v_group_total int;
 v_next uuid; v_advance boolean:=false; v_roll_saved boolean:=false; v_balance bigint;
 v_status text;
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'Datos de acción inválidos'; end if;
 select room_id,player_id,player_role into v_room.id,v_me,v_role from game_private.member(p_code,p_token);
 if v_me is null then raise exception 'Sesión inválida o expirada'; end if;
 select * into v_room from public.rooms where id=v_room.id for update;
 if v_room.status<>'active' then raise exception 'La partida no está activa'; end if;
 select * into v_p from public.room_players where id=v_me for update;
 if v_p.bankrupt then raise exception 'El jugador está en bancarrota'; end if;

 if p_action='roll' then
   if v_room.current_player_id<>v_me then raise exception 'No es tu turno'; end if;
   if v_room.turn_rolled then raise exception 'Ya lanzaste los dados en este turno'; end if;
   if v_room.pending_amount>0 then raise exception 'Primero salda el pago pendiente'; end if;
   if v_room.dice_mode='physical' then
     v_die1:=(p_data->>'d1')::smallint;
     v_die2:=(p_data->>'d2')::smallint;
     if v_die1 not between 1 and 6 or v_die2 not between 1 and 6 then raise exception 'Cada dado debe estar entre 1 y 6'; end if;
   else
     v_die1:=1+(get_byte(extensions.gen_random_bytes(1),0)%6);
     v_die2:=1+(get_byte(extensions.gen_random_bytes(1),0)%6);
   end if;
   v_total:=v_die1+v_die2;
   v_double:=(v_die1=v_die2);
   v_streak:=case when v_double then v_room.doubles_streak+1 else 0 end;
   v_position:=v_p.board_position;
   v_new_position:=v_position;
   if v_streak>=3 then
     v_new_position:=10;
     update public.room_players set board_position=10,in_jail=true,jail_attempts=0 where id=v_me;
     update public.rooms set doubles_streak=0,last_roll_double=false,turn_rolled=true,last_roll_total=v_total where id=v_room.id;
   elsif v_p.in_jail and not v_double and v_p.jail_attempts<2 then
     update public.room_players set jail_attempts=jail_attempts+1 where id=v_me;
     update public.rooms set doubles_streak=0,last_roll_double=false,turn_rolled=true,last_roll_total=v_total where id=v_room.id;
   else
     if v_p.in_jail then
       if not v_double then
         if v_p.balance<v_room.bail_amount then raise exception 'No tienes saldo para pagar la fianza; hipoteca antes de lanzar'; end if;
         update public.room_players set balance=balance-v_room.bail_amount where id=v_me;
         if v_room.bail_amount>0 then
           insert into public.room_ledger(room_id,from_player,amount,description)
             values(v_room.id,v_me,v_room.bail_amount,'Fianza de cárcel');
         end if;
       end if;
       update public.room_players set in_jail=false,jail_attempts=0 where id=v_me;
     end if;
     v_new_position:=((v_position::int+v_total)%40)::smallint;
     if v_position+v_total>=40 then
       update public.room_players set balance=balance+v_room.go_bonus where id=v_me;
       if v_room.go_bonus>0 then
         insert into public.room_ledger(room_id,to_player,amount,description)
           values(v_room.id,v_me,v_room.go_bonus,'Paso por Salida');
       end if;
     end if;
     if v_new_position=30 then
       v_new_position:=10;
       update public.room_players set board_position=10,in_jail=true,jail_attempts=0 where id=v_me;
       v_double:=false;v_streak:=0;
     else
       update public.room_players set board_position=v_new_position where id=v_me;
       select * into v_space from public.room_spaces where room_id=v_room.id and position=v_new_position;
       if v_space.space_type in ('property','railroad','utility') and
          v_space.owner_id is not null and v_space.owner_id<>v_me and not v_space.mortgaged then
         v_rent:=coalesce(v_space.rent_schedule[least(v_space.building_level+1,6)],0);
         if v_space.space_type='railroad' then
           select count(*) into v_owned from public.room_spaces
             where room_id=v_room.id and owner_id=v_space.owner_id and space_type='railroad';
           v_rent:=coalesce(v_space.rent_schedule[least(v_owned,6)],v_rent);
         elsif v_space.space_type='utility' then
           select count(*) into v_owned from public.room_spaces
             where room_id=v_room.id and owner_id=v_space.owner_id and space_type='utility';
           v_rent:=v_total*(case when v_owned=2 then 10 else 4 end);
         elsif v_space.building_level=0 and v_space.color_group is not null then
           select count(*),count(*) filter(where owner_id=v_space.owner_id) into v_group_total,v_owned
             from public.room_spaces where room_id=v_room.id and color_group=v_space.color_group
               and space_type='property';
           if v_group_total>1 and v_owned=v_group_total then v_rent:=v_rent*2;end if;
         end if;
         if v_rent>0 then
           update public.rooms set pending_amount=v_rent,pending_player_id=v_me,
              pending_to_id=v_space.owner_id,pending_reason='Alquiler: '||v_space.name where id=v_room.id;
         end if;
       elsif v_space.space_type='tax' and coalesce(v_space.price,0)>0 then
         update public.rooms set pending_amount=v_space.price,pending_player_id=v_me,
           pending_to_id=null,pending_reason='Impuesto: '||v_space.name where id=v_room.id;
       end if;
     end if;
     update public.rooms set doubles_streak=v_streak,last_roll_double=v_double,
       turn_rolled=true,last_roll_total=v_total where id=v_room.id;
   end if;
   insert into public.room_rolls(room_id,player_id,turn_number,die_1,die_2,mode,from_position,to_position)
     values(v_room.id,v_me,v_room.turn_number,v_die1,v_die2,v_room.dice_mode,v_position,v_new_position);
   insert into public.room_events(room_id,actor_id,event_type,payload)
     values(v_room.id,v_me,'roll',jsonb_build_object('d1',v_die1,'d2',v_die2,'from',v_position,'to',v_new_position,'double',v_double,'tripleJail',v_streak>=3));
 elsif p_action='pay_due' then
   if v_room.current_player_id<>v_me or v_room.pending_player_id<>v_me or v_room.pending_amount=0 then
     raise exception 'No tienes pagos pendientes';end if;
   if v_p.balance<v_room.pending_amount then raise exception 'Saldo insuficiente: hipoteca o negocia antes de pagar';end if;
   update public.room_players set balance=balance-v_room.pending_amount where id=v_me;
   if v_room.pending_to_id is not null then
     update public.room_players set balance=balance+v_room.pending_amount where id=v_room.pending_to_id;
   end if;
   insert into public.room_ledger(room_id,from_player,to_player,amount,description)
     values(v_room.id,v_me,v_room.pending_to_id,v_room.pending_amount,coalesce(v_room.pending_reason,'Pago pendiente'));
   insert into public.room_events(room_id,actor_id,event_type,payload)
     values(v_room.id,v_me,'payment',jsonb_build_object('amount',v_room.pending_amount,'to',v_room.pending_to_id));
   update public.rooms set pending_amount=0,pending_player_id=null,pending_to_id=null,pending_reason=null where id=v_room.id;
 elsif p_action='transfer' then
   v_target:=nullif(p_data->>'to','')::uuid;
   v_amount:=(p_data->>'amount')::bigint;
   if v_target is null or v_target=v_me then raise exception 'Selecciona otro jugador';end if;
   if v_amount is null or v_amount<=0 or v_amount>1000000000 then raise exception 'Importe inválido';end if;
   if v_p.balance<v_amount then raise exception 'Saldo insuficiente';end if;
   if v_room.pending_player_id=v_me then raise exception 'Primero resuelve tu deuda';end if;
   select * into v_target_p from public.room_players where id=v_target and room_id=v_room.id and not bankrupt;
   if not found then raise exception 'Destinatario inválido';end if;
   update public.room_players set balance=balance-v_amount where id=v_me;
   update public.room_players set balance=balance+v_amount where id=v_target;
   insert into public.room_ledger(room_id,from_player,to_player,amount,description)
     values(v_room.id,v_me,v_target,v_amount,'Transferencia entre jugadores');
   insert into public.room_events(room_id,actor_id,event_type,payload)
     values(v_room.id,v_me,'transfer',jsonb_build_object('amount',v_amount,'to',v_target));
 elsif p_action='bank' then
   if v_role<>'host' then raise exception 'Solo el anfitrión controla el banco';end if;
   v_target:=(p_data->>'playerId')::uuid;
   v_amount:=(p_data->>'amount')::bigint;
   if v_amount is null or v_amount=0 or abs(v_amount)>1000000000 then raise exception 'Importe inválido';end if;
   if char_length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'Indica un motivo (mínimo 3 caracteres)';end if;
   select * into v_target_p from public.room_players where id=v_target and room_id=v_room.id and not bankrupt for update;
   if not found then raise exception 'Jugador inválido';end if;
   if v_target_p.balance+v_amount<0 then raise exception 'Saldo insuficiente';end if;
   update public.room_players set balance=balance+v_amount where id=v_target;
   insert into public.room_ledger(room_id,from_player,to_player,amount,description)
     values(v_room.id,case when v_amount<0 then v_target else null end,
       case when v_amount>0 then v_target else null end,abs(v_amount),btrim(p_data->>'reason'));
   insert into public.room_events(room_id,actor_id,event_type,payload)
     values(v_room.id,v_me,'bank',jsonb_build_object('playerId',v_target,'amount',v_amount,'reason',p_data->>'reason'));
 elsif p_action='move' then
   if v_role<>'host' then raise exception 'Solo el anfitrión puede mover una ficha manualmente';end if;
   v_target:=(p_data->>'playerId')::uuid;
   v_new_position:=(p_data->>'position')::smallint;
   if v_new_position not between 0 and 39 then raise exception 'Posición inválida';end if;
   if not exists(select 1 from public.room_players where room_id=v_room.id and id=v_target and not bankrupt) then raise exception 'Jugador inválido';end if;
   update public.room_players set board_position=v_new_position,
     in_jail=case when coalesce((p_data->>'jail')::boolean,false) then true else in_jail end
     where id=v_target;
   insert into public.room_events(room_id,actor_id,event_type,payload)
     values(v_room.id,v_me,'move',jsonb_build_object('playerId',v_target,'position',v_new_position));
 elsif p_action='bail' then
   if not v_p.in_jail then raise exception 'No estás en la cárcel';end if;
   if v_p.balance<v_room.bail_amount then raise exception 'Saldo insuficiente para la fianza';end if;
   update public.room_players set balance=balance-v_room.bail_amount,in_jail=false,jail_attempts=0 where id=v_me;
   if v_room.bail_amount>0 then
     insert into public.room_ledger(room_id,from_player,amount,description)
       values(v_room.id,v_me,v_room.bail_amount,'Fianza de cárcel');
   end if;
   insert into public.room_events(room_id,actor_id,event_type,payload) values(v_room.id,v_me,'bail','{}');
 elsif p_action='end_turn' then
   if v_room.current_player_id<>v_me then raise exception 'No es tu turno';end if;
   if not v_room.turn_rolled then raise exception 'Primero lanza los dados';end if;
   if v_room.pending_amount>0 then raise exception 'Debes saldar el pago pendiente';end if;
   if v_room.last_roll_double and v_room.doubles_streak>0 and not v_p.in_jail then
     update public.rooms set turn_rolled=false,last_roll_double=false,last_roll_total=0 where id=v_room.id;
     insert into public.room_events(room_id,actor_id,event_type,payload)
       values(v_room.id,v_me,'extra_roll','{}');
   else
     select id into v_next from public.room_players
       where room_id=v_room.id and not bankrupt and participant_status<>'left'
       and turn_order>v_p.turn_order order by turn_order limit 1;
     if v_next is null then
       select id into v_next from public.room_players
         where room_id=v_room.id and not bankrupt and participant_status<>'left'
         order by turn_order limit 1;
     end if;
     if v_next is null then raise exception 'No hay jugadores activos';end if;
     update public.rooms set current_player_id=v_next,turn_number=turn_number+1,turn_rolled=false,
       last_roll_double=false,doubles_streak=0,last_roll_total=0 where id=v_room.id;
     insert into public.room_events(room_id,actor_id,event_type,payload)
       values(v_room.id,v_me,'end_turn',jsonb_build_object('nextPlayerId',v_next));
   end if;
 elsif p_action='bankrupt' then
   if v_role<>'host' and v_me<>v_room.current_player_id then raise exception 'Acción no autorizada';end if;
   v_target:=coalesce(nullif(p_data->>'playerId','')::uuid,v_me);
   select * into v_target_p from public.room_players where id=v_target and room_id=v_room.id and not bankrupt for update;
   if not found then raise exception 'Jugador inválido';end if;
   if v_role<>'host' and v_target<>v_me then raise exception 'Acción no autorizada';end if;
   if v_room.pending_player_id=v_target and v_room.pending_to_id is not null then
     update public.room_spaces set owner_id=v_room.pending_to_id,building_level=0,mortgaged=false
       where room_id=v_room.id and owner_id=v_target;
     update public.room_players set balance=balance+v_target_p.balance where id=v_room.pending_to_id;
   else
     update public.room_spaces set owner_id=null,building_level=0,mortgaged=false where room_id=v_room.id and owner_id=v_target;
   end if;
   update public.room_players set bankrupt=true,balance=0 where id=v_target;
   update public.room_trades set status='cancelled',resolved_at=now()
     where room_id=v_room.id and status='pending' and (from_player=v_target or to_player=v_target);
   if v_room.pending_player_id=v_target then
     update public.rooms set pending_amount=0,pending_player_id=null,pending_to_id=null,pending_reason=null where id=v_room.id;
   end if;
   if v_room.current_player_id=v_target then
     select id into v_next from public.room_players where room_id=v_room.id and not bankrupt and participant_status<>'left'
       order by case when turn_order>v_target_p.turn_order then 0 else 1 end,turn_order limit 1;
     update public.rooms set current_player_id=v_next,turn_rolled=false,doubles_streak=0,
       last_roll_double=false,turn_number=turn_number+1 where id=v_room.id;
   end if;
   insert into public.room_events(room_id,actor_id,event_type,payload)
     values(v_room.id,v_me,'bankrupt',jsonb_build_object('playerId',v_target));
   select count(*) into v_owned from public.room_players where room_id=v_room.id and not bankrupt and participant_status<>'left';
   if v_owned<=1 then
     update public.rooms set status='finished',finished_at=now(),host_credential_revoked_at=now() where id=v_room.id;
   end if;
 else
   raise exception 'Acción desconocida';
 end if;
 perform game_private.notify(v_room.id);
 return jsonb_build_object('ok',true);
end;$$;
revoke all on function public.game_action(text,text,text,jsonb) from public;
grant execute on function public.game_action(text,text,text,jsonb) to anon,authenticated;
commit;