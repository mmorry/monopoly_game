-- Monopoly Perú F3182 | SQL 016 | 40 board spaces verified from the user's physical board.
-- Source: 8 overlapping board photographs (458500-458511), 2 mortgage-back photographs
-- (458497-458498), and the user's ordered 40-slot transcription.
-- User's transcription skipped La Tómbola at position 33, visible between Chan Chan and Líneas de Nasca.
-- Original purchase amounts are Monopoly currency (M), NOT Peruvian soles.
-- Mortgage amounts for 12 shown backs are verified; others remain NULL,
-- while the game engine follows the half-purchase-price rule.
BEGIN;

CREATE TABLE public.monopoly_f3182_board (
 position smallint PRIMARY KEY CHECK(position BETWEEN 0 AND 39),
 title_key text UNIQUE REFERENCES public.monopoly_f3182_titles(title_key),
 space_type text NOT NULL CHECK(space_type IN
   ('start','property','railroad','utility','tax','chance','community','jail','parking','go_to_jail')),
 special_name text,
 special_price bigint CHECK(special_price IS NULL OR special_price BETWEEN 0 AND 10000000),
 CHECK ((title_key IS NOT NULL AND space_type IN ('property','railroad','utility') AND special_name IS NULL AND special_price IS NULL)
    OR (title_key IS NULL AND space_type NOT IN ('property','railroad','utility')
       AND special_name IS NOT NULL
       AND ((space_type='tax' AND special_price>0) OR (space_type<>'tax' AND special_price IS NULL))))
);
INSERT INTO public.monopoly_f3182_board(position,title_key,space_type,special_name,special_price)
VALUES
(0,NULL,'start','Salida',NULL),
(1,'catarata_bayoz','property',NULL,NULL),
(2,NULL,'community','La Tómbola',NULL),
(3,'laguna_choclococha','property',NULL,NULL),
(4,NULL,'tax','Impuesto por uso del Qhapaq Ñan',200),
(5,'refugio_oso','railroad',NULL,NULL),
(6,'pampachiri','property',NULL,NULL),
(7,NULL,'chance','El Chamán',NULL),
(8,'huanuco_pampa','property',NULL,NULL),
(9,'lago_sandoval','property',NULL,NULL),
(10,NULL,'jail','En la cárcel / de visita',NULL),
(11,'cerro_baul','property',NULL,NULL),
(12,'manglares_tumbes','utility',NULL,NULL),
(13,'laguna_azul','property',NULL,NULL),
(14,'pampa_ayacucho','property',NULL,NULL),
(15,'refugio_colibri','railroad',NULL,NULL),
(16,'miculla','property',NULL,NULL),
(17,NULL,'community','La Tómbola',NULL),
(18,'velo_novia','property',NULL,NULL),
(19,'plaza_mayor','property',NULL,NULL),
(20,NULL,'parking','Parada libre',NULL),
(21,'banos_inca','property',NULL,NULL),
(22,NULL,'chance','El Chamán',NULL),
(23,'pozuzo','property',NULL,NULL),
(24,'basilica_arequipa','property',NULL,NULL),
(25,'refugio_delfin','railroad',NULL,NULL),
(26,'islas_palomino','property',NULL,NULL),
(27,'playa_organos','property',NULL,NULL),
(28,'reserva_titicaca','utility',NULL,NULL),
(29,'nevado_huascaran','property',NULL,NULL),
(30,NULL,'go_to_jail','Ve a la cárcel',NULL),
(31,'kuelap','property',NULL,NULL),
(32,'chan_chan','property',NULL,NULL),
(33,NULL,'community','La Tómbola',NULL),
(34,'lineas_nasca','property',NULL,NULL),
(35,'refugio_gallito','railroad',NULL,NULL),
(36,NULL,'chance','El Chamán',NULL),
(37,'ciudad_inka_machupicchu','property',NULL,NULL),
(38,NULL,'tax','Impuesto por navegar por el río Amazonas',100),
(39,'senor_sipan','property',NULL,NULL);

-- Prices read directly from the board; only mortgages visible on the physical backs
-- are persisted as confirmed. All 28 physical title positions become unambiguous.
UPDATE public.monopoly_f3182_titles t
 SET board_position=v.position,
     purchase_price=v.price,
     mortgage_value=v.mortgage
