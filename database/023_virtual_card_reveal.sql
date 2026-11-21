-- 023 | Carta virtual: solo el jugador de turno revela, todos la ven después.
-- Aplicar antes de desplegar la interfaz que usa game_reveal_virtual_card.
BEGIN;

ALTER TABLE public.room_card_challenges
  ADD COLUMN IF NOT EXISTS revealed_at timestamptz;

CREATE OR REPLACE FUNCTION public.game_reveal_virtual_card(
  p_code text, p_token text, p_card_id bigint
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_room_id uuid; v_me uuid; v_room public.rooms%rowtype;
        v_card public.room_card_challenges%rowtype;
BEGIN
  SELECT room_id,player_id INTO v_room_id,v_me
  FROM game_private.member(p_code,p_token);
  IF v_me IS NULL THEN RAISE EXCEPTION 'Sesión inválida'; END IF;

  SELECT * INTO v_room FROM public.rooms WHERE id=v_room_id FOR UPDATE;
  IF v_room.status<>'active' OR v_room.card_mode<>'virtual' THEN
    RAISE EXCEPTION 'La partida no usa cartas virtuales activas';
  END IF;

  SELECT * INTO v_card FROM public.room_card_challenges
  WHERE id=p_card_id AND room_id=v_room_id FOR UPDATE;
  IF NOT FOUND OR v_card.outcome<>'pending' THEN
    RAISE EXCEPTION 'La carta no está pendiente';
  END IF;
  IF v_me<>v_room.current_player_id OR v_me<>v_card.player_id THEN
    RAISE EXCEPTION 'Solo el jugador en turno puede abrir esta carta';
  END IF;

  IF v_card.revealed_at IS NULL THEN
    UPDATE public.room_card_challenges
    SET revealed_at=now() WHERE id=v_card.id;
    INSERT INTO public.room_events(room_id,actor_id,event_type,payload)
    VALUES(v_room_id,v_me,'card_revealed',
      jsonb_build_object('cardId',v_card.id,'deck',v_card.deck));
    PERFORM game_private.notify(v_room_id);
  END IF;
  RETURN jsonb_build_object('ok',true,'cardId',v_card.id);
END
$fn$;

-- El contenido de cartas virtuales pendientes no debe salir del servidor
-- hasta que su titular pulse «Sacar carta».
CREATE OR REPLACE FUNCTION public.game_card_snapshot(p_code text,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_room uuid; v_me uuid;
BEGIN
  SELECT room_id,player_id INTO v_room,v_me
  FROM game_private.member(p_code,p_token);
  IF v_me IS NULL THEN RAISE EXCEPTION 'Sesión inválida o expirada';END IF;

  RETURN jsonb_build_object(
    'cards',coalesce((
      SELECT jsonb_agg(c.payload ORDER BY c.id DESC)
      FROM (
        SELECT d.id,jsonb_build_object(
          'id',d.id,'playerId',d.player_id,'turn',d.turn_number,
          'position',d.position,'deck',d.deck,
          'cardNumber',CASE WHEN r.card_mode='virtual' AND d.outcome='pending'
                             AND d.revealed_at IS NULL THEN NULL ELSE d.card_number END,
          'title',CASE WHEN r.card_mode='virtual' AND d.outcome='pending'
                         AND d.revealed_at IS NULL THEN NULL ELSE d.card_title END,
          'instruction',CASE WHEN r.card_mode='virtual' AND d.outcome='pending'
                               AND d.revealed_at IS NULL THEN NULL ELSE d.challenge_text END,
          'revealedAt',d.revealed_at,
          'outcome',d.outcome,'effect',d.effect_kind,
          'amount',CASE WHEN r.card_mode='virtual' AND d.outcome='pending'
                          AND d.revealed_at IS NULL THEN NULL ELSE d.effect_amount END,
          'otherPlayerId',d.other_player_id,'targetPosition',d.target_position,
          'note',d.result_note,'source',d.source_type,
          'drawnAt',d.drawn_at,'resolvedAt',d.resolved_at
        ) AS payload
        FROM public.room_card_challenges d
        JOIN public.rooms r ON r.id=d.room_id
        WHERE d.room_id=v_room
        ORDER BY d.id DESC LIMIT 80
      ) c
    ),'[]'::jsonb),
    'totals',(
      SELECT jsonb_build_object(
        'chaman',count(*) FILTER (WHERE d.deck='chaman'),
        'tombola',count(*) FILTER (WHERE d.deck='tombola'),
        'pending',count(*) FILTER (WHERE d.outcome='pending'),
        'completed',count(*) FILTER (WHERE d.outcome='completed'),
        'failed',count(*) FILTER (WHERE d.outcome='failed'),
        'cancelled',count(*) FILTER (WHERE d.outcome='cancelled')
      )
      FROM public.room_card_challenges d WHERE d.room_id=v_room
    )
  );
END
$fn$;

-- El cierre también exige que el dueño ya haya revelado la carta.
DO $patch$
DECLARE source_sql text;
BEGIN
  source_sql:=pg_get_functiondef('public.game_finish_virtual_card(text,text,bigint)'::regprocedure);
  IF position('IF v_me<>v_challenge.player_id AND v_role<>''host'' THEN' IN source_sql)=0 THEN
    RAISE EXCEPTION 'La función de cierre cambió; revisar antes de aplicar';
  END IF;
  source_sql:=replace(source_sql,
    'IF v_me<>v_challenge.player_id AND v_role<>''host'' THEN',
    'IF v_me<>v_challenge.player_id THEN');
  IF position('SELECT * INTO v_card FROM public.monopoly_f3182_cards' IN source_sql)=0 THEN
    RAISE EXCEPTION 'No se encontró el punto de validación del cierre';
  END IF;
  source_sql:=replace(source_sql,
    'SELECT * INTO v_card FROM public.monopoly_f3182_cards',
    'IF v_challenge.revealed_at IS NULL THEN
       RAISE EXCEPTION ''Primero debes revelar la carta'';
     END IF;
     SELECT * INTO v_card FROM public.monopoly_f3182_cards');
  EXECUTE source_sql;
END
$patch$;

REVOKE ALL ON FUNCTION public.game_reveal_virtual_card(text,text,bigint)
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.game_reveal_virtual_card(text,text,bigint)
TO anon,authenticated,service_role;

COMMIT;