-- 018 F3182 configurable decks, ordered virtual draws and mandatory auctions.
BEGIN;
ALTER TABLE public.rooms
 ADD COLUMN card_mode text NOT NULL DEFAULT 'physical'
 CHECK(card_mode IN ('physical','virtual'));

CREATE FUNCTION public.game_card_mode(p_code text,p_token text,p_mode text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $body$
DECLARE rid uuid; pid uuid; ro text;
BEGIN
 SELECT room_id,player_id,player_role INTO rid,pid,ro FROM game_private.member(p_code,p_token);
 IF pid IS NULL OR ro<>'host' THEN RAISE EXCEPTION 'Solo el anfitrión configura las cartas';END IF;
 IF p_mode NOT IN ('physical','virtual') OR p_mode IS NULL THEN RAISE EXCEPTION 'Modo de cartas inválido';END IF;
 PERFORM 1 FROM public.rooms WHERE id=rid AND status='waiting' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'El modo de cartas no se cambia durante la partida';END IF;
 UPDATE public.rooms SET card_mode=p_mode WHERE id=rid;
 PERFORM game_private.notify(rid);
 RETURN jsonb_build_object('ok',true,'cardMode',p_mode);
END;$body$;
REVOKE ALL ON FUNCTION public.game_card_mode(text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.game_card_mode(text,text,text) TO anon,authenticated;

-- Virtual cards are assigned on the server, one per draw without repeating
-- until the deck's 16 entries have been cycled. Distinct decks rotate independently.
CREATE FUNCTION game_private.assign_virtual_f3182_card()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $body$
DECLARE v_mode text;v_number smallint;v_card public.monopoly_f3182_cards%rowtype;
BEGIN
 SELECT card_mode INTO v_mode FROM public.rooms WHERE id=NEW.room_id;
 IF v_mode<>'virtual' THEN RETURN NEW;END IF;
 SELECT ((count(*)-1)%16+1)::smallint INTO v_number
 FROM public.room_card_challenges WHERE room_id=NEW.room_id AND deck=NEW.deck;
 SELECT * INTO v_card FROM public.monopoly_f3182_cards
 WHERE edition_sku='F3182' AND deck=NEW.deck AND catalog_number=v_number;
 IF NOT FOUND THEN RAISE EXCEPTION 'No se encontró la carta F3182 número %',v_number;END IF;
 UPDATE public.room_card_challenges
  SET card_number=v_number,card_title=v_card.title,challenge_text=v_card.instruction
 WHERE id=NEW.id;
 RETURN NEW;
END;$body$;
REVOKE ALL ON FUNCTION game_private.assign_virtual_f3182_card() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER room_cards_virtual_assign
 AFTER INSERT ON public.room_card_challenges FOR EACH ROW
 EXECUTE FUNCTION game_private.assign_virtual_f3182_card();

CREATE FUNCTION public.game_decline_property(p_code text,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $body$
DECLARE r public.rooms%rowtype; pid uuid; ro text; p public.room_players%rowtype;
 s public.room_spaces%rowtype; a uuid;
BEGIN
 SELECT room_id,player_id,player_role INTO r.id,pid,ro FROM game_private.member(p_code,p_token);
 IF pid IS NULL THEN RAISE EXCEPTION 'Sesión inválida';END IF;
 SELECT * INTO r FROM public.rooms WHERE id=r.id FOR UPDATE;
 IF r.status<>'active' OR r.current_player_id IS DISTINCT FROM pid OR NOT r.turn_rolled
 THEN RAISE EXCEPTION 'No hay propiedad del turno que puedas rechazar';END IF;
 IF r.pending_amount>0 THEN RAISE EXCEPTION 'Primero paga tu deuda';END IF;
 SELECT * INTO p FROM public.room_players WHERE id=pid;
 IF p.bankrupt OR p.in_jail THEN RAISE EXCEPTION 'No puedes rechazar desde la cárcel o en bancarrota';END IF;
 SELECT * INTO s FROM public.room_spaces WHERE room_id=r.id AND position=p.board_position FOR UPDATE;
 IF s.space_type NOT IN ('property','railroad','utility') OR s.owner_id IS NOT NULL OR coalesce(s.price,0)<=0
 THEN RAISE EXCEPTION 'No existe propiedad disponible en tu casilla';END IF;
 IF EXISTS(SELECT 1 FROM public.room_auctions
           WHERE room_id=r.id AND position=s.position AND status='open')
 THEN RAISE EXCEPTION 'La propiedad ya está en subasta';END IF;
 INSERT INTO public.room_auctions(room_id,position,minimum_bid)
 VALUES(r.id,s.position,10) RETURNING id INTO a;
 INSERT INTO public.room_events(room_id,actor_id,event_type,payload)
 VALUES(r.id,pid,'property_declined',
   jsonb_build_object('position',s.position,'auctionId',a,'minimum',10));
 PERFORM game_private.notify(r.id);
 RETURN jsonb_build_object('ok',true,'auctionId',a,'minimum',10);
END;$body$;
REVOKE ALL ON FUNCTION public.game_decline_property(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.game_decline_property(text,text) TO anon,authenticated;

-- Patch the existing functions without changing the previously committed SQL scripts.
DO $patch$
DECLARE src text;
BEGIN
 src:=pg_get_functiondef('public.game_get_room(text,text)'::regprocedure);
 IF position('''diceMode'',v_room.dice_mode,' IN src)=0 THEN
  RAISE EXCEPTION 'Unexpected game_get_room';END IF;
 EXECUTE replace(src,'''diceMode'',v_room.dice_mode,',
 '''diceMode'',v_room.dice_mode,''cardMode'',v_room.card_mode,');

 src:=pg_get_functiondef('public.game_action(text,text,text,jsonb)'::regprocedure);
 IF position('if v_room.pending_amount>0 then raise exception ''Debes saldar el pago pendiente'';end if;' IN src)=0 THEN
  RAISE EXCEPTION 'Unexpected game_action end turn guard';END IF;
 src:=replace(src,
 'if v_room.pending_amount>0 then raise exception ''Debes saldar el pago pendiente'';end if;',
 'if v_room.pending_amount>0 then raise exception ''Debes saldar el pago pendiente'';end if;
   if exists (select 1 from public.room_auctions a where a.room_id=v_room.id
     and a.status=''open'') then
     raise exception ''Hay una subasta abierta: primero ciérrala o cancélala'';
   end if;
   if exists (select 1 from public.room_spaces s where s.room_id=v_room.id
     and s.position=v_p.board_position
     and s.owner_id is null and s.space_type in (''property'',''railroad'',''utility'')
     and coalesce(s.price,0)>0)
     and not v_p.in_jail
     and exists(select 1 from public.room_rolls d where d.room_id=v_room.id
       and d.player_id=v_me and d.turn_number=v_room.turn_number
       and d.to_position=v_p.board_position)
     and not exists(select 1 from public.room_auctions a where a.room_id=v_room.id
       and a.position=v_p.board_position and a.status in (''closed'',''cancelled'')
       and a.created_at >= (select min(d.created_at) from public.room_rolls d
         where d.room_id=v_room.id and d.player_id=v_me
         and d.turn_number=v_room.turn_number and d.to_position=v_p.board_position))
   then
     raise exception ''Compra la propiedad o recházala para subastarla'';
   end if;');
 EXECUTE src;
 src:=pg_get_functiondef('public.game_auction(text,text,text,jsonb)'::regprocedure);
 IF position('coalesce((p_data->>''minimum'')::bigint,1)' IN src)=0 THEN
    RAISE EXCEPTION 'Unexpected game_auction default bid';END IF;
 src:=replace(src,'coalesce((p_data->>''minimum'')::bigint,1)',
                   'coalesce((p_data->>''minimum'')::bigint,10)');
 EXECUTE src;
 src:=pg_get_functiondef('public.game_property(text,text,text,smallint)'::regprocedure);
 IF position('if v_s.owner_id is not null then raise exception ''La propiedad ya tiene dueño'';end if;' IN src)=0 THEN
   RAISE EXCEPTION 'Unexpected game_property buy';END IF;
 src:=replace(src,
 'if v_s.owner_id is not null then raise exception ''La propiedad ya tiene dueño'';end if;',
 'if v_s.owner_id is not null then raise exception ''La propiedad ya tiene dueño'';end if;
   if exists (select 1 from public.room_auctions
     where room_id=v_room.id and position=p_position and status=''open'') then
     raise exception ''La propiedad está en subasta'';end if;');
 EXECUTE src;
END $patch$;
COMMIT;