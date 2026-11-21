-- 019 | F3182 server-randomized virtual decks, atomic card execution and retained jail passes
-- Versioned file. Executed once against the juegos/monopoly_game project.
BEGIN;
CREATE TABLE public.room_virtual_decks (
 room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
 deck text NOT NULL CHECK(deck IN ('chaman','tombola')),
 remaining smallint[] NOT NULL DEFAULT '{}'::smallint[],
 PRIMARY KEY(room_id,deck)
);
ALTER TABLE public.room_virtual_decks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.room_virtual_decks FROM PUBLIC,anon,authenticated;

CREATE TABLE public.room_held_jail_cards (
 room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
 player_id uuid NOT NULL REFERENCES public.room_players(id) ON DELETE CASCADE,
 deck text NOT NULL CHECK(deck IN ('chaman','tombola')),
 card_number smallint NOT NULL CHECK(card_number BETWEEN 1 AND 16),
 held_since timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(room_id,deck,card_number)
);
CREATE INDEX room_held_jail_cards_player_idx ON public.room_held_jail_cards(room_id,player_id);
ALTER TABLE public.room_held_jail_cards ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.room_held_jail_cards FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION game_private.assign_virtual_f3182_card()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $body$
DECLARE v_mode text; v_remaining smallint[]; v_num smallint; v_idx int;
 v_card public.monopoly_f3182_cards%rowtype;
BEGIN
 SELECT card_mode INTO v_mode FROM public.rooms WHERE id=NEW.room_id;
 IF v_mode<>'virtual' THEN RETURN NEW; END IF;
 INSERT INTO public.room_virtual_decks(room_id,deck) VALUES(NEW.room_id,NEW.deck)
  ON CONFLICT DO NOTHING;
 SELECT remaining INTO v_remaining FROM public.room_virtual_decks
  WHERE room_id=NEW.room_id AND deck=NEW.deck FOR UPDATE;
 IF coalesce(cardinality(v_remaining),0)=0 THEN
  SELECT coalesce(array_agg(n ORDER BY n),'{}'::smallint[])
  INTO v_remaining FROM generate_series(1,16) n
  WHERE NOT EXISTS(
   SELECT 1 FROM public.room_held_jail_cards h
   WHERE h.room_id=NEW.room_id AND h.deck=NEW.deck AND h.card_number=n);
 END IF;
 IF cardinality(v_remaining)=0 THEN
  RAISE EXCEPTION 'Todas las tarjetas de esta baraja están retenidas';
 END IF;
 v_idx:=1+floor(random()*cardinality(v_remaining))::int;
 v_num:=v_remaining[v_idx];
 SELECT * INTO v_card FROM public.monopoly_f3182_cards
  WHERE edition_sku='F3182' AND deck=NEW.deck AND catalog_number=v_num;
 IF NOT FOUND THEN RAISE EXCEPTION 'Carta F3182 no registrada'; END IF;
 UPDATE public.room_virtual_decks
 SET remaining=array_remove(v_remaining,v_num)
 WHERE room_id=NEW.room_id AND deck=NEW.deck;
 UPDATE public.room_card_challenges SET card_number=v_num,
  card_title=v_card.title,challenge_text=v_card.instruction
 WHERE id=NEW.id;
 RETURN NEW;