FROM (VALUES
('catarata_bayoz',1::smallint,60::bigint,30::bigint),
('laguna_choclococha',3::smallint,60::bigint,30::bigint),
('refugio_oso',5::smallint,200::bigint,100::bigint),
('pampachiri',6::smallint,100::bigint,NULL::bigint),
('huanuco_pampa',8::smallint,100::bigint,NULL::bigint),
('lago_sandoval',9::smallint,120::bigint,NULL::bigint),
('cerro_baul',11::smallint,140::bigint,NULL::bigint),
('manglares_tumbes',12::smallint,150::bigint,75::bigint),
('laguna_azul',13::smallint,140::bigint,NULL::bigint),
('pampa_ayacucho',14::smallint,160::bigint,NULL::bigint),
('refugio_colibri',15::smallint,200::bigint,100::bigint),
('miculla',16::smallint,180::bigint,NULL::bigint),
('velo_novia',18::smallint,180::bigint,NULL::bigint),
('plaza_mayor',19::smallint,200::bigint,100::bigint),
('banos_inca',21::smallint,220::bigint,NULL::bigint),
('pozuzo',23::smallint,220::bigint,NULL::bigint),
('basilica_arequipa',24::smallint,240::bigint,NULL::bigint),
('refugio_delfin',25::smallint,200::bigint,100::bigint),
('islas_palomino',26::smallint,260::bigint,130::bigint),
('playa_organos',27::smallint,260::bigint,130::bigint),
('reserva_titicaca',28::smallint,150::bigint,75::bigint),
('nevado_huascaran',29::smallint,280::bigint,140::bigint),
('kuelap',31::smallint,300::bigint,NULL::bigint),
('chan_chan',32::smallint,300::bigint,NULL::bigint),
('lineas_nasca',34::smallint,320::bigint,NULL::bigint),
('refugio_gallito',35::smallint,200::bigint,100::bigint),
('ciudad_inka_machupicchu',37::smallint,350::bigint,NULL::bigint),
('senor_sipan',39::smallint,400::bigint,NULL::bigint)
) AS v(title_key,position,price,mortgage)
WHERE t.title_key=v.title_key AND t.edition_sku='F3182';
CREATE UNIQUE INDEX monopoly_f3182_titles_unique_position
 ON public.monopoly_f3182_titles(board_position) WHERE board_position IS NOT NULL;

DO $verify$
DECLARE n int; duplicate_count int;bad_kinds int;
BEGIN
 SELECT count(*) INTO n FROM public.monopoly_f3182_board;
 IF n<>40 THEN RAISE EXCEPTION 'Expected 40 board slots, found %',n; END IF;
 SELECT count(*) INTO n FROM public.monopoly_f3182_titles
   WHERE edition_sku='F3182' AND purchase_price IS NOT NULL AND board_position IS NOT NULL;
 IF n<>28 THEN RAISE EXCEPTION 'Expected 28 priced titles, found %',n; END IF;
 SELECT count(*) INTO n FROM public.monopoly_f3182_titles
   WHERE edition_sku='F3182' AND mortgage_value IS NOT NULL;
 IF n<>12 THEN RAISE EXCEPTION 'Expected 12 verified mortgage backs, found %',n; END IF;
 SELECT count(*) INTO bad_kinds FROM public.monopoly_f3182_board b
 JOIN public.monopoly_f3182_titles t ON t.title_key=b.title_key
 WHERE b.space_type<>t.kind;
 IF bad_kinds>0 THEN RAISE EXCEPTION 'Incompatible title kinds';END IF;
 SELECT count(*) INTO n FROM public.monopoly_f3182_board WHERE space_type='community';
 IF n<>3 THEN RAISE EXCEPTION 'Missing La Tómbola square';END IF;
END $verify$;

ALTER TABLE public.monopoly_f3182_board ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.monopoly_f3182_board FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.monopoly_f3182_board TO anon,authenticated;
CREATE POLICY f3182_public_board_read ON public.monopoly_f3182_board
  FOR SELECT TO anon,authenticated USING(true);

-- Replace earlier internet-only partial references with evidence from physical board.
-- Isla de los Uros does not appear among the 28 physical F3182 titles.
DELETE FROM public.monopoly_edition_items
WHERE edition_sku='F3182' AND item_key='isla_uros';
UPDATE public.monopoly_edition_items i
  SET board_position=t.board_position,
      purchase_price=t.purchase_price,
      rent_schedule=t.rent_schedule,
      verified_scope='position',
      display_name=t.title_name
FROM public.monopoly_f3182_titles t
WHERE i.edition_sku='F3182' AND t.edition_sku='F3182' AND
 i.item_key IN ('nevado_huascaran','laguna_choclococha','senor_sipan')
 AND t.title_key=i.item_key;
UPDATE public.monopoly_edition_items i
 SET board_position=t.board_position,purchase_price=t.purchase_price,
     rent_schedule=t.rent_schedule,verified_scope='position',display_name=t.title_name
FROM public.monopoly_f3182_titles t
WHERE i.edition_sku='F3182' AND t.edition_sku='F3182' AND
 (i.item_key='bosque_piedras_pampachiri' AND t.title_key='pampachiri'
 OR i.item_key='kuelap' AND t.title_key='kuelap'
 OR i.item_key='machu_picchu' AND t.title_key='ciudad_inka_machupicchu');

