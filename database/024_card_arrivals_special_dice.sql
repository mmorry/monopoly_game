-- 024: Cartas de movimiento F3182, decisiones de compra y tirada especial.
-- Script versionado; ejecución directa autorizada para el proyecto Monopoly Perú.
BEGIN;
ALTER TABLE public.room_card_challenges
  ADD COLUMN IF NOT EXISTS arrival_status text,
  ADD COLUMN IF NOT EXISTS special_dice_pending boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS special_die_1 smallint,
  ADD COLUMN IF NOT EXISTS special_die_2 smallint;
ALTER TABLE public.room_card_challenges
  DROP CONSTRAINT IF EXISTS room_card_arrival_status_check;
ALTER TABLE public.room_card_challenges
  ADD CONSTRAINT room_card_arrival_status_check
    CHECK (arrival_status IS NULL OR arrival_status IN ('pending','auction','special_dice','resolved'));
ALTER TABLE public.room_card_challenges
  ADD CONSTRAINT room_card_special_dice_valid CHECK (
    (special_die_1 IS NULL AND special_die_2 IS NULL) OR
    (special_die_1 BETWEEN 1 AND 6 AND special_die_2 BETWEEN 1 AND 6)
  );

-- Reglas originales: ambas cartas de refugio duplican el alquiler;
-- el área natural protegida requiere 2 dados adicionales × 10.
UPDATE public.monopoly_f3182_cards
SET instruction='Avanza hasta el refugio más cercano. Si está libre, puedes comprarlo; si pertenece a otro jugador y no está hipotecado, paga el doble del alquiler que corresponda.'
WHERE edition_sku='F3182' AND deck='chaman' AND catalog_number IN (4,15)
  AND effect_code='nearest_refuge';
UPDATE public.monopoly_f3182_cards
SET instruction='Avanza hasta el área natural protegida más cercana. Si está libre, puedes comprarla; si pertenece a otro jugador y no está hipotecada, lanza dos dados adicionales y paga 10 veces la suma obtenida.'
WHERE edition_sku='F3182' AND deck='chaman' AND catalog_number=5 AND effect_code='nearest_utility';