END;
$body$;
REVOKE ALL ON FUNCTION game_private.assign_virtual_f3182_card() FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.game_finish_virtual_card(p_code text,p_token text,p_card_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $body$
DECLARE v_room public.rooms%rowtype; v_me uuid; v_role text;
 v_challenge public.room_card_challenges%rowtype;
 v_card public.monopoly_f3182_cards%rowtype;
 v_player public.room_players%rowtype; v_target int; v_before int;
 v_total bigint:=0; v_n int; v_cost bigint; v_credit bigint;
 v_other record; v_owner uuid; v_rent bigint; v_owned int; v_group_size int;
 v_refuge_roll int; v_has_move boolean:=false;
 v_note text; v_effect text; v_goal_bonus bigint:=0;
BEGIN
 SELECT room_id,player_id,player_role INTO v_room.id,v_me,v_role
 FROM game_private.member(p_code,p_token);
 IF v_me IS NULL THEN RAISE EXCEPTION 'Sesión inválida'; END IF;
 SELECT * INTO v_room FROM public.rooms WHERE id=v_room.id FOR UPDATE;
 IF v_room.status<>'active' OR v_room.card_mode<>'virtual' THEN
  RAISE EXCEPTION 'La partida no usa cartas virtuales'; END IF;
 IF v_room.pending_amount>0 THEN RAISE EXCEPTION 'Paga primero la deuda pendiente';END IF;
 SELECT * INTO v_challenge FROM public.room_card_challenges
 WHERE id=p_card_id AND room_id=v_room.id FOR UPDATE;
 IF NOT FOUND OR v_challenge.outcome<>'pending' THEN
   RAISE EXCEPTION 'Esta carta ya fue resuelta';END IF;
 IF v_challenge.player_id<>v_room.current_player_id THEN
   RAISE EXCEPTION 'No corresponde al turno actual';END IF;
 IF v_me<>v_challenge.player_id AND v_role<>'host' THEN
   RAISE EXCEPTION 'No puedes resolver una carta de otro jugador'; END IF;
 SELECT * INTO v_card FROM public.monopoly_f3182_cards
 WHERE edition_sku='F3182' AND deck=v_challenge.deck AND catalog_number=v_challenge.card_number;
 IF NOT FOUND THEN RAISE EXCEPTION 'La carta asignada no existe';END IF;
 SELECT * INTO v_player FROM public.room_players WHERE id=v_challenge.player_id FOR UPDATE;
 IF v_player.bankrupt THEN RAISE EXCEPTION 'Jugador en bancarrota';END IF;
 v_before:=v_player.board_position;
 v_effect:=v_card.effect_code;
 v_note:='Aplicación automática F3182: '||v_card.title;

 IF v_effect IN ('bank_receive','bank_pay') THEN
   v_cost:=v_card.effect_value;
   IF v_effect='bank_pay' AND v_player.balance<v_cost THEN
     RAISE EXCEPTION 'Saldo insuficiente: hipoteca o negocia antes de finalizar esta carta'; END IF;
   UPDATE public.room_players
     SET balance=balance+CASE WHEN v_effect='bank_receive' THEN v_cost ELSE -v_cost END
   WHERE id=v_player.id;
   INSERT INTO public.room_ledger(room_id,from_player,to_player,amount,description,card_challenge_id)
   VALUES(v_room.id,
     CASE WHEN v_effect='bank_pay' THEN v_player.id ELSE null END,
     CASE WHEN v_effect='bank_receive' THEN v_player.id ELSE null END,
     v_cost,'Carta: '||v_card.title,v_challenge.id);
   v_total:=v_cost;
 ELSIF v_effect='repairs' THEN
   SELECT coalesce(sum(CASE WHEN building_level=5 THEN 0 ELSE building_level END),0),
     count(*) FILTER(WHERE building_level=5)
     INTO v_total,v_n FROM public.room_spaces
     WHERE room_id=v_room.id AND owner_id=v_player.id AND building_level>0;
   v_cost:=v_total*v_card.effect_value+v_n*v_card.secondary_value;
   IF v_player.balance<v_cost THEN RAISE EXCEPTION 'Saldo insuficiente para reparaciones';END IF;
   IF v_cost>0 THEN
     UPDATE public.room_players SET balance=balance-v_cost WHERE id=v_player.id;
     INSERT INTO public.room_ledger(room_id,from_player,amount,description,card_challenge_id)
     VALUES(v_room.id,v_player.id,v_cost,'Reparaciones: '||v_card.title,v_challenge.id);
   END IF;
   v_total:=v_cost;
 ELSIF v_effect IN ('pay_each','collect_each') THEN
   SELECT count(*) INTO v_n FROM public.room_players
    WHERE room_id=v_room.id AND id<>v_player.id AND NOT bankrupt AND participant_status<>'left';
   v_total:=v_n*v_card.effect_value;
   IF v_effect='pay_each' THEN
     IF v_player.balance<v_total THEN RAISE EXCEPTION 'Saldo insuficiente para pagar a cada jugador';END IF;
     UPDATE public.room_players SET balance=balance-v_total WHERE id=v_player.id;
   ELSE
     IF EXISTS(SELECT 1 FROM public.room_players WHERE room_id=v_room.id
       AND id<>v_player.id AND NOT bankrupt AND participant_status<>'left'
       AND balance<v_card.effect_value)
       THEN RAISE EXCEPTION 'Otro jugador necesita fondos para pagar esta carta'; END IF;
     UPDATE public.room_players SET balance=balance+v_total WHERE id=v_player.id;
   END IF;
   FOR v_other IN SELECT id FROM public.room_players WHERE room_id=v_room.id
      AND id<>v_player.id AND NOT bankrupt AND participant_status<>'left'
   LOOP
     UPDATE public.room_players SET
       balance=balance+CASE WHEN v_effect='pay_each' THEN v_card.effect_value ELSE -v_card.effect_value END
       WHERE id=v_other.id;
     INSERT INTO public.room_ledger(room_id,from_player,to_player,amount,description,card_challenge_id)
     VALUES(v_room.id,
       CASE WHEN v_effect='pay_each' THEN v_player.id ELSE v_other.id END,
       CASE WHEN v_effect='pay_each' THEN v_other.id ELSE v_player.id END,
       v_card.effect_value,'Carta: '||v_card.title,v_challenge.id);
   END LOOP;
 ELSIF v_effect IN ('move','move_back','move_collect','move_pass_go','nearest_refuge','nearest_utility') THEN
   IF v_effect='move_back' THEN
     v_target:=(v_before+40-(v_card.effect_value%40))%40;
   ELSIF v_effect IN ('move','move_collect','move_pass_go') THEN
     v_target:=v_card.effect_value::int;
   ELSIF v_effect='nearest_refuge' THEN
     SELECT position INTO v_target FROM public.room_spaces
       WHERE room_id=v_room.id AND space_type='railroad' AND position>v_before
       ORDER BY position LIMIT 1;
     IF v_target IS NULL THEN
       SELECT min(position) INTO v_target FROM public.room_spaces
       WHERE room_id=v_room.id AND space_type='railroad'; END IF;
   ELSE
     SELECT position INTO v_target FROM public.room_spaces
       WHERE room_id=v_room.id AND space_type='utility' AND position>v_before
       ORDER BY position LIMIT 1;
     IF v_target IS NULL THEN
       SELECT min(position) INTO v_target FROM public.room_spaces
       WHERE room_id=v_room.id AND space_type='utility'; END IF;
   END IF;
   IF v_target IS NULL OR v_target NOT BETWEEN 0 AND 39 THEN
     RAISE EXCEPTION 'Destino de carta inválido'; END IF;
   v_has_move:=true;
   IF v_effect='move_collect' THEN
     v_goal_bonus:=v_room.go_bonus;
   ELSIF v_effect IN ('move_pass_go','nearest_refuge','nearest_utility') AND v_target<v_before THEN
     v_goal_bonus:=v_room.go_bonus;
   END IF;
   UPDATE public.room_players SET board_position=v_target,
      balance=balance+v_goal_bonus WHERE id=v_player.id;
   IF v_goal_bonus>0 THEN
      INSERT INTO public.room_ledger(room_id,to_player,amount,description,card_challenge_id)
      VALUES(v_room.id,v_player.id,v_goal_bonus,'Carta: paso por Salida',v_challenge.id);
   END IF;
   SELECT owner_id INTO v_owner FROM public.room_spaces
    WHERE room_id=v_room.id AND position=v_target;
   IF v_owner IS NOT NULL AND v_owner<>v_player.id THEN
     SELECT coalesce(s.rent_schedule[least(s.building_level+1,6)],0) INTO v_rent
     FROM public.room_spaces s WHERE s.room_id=v_room.id AND s.position=v_target AND NOT s.mortgaged;
     IF v_rent IS NOT NULL THEN
       IF v_effect='nearest_refuge' THEN
         SELECT count(*) INTO v_owned FROM public.room_spaces
         WHERE room_id=v_room.id AND space_type='railroad' AND owner_id=v_owner;
         SELECT coalesce(rent_schedule[least(v_owned,6)],0)*2 INTO v_rent
         FROM public.room_spaces WHERE room_id=v_room.id AND position=v_target;
       ELSIF v_effect='nearest_utility' THEN
         v_refuge_roll:=1+(get_byte(extensions.gen_random_bytes(1),0)%6)
                     +1+(get_byte(extensions.gen_random_bytes(1),0)%6);
         v_rent:=v_refuge_roll*10;
       ELSIF v_effect NOT IN ('move_back') THEN
         IF EXISTS(SELECT 1 FROM public.room_spaces
           WHERE room_id=v_room.id AND position=v_target AND space_type='railroad') THEN
           SELECT count(*) INTO v_owned FROM public.room_spaces
           WHERE room_id=v_room.id AND space_type='railroad' AND owner_id=v_owner;
           SELECT coalesce(rent_schedule[least(v_owned,6)],0) INTO v_rent
           FROM public.room_spaces WHERE room_id=v_room.id AND position=v_target;
         END IF;
       END IF;
       IF coalesce(v_rent,0)>0 THEN
         UPDATE public.rooms SET pending_amount=v_rent,
            pending_player_id=v_player.id,pending_to_id=v_owner,
            pending_reason='Alquiler por carta: '||v_card.title WHERE id=v_room.id;
       END IF;
     END IF;
   END IF;
 ELSIF v_effect='jail' THEN
   UPDATE public.room_players SET board_position=10,in_jail=true,jail_attempts=0 WHERE id=v_player.id;
   UPDATE public.rooms SET last_roll_double=false,doubles_streak=0 WHERE id=v_room.id;
   v_target:=10;v_has_move:=true;
 ELSIF v_effect='jail_free' THEN
   INSERT INTO public.room_held_jail_cards(room_id,player_id,deck,card_number)
    VALUES(v_room.id,v_player.id,v_challenge.deck,v_challenge.card_number);
 ELSIF v_effect IS DISTINCT FROM 'none' THEN
   RAISE EXCEPTION 'Efecto de carta no implementado: %',v_effect;
 END IF;
 UPDATE public.room_card_challenges SET outcome='completed',effect_kind=
   CASE WHEN v_effect IN ('bank_receive','bank_pay','jail') THEN v_effect
        WHEN v_has_move THEN 'move' ELSE 'none' END,
   effect_amount=CASE WHEN v_effect IN ('bank_receive','bank_pay') THEN v_total
                      WHEN v_effect='repairs' AND v_total>0 THEN v_total
                      ELSE null END,
   target_position=CASE WHEN v_has_move THEN v_target ELSE null END,
   result_note=left(v_note,500),resolved_at=now(),resolved_by=v_me
 WHERE id=v_challenge.id;
 INSERT INTO public.room_events(room_id,actor_id,event_type,payload)
 VALUES(v_room.id,v_me,'virtual_card_applied',jsonb_build_object(
  'cardId',v_challenge.id,'playerId',v_player.id,'deck',v_challenge.deck,
  'number',v_challenge.card_number,'effect',v_effect,
  'amount',v_total,'from',v_before,'to',CASE WHEN v_has_move THEN v_target ELSE null END));
 PERFORM game_private.notify(v_room.id);
 RETURN jsonb_build_object('ok',true,'cardId',v_challenge.id,'effect',v_effect,'amount',v_total);
END;
$body$;
REVOKE ALL ON FUNCTION public.game_finish_virtual_card(text,text,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.game_finish_virtual_card(text,text,bigint) TO anon,authenticated;

CREATE FUNCTION public.game_use_jail_pass(p_code text,p_token text,p_deck text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $body$
DECLARE v_room uuid;v_me uuid;v_role text;v_card smallint;
BEGIN
 SELECT room_id,player_id,player_role INTO v_room,v_me,v_role
  FROM game_private.member(p_code,p_token);
 IF v_me IS NULL THEN RAISE EXCEPTION 'Sesión inválida'; END IF;
 PERFORM 1 FROM public.rooms WHERE id=v_room AND status='active' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'La partida no está activa';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.room_players WHERE id=v_me AND in_jail AND NOT bankrupt)
 THEN RAISE EXCEPTION 'No estás en la cárcel'; END IF;
 SELECT card_number INTO v_card FROM public.room_held_jail_cards
 WHERE room_id=v_room AND player_id=v_me AND deck=p_deck FOR UPDATE;
 IF v_card IS NULL THEN RAISE EXCEPTION 'No posees esta tarjeta';END IF;
 DELETE FROM public.room_held_jail_cards
 WHERE room_id=v_room AND player_id=v_me AND deck=p_deck AND card_number=v_card;
 UPDATE public.room_players SET in_jail=false,jail_attempts=0 WHERE id=v_me;
 INSERT INTO public.room_events(room_id,actor_id,event_type,payload)
 VALUES(v_room,v_me,'jail_pass_used',jsonb_build_object('deck',p_deck,'cardNumber',v_card));
 PERFORM game_private.notify(v_room);
 RETURN jsonb_build_object('ok',true);
END;$body$;
REVOKE ALL ON FUNCTION public.game_use_jail_pass(text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.game_use_jail_pass(text,text,text) TO anon,authenticated;

-- Existing session tokens are valid even after the room is closed.
-- Only authenticated room members may read their own held passes.
CREATE FUNCTION public.game_my_jail_passes(p_code text,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $body$
DECLARE rid uuid;pid uuid; r jsonb;
BEGIN
 SELECT room_id,player_id INTO rid,pid FROM game_private.member(p_code,p_token);
 IF pid IS NULL THEN RAISE EXCEPTION 'Sesión inválida';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('deck',deck,'number',card_number)),'[]'::jsonb)
 INTO r FROM public.room_held_jail_cards WHERE room_id=rid AND player_id=pid;
 RETURN r;
END;$body$;
REVOKE ALL ON FUNCTION public.game_my_jail_passes(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.game_my_jail_passes(text,text) TO anon,authenticated;

COMMIT;