-- The room's default 40 inserts receive the correct, source-verified board.
CREATE FUNCTION game_private.f3182_seed_room_space()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $body$
DECLARE v_edition text; v_board public.monopoly_f3182_board%rowtype;
 v_title public.monopoly_f3182_titles%rowtype;
BEGIN
 SELECT edition_sku INTO v_edition FROM public.rooms WHERE id=NEW.room_id;
 IF v_edition IS DISTINCT FROM 'F3182' THEN RETURN NEW; END IF;
 SELECT * INTO v_board FROM public.monopoly_f3182_board WHERE position=NEW.position;
 IF NOT FOUND THEN RAISE EXCEPTION 'F3182 board missing position %',NEW.position; END IF;
 NEW.space_type:=v_board.space_type;
 IF v_board.title_key IS NULL THEN
    NEW.name:=v_board.special_name; NEW.price:=v_board.special_price;
    NEW.color_group:=NULL;NEW.rent_schedule:=NULL;NEW.build_cost:=NULL;
    NEW.mortgage_value:=NULL;NEW.f3182_title_key:=NULL;
 ELSE
    SELECT * INTO v_title FROM public.monopoly_f3182_titles
      WHERE title_key=v_board.title_key;
    NEW.name:=v_title.title_name;NEW.price:=v_title.purchase_price;
    NEW.mortgage_value:=v_title.mortgage_value;
    NEW.color_group:=v_title.color_group;NEW.rent_schedule:=v_title.rent_schedule;
    NEW.build_cost:=v_title.house_cost;NEW.f3182_title_key:=v_title.title_key;
 END IF;
 RETURN NEW;
END;$body$;
REVOKE ALL ON FUNCTION game_private.f3182_seed_room_space() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER room_spaces_f3182_seed
 BEFORE INSERT ON public.room_spaces FOR EACH ROW
 EXECUTE FUNCTION game_private.f3182_seed_room_space();

-- Existing waiting rooms are left untouched. The host may explicitly restore the official
-- template for their own room; active/finished games cannot be overwritten.
CREATE FUNCTION public.game_load_f3182_board(p_code text,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $body$
DECLARE v_room uuid;v_me uuid;v_role text;v_status text;v_updated int;
BEGIN
 SELECT room_id,player_id,player_role INTO v_room,v_me,v_role
   FROM game_private.member(p_code,p_token);
 IF v_me IS NULL OR v_role<>'host' THEN
   RAISE EXCEPTION 'Solo el anfitrión puede restaurar el tablero';END IF;
 SELECT status INTO v_status FROM public.rooms WHERE id=v_room AND edition_sku='F3182' FOR UPDATE;
 IF NOT FOUND OR v_status<>'waiting' THEN
   RAISE EXCEPTION 'Solo puedes cargar el tablero antes de iniciar la partida'; END IF;
 IF EXISTS(SELECT 1 FROM public.room_spaces WHERE room_id=v_room
           AND (owner_id IS NOT NULL OR building_level<>0 OR mortgaged))
 THEN RAISE EXCEPTION 'No puedes restaurar un tablero con propiedades adquiridas';END IF;
 UPDATE public.room_spaces s
  SET name=coalesce(t.title_name,b.special_name),
      space_type=b.space_type,
      color_group=t.color_group,
      price=coalesce(t.purchase_price,b.special_price),
      rent_schedule=t.rent_schedule,
      build_cost=t.house_cost,
      mortgage_value=t.mortgage_value,
      f3182_title_key=t.title_key
 FROM public.monopoly_f3182_board b
 LEFT JOIN public.monopoly_f3182_titles t ON t.title_key=b.title_key
 WHERE s.room_id=v_room AND s.position=b.position;
 GET DIAGNOSTICS v_updated=ROW_COUNT;
 IF v_updated<>40 THEN RAISE EXCEPTION 'Incomplete board: % slots updated',v_updated;END IF;
 INSERT INTO public.room_events(room_id,actor_id,event_type,payload)
 VALUES (v_room,v_me,'f3182_board_loaded',jsonb_build_object('spaces',v_updated));
 PERFORM game_private.notify(v_room);
 RETURN jsonb_build_object('ok',true,'spaces',v_updated,'edition','F3182');
END;$body$;
REVOKE ALL ON FUNCTION public.game_load_f3182_board(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.game_load_f3182_board(text,text) TO anon,authenticated;

UPDATE public.monopoly_editions
 SET verification_state='complete',
     notes='Tablero F3182 completo: 40 posiciones y 28 precios de compra verificados con fotografías del usuario. Los 28 alquileres y costos de construcción están registrados. Solo se han confirmado por reverso de tarjeta 12 hipotecas; para otras posiciones la mecánica aplica 50% del precio de compra. Los contenidos exactos de 32 cartas Chamán/Tómbola permanecen pendientes.'
 WHERE sku='F3182';
COMMIT;