DO $patch$
DECLARE src text;
BEGIN
  src:=pg_get_functiondef('public.game_finish_virtual_card(text,text,bigint)'::regprocedure);
  IF position('v_refuge_roll:=1+(get_byte' IN src)=0
     OR position('UPDATE public.room_card_challenges SET outcome=''completed''' IN src)=0
  THEN RAISE EXCEPTION 'El resolvedor de cartas cambió: revisar script 024'; END IF;

  -- No calcular el dado especial en secreto ni cargar la deuda antes de mostrar la tirada.
  src:=replace(src,
'         v_refuge_roll:=1+(get_byte(extensions.gen_random_bytes(1),0)%6)
                     +1+(get_byte(extensions.gen_random_bytes(1),0)%6);
         v_rent:=v_refuge_roll*10;',
'         v_refuge_roll:=null;
         v_rent:=0;');
  IF position('v_refuge_roll:=1+(get_byte' IN src)>0 THEN
    RAISE EXCEPTION 'No se pudo quitar tirada especial oculta';END IF;

  -- Para cualquier carta que mueve a una propiedad libre, mantener la decisión pendiente.
  -- Si es una utility con dueño, esperar una tirada especial explícita.
  src:=replace(src,
' INSERT INTO public.room_events(room_id,actor_id,event_type,payload)
 VALUES(v_room.id,v_me,''virtual_card_applied''',
' IF v_has_move AND EXISTS (
     SELECT 1 FROM public.room_spaces s
     WHERE s.room_id=v_room.id AND s.position=v_target
       AND s.space_type IN (''property'',''railroad'',''utility'')
       AND s.owner_id IS NULL AND coalesce(s.price,0)>0
   ) THEN
   UPDATE public.room_card_challenges
   SET arrival_status=''pending'' WHERE id=v_challenge.id;
 END IF;
 IF v_effect=''nearest_utility'' AND v_owner IS NOT NULL AND v_owner<>v_player.id
   AND EXISTS (SELECT 1 FROM public.room_spaces s WHERE s.room_id=v_room.id
               AND s.position=v_target AND NOT s.mortgaged) THEN
   UPDATE public.room_card_challenges
   SET arrival_status=''special_dice'',special_dice_pending=true
   WHERE id=v_challenge.id;
 END IF;
 INSERT INTO public.room_events(room_id,actor_id,event_type,payload)
 VALUES(v_room.id,v_me,''virtual_card_applied''');
  IF position('arrival_status=''special_dice''' IN src)=0 THEN
    RAISE EXCEPTION 'No se pudo añadir el estado de carta'; END IF;
  EXECUTE src;

  src:=pg_get_functiondef('game_private.advance_if_settled(text,text)'::regprocedure);
  IF position('IF EXISTS(SELECT 1 FROM public.room_auctions' IN src)=0 THEN
    RAISE EXCEPTION 'El avance automático cambió';END IF;
  src:=replace(src,
' IF EXISTS(SELECT 1 FROM public.room_auctions',
' IF EXISTS(SELECT 1 FROM public.room_card_challenges c WHERE c.room_id=rid
     AND c.player_id=pid AND c.turn_number=rr.turn_number
     AND c.arrival_status IN (''pending'',''auction'',''special_dice''))
 THEN RETURN;END IF;
 IF EXISTS(SELECT 1 FROM public.room_auctions');
  EXECUTE src;

  src:=pg_get_functiondef('public.game_action(text,text,text,jsonb)'::regprocedure);
  IF position('   if v_room.pending_amount>0 then raise exception ''Debes saldar el pago pendiente''; end if;' IN src)=0
  THEN RAISE EXCEPTION 'La finalización manual cambió';END IF;
  src:=replace(src,
'   if v_room.pending_amount>0 then raise exception ''Debes saldar el pago pendiente''; end if;',
'   if v_room.pending_amount>0 then raise exception ''Debes saldar el pago pendiente''; end if;
   if exists(select 1 from public.room_card_challenges c where c.room_id=v_room.id
      and c.player_id=v_me and c.turn_number=v_room.turn_number
      and c.arrival_status in (''pending'',''auction'',''special_dice'')) then
     raise exception ''Primero resuelve la compra, subasta o los dados especiales de la carta'';
   end if;');
  EXECUTE src;

  src:=pg_get_functiondef('public.game_property(text,text,text,smallint)'::regprocedure);
  IF position(' if p_action=''buy'' then perform game_private.advance_if_settled' IN src)=0
  THEN RAISE EXCEPTION 'La función de compra cambió';END IF;
  src:=replace(src,
' if p_action=''buy'' then perform game_private.advance_if_settled(p_code,p_token);end if;',
' if p_action=''buy'' then
    update public.room_card_challenges c set arrival_status=''resolved''
    where c.room_id=v_room.id and c.player_id=v_me
      and c.turn_number=v_room.turn_number and c.target_position=p_position
      and c.arrival_status=''pending'';
    perform game_private.advance_if_settled(p_code,p_token);
   end if;');
  EXECUTE src;

  src:=pg_get_functiondef('public.game_decline_property(text,text)'::regprocedure);
  IF position(' PERFORM game_private.notify(r.id);' IN src)=0
  THEN RAISE EXCEPTION 'La función de subasta por rechazo cambió';END IF;
  src:=replace(src,
' PERFORM game_private.notify(r.id);',
' UPDATE public.room_card_challenges c SET arrival_status=''auction''
    WHERE c.room_id=r.id AND c.player_id=pid AND c.turn_number=r.turn_number
      AND c.target_position=s.position AND c.arrival_status=''pending'';
  PERFORM game_private.notify(r.id);');
  EXECUTE src;

  src:=pg_get_functiondef('public.game_auction(text,text,text,jsonb)'::regprocedure);
  IF position(' if p_action in (''close'',''cancel'') then' IN src)=0
  THEN RAISE EXCEPTION 'La función de cierre de subasta cambió';END IF;
  src:=replace(src,
' if p_action in (''close'',''cancel'') then',
' if p_action in (''close'',''cancel'') then
     update public.room_card_challenges c SET arrival_status=''resolved''
     where c.room_id=v_room AND c.turn_number=(
       select turn_number from public.rooms where id=v_room)
       AND c.target_position=v_a.position AND c.arrival_status=''auction'';');
  EXECUTE src;

  src:=pg_get_functiondef('public.game_card_snapshot(text,text)'::regprocedure);
  IF position('''revealedAt'',d.revealed_at,' IN src)=0
  THEN RAISE EXCEPTION 'El snapshot de cartas cambió';END IF;
  src:=replace(src,'''revealedAt'',d.revealed_at,',
'''revealedAt'',d.revealed_at,
          ''arrivalStatus'',d.arrival_status,
          ''specialDicePending'',d.special_dice_pending,
          ''specialDie1'',d.special_die_1,
          ''specialDie2'',d.special_die_2,');
  EXECUTE src;
END
$patch$;

CREATE OR REPLACE FUNCTION public.game_special_card_dice(
  p_code text,p_token text,p_card_id bigint,
  p_die1 smallint DEFAULT NULL,p_die2 smallint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE rid uuid; pid uuid; r public.rooms%rowtype;
        c public.room_card_challenges%rowtype; s public.room_spaces%rowtype;
        d1 smallint; d2 smallint; total integer; cost bigint;
BEGIN
 SELECT room_id,player_id INTO rid,pid FROM game_private.member(p_code,p_token);
 IF pid IS NULL THEN RAISE EXCEPTION 'Sesión inválida';END IF;
 SELECT * INTO r FROM public.rooms WHERE id=rid FOR UPDATE;
 IF r.status<>'active' OR r.card_mode<>'virtual' OR r.current_player_id IS DISTINCT FROM pid
   OR r.pending_amount>0 THEN
    RAISE EXCEPTION 'No puedes lanzar los dados especiales ahora';
 END IF;
 SELECT * INTO c FROM public.room_card_challenges
 WHERE id=p_card_id AND room_id=rid AND player_id=pid FOR UPDATE;
 IF NOT FOUND OR c.outcome<>'completed' OR NOT c.special_dice_pending
    OR c.arrival_status<>'special_dice' OR c.turn_number<>r.turn_number THEN
    RAISE EXCEPTION 'La tirada especial no está pendiente o ya se ejecutó';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.monopoly_f3182_cards
  WHERE edition_sku='F3182' AND deck=c.deck AND catalog_number=c.card_number
    AND effect_code='nearest_utility') THEN
   RAISE EXCEPTION 'Esta carta no permite tirada especial';
 END IF;
 SELECT * INTO s FROM public.room_spaces
 WHERE room_id=rid AND position=c.target_position FOR UPDATE;
 IF NOT FOUND OR s.space_type<>'utility' OR s.owner_id IS NULL
   OR s.owner_id=pid OR s.mortgaged OR
   NOT EXISTS (SELECT 1 FROM public.room_players WHERE id=pid
                AND board_position=s.position) THEN
   RAISE EXCEPTION 'El destino no requiere un alquiler especial';
 END IF;
 IF r.dice_mode='physical' THEN
   IF p_die1 NOT BETWEEN 1 AND 6 OR p_die2 NOT BETWEEN 1 AND 6 THEN
     RAISE EXCEPTION 'Registra dos dados físicos del 1 al 6';
   END IF;
   d1:=p_die1;d2:=p_die2;
 ELSE
   IF p_die1 IS NOT NULL OR p_die2 IS NOT NULL THEN
     RAISE EXCEPTION 'Los dados virtuales se generan en el servidor';
   END IF;
   d1:=1+(get_byte(extensions.gen_random_bytes(1),0)%6);
   d2:=1+(get_byte(extensions.gen_random_bytes(1),0)%6);
 END IF;
 total:=d1+d2;cost:=total*10;
 UPDATE public.room_card_challenges
 SET special_dice_pending=false,arrival_status='resolved',
     special_die_1=d1,special_die_2=d2,effect_amount=cost,
     result_note=left(coalesce(result_note,'')||
       format(' | Dados especiales %s + %s = %s; alquiler M %s',d1,d2,total,cost),500)
 WHERE id=c.id;
 UPDATE public.rooms SET pending_amount=cost,pending_player_id=pid,
   pending_to_id=s.owner_id,
   pending_reason=format('Carta El Chamán: dados %s + %s = %s × 10; alquiler de %s',
                         d1,d2,total,s.name)
 WHERE id=rid;
 INSERT INTO public.room_events(room_id,actor_id,event_type,payload)
 VALUES(rid,pid,'special_card_dice',
   jsonb_build_object('cardId',c.id,'position',s.position,'d1',d1,'d2',d2,
     'total',total,'rent',cost,'to',s.owner_id));
 PERFORM game_private.notify(rid);
 RETURN jsonb_build_object('ok',true,'cardId',c.id,'d1',d1,'d2',d2,
   'total',total,'rent',cost);
END;$fn$;
REVOKE ALL ON FUNCTION public.game_special_card_dice(text,text,bigint,smallint,smallint)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.game_special_card_dice(text,text,bigint,smallint,smallint)
  TO anon,authenticated,service_role;
COMMIT;