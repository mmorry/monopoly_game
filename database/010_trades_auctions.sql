-- Monopoly Perú | Version 010 | Atomic trades and auctions
begin;
create or replace function public.game_trade(p_code text,p_token text,p_action text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_room uuid;v_me uuid;v_role text;v_status text;v_to uuid;v_trade public.room_trades%rowtype;
 v_trade_id uuid;v_give_cash bigint;v_take_cash bigint;v_give smallint[];v_take smallint[];
 v_from_balance bigint;v_to_balance bigint;v_count int;v_expected int;
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'Oferta inválida';end if;
 select room_id,player_id,player_role into v_room,v_me,v_role from game_private.member(p_code,p_token);
 if v_me is null then raise exception 'Sesión inválida';end if;
 select status into v_status from public.rooms where id=v_room for update;
 if v_status<>'active' then raise exception 'Partida no activa';end if;
 if exists(select 1 from public.room_players where id=v_me and bankrupt) then raise exception 'Jugador en bancarrota';end if;
 if p_action='offer' then
   v_to:=(p_data->>'to')::uuid;
   if v_to=v_me or not exists(select 1 from public.room_players where room_id=v_room and id=v_to and not bankrupt)
     then raise exception 'Destinatario inválido';end if;
   v_give_cash:=coalesce((p_data->>'giveCash')::bigint,0);
   v_take_cash:=coalesce((p_data->>'takeCash')::bigint,0);
   if v_give_cash not between 0 and 1000000000 or v_take_cash not between 0 and 1000000000 then raise exception 'Importe inválido';end if;
   select coalesce(array_agg(x::smallint),'{}'::smallint[]) into v_give
     from jsonb_array_elements_text(coalesce(p_data->'giveSpaces','[]'::jsonb)) as x;
   select coalesce(array_agg(x::smallint),'{}'::smallint[]) into v_take
     from jsonb_array_elements_text(coalesce(p_data->'takeSpaces','[]'::jsonb)) as x;
   if cardinality(v_give)>28 or cardinality(v_take)>28 then raise exception 'Demasiadas propiedades';end if;
   if cardinality(v_give)+cardinality(v_take)=0 and v_give_cash=0 and v_take_cash=0 then raise exception 'Oferta vacía';end if;
   if (select count(distinct x) from unnest(v_give) x)<>cardinality(v_give)
     or (select count(distinct x) from unnest(v_take) x)<>cardinality(v_take) then raise exception 'Propiedades repetidas';end if;
   select count(*) into v_count from public.room_spaces
     where room_id=v_room and position=any(v_give) and owner_id=v_me and building_level=0;
   if v_count<>cardinality(v_give) then raise exception 'No puedes ofrecer una propiedad ajena o construida';end if;
   select count(*) into v_count from public.room_spaces
     where room_id=v_room and position=any(v_take) and owner_id=v_to and building_level=0;
   if v_count<>cardinality(v_take) then raise exception 'La propiedad solicitada no está disponible';end if;
   select balance into v_from_balance from public.room_players where id=v_me;
   if v_from_balance<v_give_cash then raise exception 'No tienes el efectivo ofrecido';end if;
   insert into public.room_trades(room_id,from_player,to_player,offered_cash,requested_cash,offered_positions,requested_positions)
     values(v_room,v_me,v_to,v_give_cash,v_take_cash,v_give,v_take) returning id into v_trade_id;
   insert into public.room_events(room_id,actor_id,event_type,payload)
     values(v_room,v_me,'trade_offered',jsonb_build_object('id',v_trade_id,'to',v_to));
 elsif p_action in ('accept','reject','cancel') then
   v_trade_id:=(p_data->>'id')::uuid;
   select * into v_trade from public.room_trades where room_id=v_room and id=v_trade_id for update;
   if not found or v_trade.status<>'pending' then raise exception 'Oferta no disponible';end if;
   if p_action='accept' and v_trade.to_player<>v_me then raise exception 'Solo el destinatario puede aceptar';end if;
   if p_action='reject' and v_trade.to_player<>v_me then raise exception 'Solo el destinatario puede rechazar';end if;
   if p_action='cancel' and v_trade.from_player<>v_me then raise exception 'Solo el remitente puede cancelar';end if;
   if p_action='accept' then
     if exists(select 1 from public.room_players where id in (v_trade.from_player,v_trade.to_player) and bankrupt)
       then raise exception 'Uno de los jugadores está en bancarrota';end if;
     select balance into v_from_balance from public.room_players where id=v_trade.from_player for update;
     select balance into v_to_balance from public.room_players where id=v_trade.to_player for update;
     if v_from_balance<v_trade.offered_cash or v_to_balance<v_trade.requested_cash then
       raise exception 'Uno de los jugadores ya no tiene saldo suficiente';end if;
     select count(*) into v_count from public.room_spaces
       where room_id=v_room and position=any(v_trade.offered_positions)
         and owner_id=v_trade.from_player and building_level=0;
     if v_count<>cardinality(v_trade.offered_positions) then raise exception 'Una propiedad ofrecida cambió de dueño o tiene construcciones';end if;
     select count(*) into v_count from public.room_spaces
       where room_id=v_room and position=any(v_trade.requested_positions)
         and owner_id=v_trade.to_player and building_level=0;
     if v_count<>cardinality(v_trade.requested_positions) then raise exception 'Una propiedad solicitada ya no está disponible';end if;
     update public.room_players set balance=balance-v_trade.offered_cash+v_trade.requested_cash where id=v_trade.from_player;
     update public.room_players set balance=balance+v_trade.offered_cash-v_trade.requested_cash where id=v_trade.to_player;
     update public.room_spaces set owner_id=v_trade.to_player where room_id=v_room and position=any(v_trade.offered_positions);
     update public.room_spaces set owner_id=v_trade.from_player where room_id=v_room and position=any(v_trade.requested_positions);
     if v_trade.offered_cash>0 then
       insert into public.room_ledger(room_id,from_player,to_player,amount,description)
         values(v_room,v_trade.from_player,v_trade.to_player,v_trade.offered_cash,'Intercambio');
     end if;
     if v_trade.requested_cash>0 then
       insert into public.room_ledger(room_id,from_player,to_player,amount,description)
         values(v_room,v_trade.to_player,v_trade.from_player,v_trade.requested_cash,'Intercambio');
     end if;
   end if;
   update public.room_trades set status=case p_action when 'accept' then 'accepted'
     when 'reject' then 'rejected' else 'cancelled' end,resolved_at=now() where id=v_trade.id;
   insert into public.room_events(room_id,actor_id,event_type,payload)
     values(v_room,v_me,'trade_'||p_action,jsonb_build_object('id',v_trade.id));
 else
   raise exception 'Acción de intercambio inválida';
 end if;
 perform game_private.notify(v_room);
 return jsonb_build_object('ok',true,'id',v_trade_id);
end;$$;
revoke all on function public.game_trade(text,text,text,jsonb) from public;
grant execute on function public.game_trade(text,text,text,jsonb) to anon,authenticated;

create or replace function public.game_auction(p_code text,p_token text,p_action text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_room uuid; v_me uuid;v_role text;v_status text;v_id uuid;v_position smallint;
 v_a public.room_auctions%rowtype;v_bid bigint;v_high bigint;v_winner uuid;
 v_balance bigint;v_space public.room_spaces%rowtype;
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'Datos inválidos';end if;
 select room_id,player_id,player_role into v_room,v_me,v_role from game_private.member(p_code,p_token);
 if v_me is null then raise exception 'Sesión inválida';end if;
 select status into v_status from public.rooms where id=v_room for update;
 if v_status<>'active' then raise exception 'Partida no activa';end if;
 if p_action='start' then
   if v_role<>'host' then raise exception 'Solo el anfitrión abre subastas';end if;
   v_position:=(p_data->>'position')::smallint;
   select * into v_space from public.room_spaces where room_id=v_room and position=v_position;
   if not found or v_space.space_type not in ('property','railroad','utility') or v_space.owner_id is not null
     then raise exception 'Esta propiedad no puede subastarse';end if;
   if v_space.price is null or v_space.price<=0 then raise exception 'Primero configura el precio de esta propiedad';end if;
   v_bid:=coalesce((p_data->>'minimum')::bigint,1);
   if v_bid<1 then raise exception 'Puja mínima inválida';end if;
   insert into public.room_auctions(room_id,position,minimum_bid)
     values(v_room,v_position,v_bid) returning id into v_id;
   insert into public.room_events(room_id,actor_id,event_type,payload)
     values(v_room,v_me,'auction_started',jsonb_build_object('id',v_id,'position',v_position));
 else
   v_id:=(p_data->>'id')::uuid;
   select * into v_a from public.room_auctions where id=v_id and room_id=v_room for update;
   if not found or v_a.status<>'open' then raise exception 'Subasta no disponible';end if;
   if p_action='bid' then
     if exists(select 1 from public.room_players where id=v_me and bankrupt) then raise exception 'No puedes pujar en bancarrota';end if;
     v_bid:=(p_data->>'amount')::bigint;
     select coalesce(max(amount),0) into v_high from public.room_bids where auction_id=v_id;
     select balance into v_balance from public.room_players where id=v_me;
     if v_bid is null or v_bid<v_a.minimum_bid or v_bid<=v_high or v_bid>v_balance
       then raise exception 'La puja debe superar la mayor oferta y estar cubierta por tu saldo';end if;
     insert into public.room_bids(auction_id,bidder_id,amount) values(v_id,v_me,v_bid);
     insert into public.room_events(room_id,actor_id,event_type,payload)
       values(v_room,v_me,'auction_bid',jsonb_build_object('id',v_id,'amount',v_bid));
   elsif p_action='close' then
     if v_role<>'host' then raise exception 'Solo el anfitrión cierra subastas';end if;
     select bidder_id,amount into v_winner,v_bid from public.room_bids
       where auction_id=v_id order by amount desc,id asc limit 1;
     if v_winner is null then raise exception 'No hay ofertas: cancela la subasta';end if;
     select balance into v_balance from public.room_players where id=v_winner and not bankrupt for update;
     if v_balance is null or v_balance<v_bid then raise exception 'El ganador ya no dispone de fondos suficientes';end if;
     update public.room_players set balance=balance-v_bid where id=v_winner;
     update public.room_spaces set owner_id=v_winner where room_id=v_room and position=v_a.position and owner_id is null;
     if not found then raise exception 'La propiedad ya fue adquirida';end if;
     update public.room_auctions set status='closed',winner_id=v_winner,winning_bid=v_bid,finished_at=now() where id=v_id;
     insert into public.room_ledger(room_id,from_player,amount,description)
       values(v_room,v_winner,v_bid,'Subasta de casilla '||v_a.position);
     insert into public.room_events(room_id,actor_id,event_type,payload)
       values(v_room,v_me,'auction_closed',jsonb_build_object('id',v_id,'winner',v_winner,'amount',v_bid));
   elsif p_action='cancel' then
     if v_role<>'host' then raise exception 'Solo el anfitrión cancela subastas';end if;
     update public.room_auctions set status='cancelled',finished_at=now() where id=v_id;
     insert into public.room_events(room_id,actor_id,event_type,payload)
       values(v_room,v_me,'auction_cancelled',jsonb_build_object('id',v_id));
   else
     raise exception 'Acción de subasta inválida';
   end if;
 end if;
 perform game_private.notify(v_room);
 return jsonb_build_object('ok',true,'id',v_id);
end;$$;
revoke all on function public.game_auction(text,text,text,jsonb) from public;
grant execute on function public.game_auction(text,text,text,jsonb) to anon,authenticated;
commit;