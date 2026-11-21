-- Monopoly Perú F3182 | SQL 015 | 28 verified property-title faces.
-- Physical card photographs uploaded in this conversation (images 1–5).
-- IMPORTANT: purchase price, mortgage value and board POSITION are not visible and remain NULL.
-- rent_schedule=[base,1 house,2 houses,3 houses,4 houses,hotel].
-- Refugios use the first four rent_schedule entries for 1-4 owned.
-- Areas Naturales Protegidas rent = dice * 4 or dice * 10 if owning both.
BEGIN;
CREATE TABLE public.monopoly_f3182_titles (
  title_key text PRIMARY KEY CHECK (length(title_key) BETWEEN 3 AND 80),
  edition_sku text NOT NULL DEFAULT 'F3182'
    REFERENCES public.monopoly_editions(sku),
  title_name text NOT NULL UNIQUE CHECK (length(btrim(title_name)) BETWEEN 2 AND 80),
  department text,
  kind text NOT NULL CHECK(kind IN ('property','railroad','utility')),
  color_group text,
  rent_schedule bigint[] CHECK(rent_schedule IS NULL OR
    (cardinality(rent_schedule)=6 AND 0 <= ALL(rent_schedule))),
  rent_with_group bigint CHECK(rent_with_group IS NULL OR rent_with_group>=0),
  house_cost bigint CHECK(house_cost IS NULL OR house_cost>0),
  hotel_cost bigint CHECK(hotel_cost IS NULL OR hotel_cost>0),
  one_utility_multiplier smallint,
  both_utilities_multiplier smallint,
  source_photo smallint NOT NULL CHECK(source_photo BETWEEN 1 AND 5),
  purchase_price bigint DEFAULT NULL CHECK(purchase_price IS NULL OR purchase_price>0),
  mortgage_value bigint DEFAULT NULL CHECK(mortgage_value IS NULL OR mortgage_value>0),
  board_position smallint DEFAULT NULL CHECK(board_position IS NULL OR board_position BETWEEN 0 AND 39),
  verification text NOT NULL DEFAULT 'physical_card' CHECK(verification='physical_card'),
  CHECK (
    (kind='property' AND color_group IS NOT NULL AND rent_schedule IS NOT NULL
     AND rent_with_group=2*rent_schedule[1]
     AND house_cost IS NOT NULL AND hotel_cost=house_cost
     AND one_utility_multiplier IS NULL AND both_utilities_multiplier IS NULL)
    OR (kind='railroad' AND color_group IS NULL AND rent_schedule IS NOT NULL
      AND rent_with_group IS NULL AND house_cost IS NULL AND hotel_cost IS NULL
      AND one_utility_multiplier IS NULL AND both_utilities_multiplier IS NULL)
    OR (kind='utility' AND color_group IS NULL AND rent_schedule IS NULL
      AND rent_with_group IS NULL AND house_cost IS NULL AND hotel_cost IS NULL
      AND one_utility_multiplier=4 AND both_utilities_multiplier=10)
  )
);
INSERT INTO public.monopoly_f3182_titles(
 title_key,edition_sku,title_name,department,kind,color_group,rent_schedule,
 rent_with_group,house_cost,hotel_cost,one_utility_multiplier,both_utilities_multiplier,source_photo
) VALUES
('catarata_bayoz','F3182','Catarata Bayoz','Junín','property','marrón',ARRAY[2,10,30,90,160,250]::bigint[],4,50,50,NULL,NULL,2),
('laguna_choclococha','F3182','Laguna de Choclococha','Huancavelica','property','marrón',ARRAY[4,20,60,180,320,450]::bigint[],8,50,50,NULL,NULL,2),
('pampachiri','F3182','Bosque de Piedras de Pampachiri','Apurímac','property','celeste',ARRAY[6,30,90,270,400,550]::bigint[],12,50,50,NULL,NULL,4),
('huanuco_pampa','F3182','Zona Arqueológica Monumental Huánuco Pampa','Huánuco','property','celeste',ARRAY[6,30,90,270,400,550]::bigint[],12,50,50,NULL,NULL,4),
('lago_sandoval','F3182','Lago Sandoval','Madre de Dios','property','celeste',ARRAY[8,40,100,300,450,600]::bigint[],16,50,50,NULL,NULL,4),
('cerro_baul','F3182','Cerro Baúl','Moquegua','property','rosa',ARRAY[10,50,150,450,625,750]::bigint[],20,100,100,NULL,NULL,4),
('laguna_azul','F3182','Laguna Azul','San Martín','property','rosa',ARRAY[10,50,150,450,625,750]::bigint[],20,100,100,NULL,NULL,4),
('pampa_ayacucho','F3182','Santuario Histórico de la Pampa de Ayacucho','Ayacucho','property','rosa',ARRAY[12,60,180,500,700,900]::bigint[],24,100,100,NULL,NULL,4),
('velo_novia','F3182','Caída de Agua Velo de la Novia','Ucayali','property','naranja',ARRAY[14,70,200,550,750,950]::bigint[],28,100,100,NULL,NULL,3),
('miculla','F3182','Complejo Arqueológico de Miculla','Tacna','property','naranja',ARRAY[14,70,200,550,750,950]::bigint[],28,100,100,NULL,NULL,3),
('plaza_mayor','F3182','Plaza Mayor','Lima','property','naranja',ARRAY[16,80,220,600,800,1000]::bigint[],32,100,100,NULL,NULL,3),
('pozuzo','F3182','Pozuzo','Pasco','property','rojo',ARRAY[18,90,250,700,875,1050]::bigint[],36,150,150,NULL,NULL,5),
('banos_inca','F3182','Complejo Turístico Baños del Inca','Cajamarca','property','rojo',ARRAY[18,90,250,700,875,1050]::bigint[],36,150,150,NULL,NULL,5),
('basilica_arequipa','F3182','Basílica Catedral de Arequipa','Arequipa','property','rojo',ARRAY[20,100,300,750,925,1100]::bigint[],40,150,150,NULL,NULL,5),
('playa_organos','F3182','Playa Los Órganos','Piura','property','amarillo',ARRAY[22,110,330,800,975,1150]::bigint[],44,150,150,NULL,NULL,3),
('islas_palomino','F3182','Islas Palomino','Callao','property','amarillo',ARRAY[22,110,330,800,975,1150]::bigint[],44,150,150,NULL,NULL,3),
('nevado_huascaran','F3182','Nevado Huascarán','Áncash','property','amarillo',ARRAY[24,120,360,850,1025,1200]::bigint[],48,150,150,NULL,NULL,3),
('kuelap','F3182','Zona Arqueológica Monumental Kuélap','Amazonas','property','verde',ARRAY[26,130,390,900,1100,1275]::bigint[],52,200,200,NULL,NULL,5),
('chan_chan','F3182','Complejo Arqueológico Chan Chan','La Libertad','property','verde',ARRAY[26,130,390,900,1100,1275]::bigint[],52,200,200,NULL,NULL,5),
('lineas_nasca','F3182','Líneas de Nasca','Ica','property','verde',ARRAY[28,150,450,1000,1200,1400]::bigint[],56,200,200,NULL,NULL,5),
('ciudad_inka_machupicchu','F3182','Ciudad Inka de Machupicchu','Cusco','property','azul',ARRAY[35,175,500,1100,1300,1500]::bigint[],70,200,200,NULL,NULL,5),
('senor_sipan','F3182','Señor de Sipán','Lambayeque','property','azul',ARRAY[50,200,600,1400,1700,2000]::bigint[],100,200,200,NULL,NULL,5),
('refugio_delfin','F3182','Refugio del Delfín Rosado del Amazonas',NULL,'railroad',NULL,ARRAY[25,50,100,200,200,200]::bigint[],NULL,NULL,NULL,NULL,NULL,1),
('refugio_colibri','F3182','Refugio del Colibrí Cola de Espátula',NULL,'railroad',NULL,ARRAY[25,50,100,200,200,200]::bigint[],NULL,NULL,NULL,NULL,NULL,1),
('refugio_oso','F3182','Refugio del Oso de Anteojos',NULL,'railroad',NULL,ARRAY[25,50,100,200,200,200]::bigint[],NULL,NULL,NULL,NULL,NULL,1),
('refugio_gallito','F3182','Refugio del Gallito de las Rocas',NULL,'railroad',NULL,ARRAY[25,50,100,200,200,200]::bigint[],NULL,NULL,NULL,NULL,NULL,1),
('reserva_titicaca','F3182','Reserva Nacional del Titicaca','Puno','utility',NULL,NULL,NULL,NULL,NULL,4,10,1),
('manglares_tumbes','F3182','Santuario Nacional Los Manglares de Tumbes','Tumbes','utility',NULL,NULL,NULL,NULL,NULL,4,10,1);

ALTER TABLE public.monopoly_f3182_titles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.monopoly_f3182_titles FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.monopoly_f3182_titles TO anon,authenticated;
CREATE POLICY f3182_titles_reference_read ON public.monopoly_f3182_titles
  FOR SELECT TO anon,authenticated USING (true);

ALTER TABLE public.room_spaces
  ADD COLUMN f3182_title_key text REFERENCES public.monopoly_f3182_titles(title_key);
CREATE UNIQUE INDEX room_spaces_unique_f3182_title
  ON public.room_spaces(room_id,f3182_title_key)
  WHERE f3182_title_key IS NOT NULL;

CREATE FUNCTION public.game_f3182_titles()
RETURNS jsonb LANGUAGE sql SECURITY INVOKER STABLE SET search_path=''
AS $body$
 SELECT coalesce(jsonb_agg(jsonb_build_object(
    'key',t.title_key,'name',t.title_name,'department',t.department,'kind',t.kind,
    'group',t.color_group,'rents',t.rent_schedule,'groupRent',t.rent_with_group,
    'buildCost',t.house_cost,'hotelCost',t.hotel_cost,
    'oneUtilityMultiplier',t.one_utility_multiplier,
    'bothUtilitiesMultiplier',t.both_utilities_multiplier,
    'price',t.purchase_price,'mortgage',t.mortgage_value,
    'position',t.board_position,'photo',t.source_photo
 ) ORDER BY CASE t.kind WHEN 'property' THEN 1 WHEN 'railroad' THEN 2 ELSE 3 END,
  CASE t.color_group WHEN 'marrón' THEN 1 WHEN 'celeste' THEN 2
   WHEN 'rosa' THEN 3 WHEN 'naranja' THEN 4 WHEN 'rojo' THEN 5
   WHEN 'amarillo' THEN 6 WHEN 'verde' THEN 7 ELSE 8 END,
  t.title_name),'[]'::jsonb)
 FROM public.monopoly_f3182_titles t WHERE t.edition_sku='F3182';
$body$;
REVOKE ALL ON FUNCTION public.game_f3182_titles() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.game_f3182_titles() TO anon,authenticated;

CREATE FUNCTION public.game_assign_f3182_title(
  p_code text,p_token text,p_position smallint,p_title_key text,
  p_purchase_price bigint DEFAULT NULL,p_mortgage_value bigint DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $body$
DECLARE v_room uuid;v_me uuid;v_role text;v_status text;
 v_title public.monopoly_f3182_titles%rowtype;
 v_space public.room_spaces%rowtype;
BEGIN
 SELECT room_id,player_id,player_role INTO v_room,v_me,v_role
   FROM game_private.member(p_code,p_token);
 IF v_me IS NULL OR v_role<>'host' THEN
   RAISE EXCEPTION 'Solo el anfitrión puede configurar propiedades'; END IF;
 SELECT status INTO v_status FROM public.rooms
   WHERE id=v_room AND edition_sku='F3182' FOR UPDATE;
 IF NOT FOUND OR v_status NOT IN ('waiting','active') THEN
   RAISE EXCEPTION 'La edición F3182 no está abierta para configurar';END IF;
 SELECT * INTO v_title FROM public.monopoly_f3182_titles WHERE title_key=p_title_key;
 IF NOT FOUND THEN RAISE EXCEPTION 'Tarjeta F3182 desconocida';END IF;
 SELECT * INTO v_space FROM public.room_spaces
   WHERE room_id=v_room AND position=p_position FOR UPDATE;
 IF NOT FOUND OR v_space.owner_id IS NOT NULL THEN
   RAISE EXCEPTION 'La casilla no está disponible para configurar';END IF;
 IF v_space.space_type<>v_title.kind THEN
   RAISE EXCEPTION 'Tipo incompatible: la casilla es %, la tarjeta es %',
       v_space.space_type,v_title.kind;END IF;
 IF v_title.kind='property' AND v_space.color_group IS DISTINCT FROM v_title.color_group THEN
   RAISE EXCEPTION 'Grupo de color incorrecto: la tarjeta es %',
     v_title.color_group;END IF;
 IF p_purchase_price IS NOT NULL AND p_purchase_price NOT BETWEEN 1 AND 10000000 THEN
   RAISE EXCEPTION 'Precio de compra inválido';END IF;
 IF p_mortgage_value IS NOT NULL AND p_mortgage_value NOT BETWEEN 1 AND 10000000 THEN
   RAISE EXCEPTION 'Valor de hipoteca inválido';END IF;
 -- No synthetic prices: NULL remains unknown until the physical board supplies one.
 UPDATE public.room_spaces SET
   name=v_title.title_name,
   color_group=v_title.color_group,
   rent_schedule=v_title.rent_schedule,
   build_cost=v_title.house_cost,
   price=p_purchase_price,
   mortgage_value=p_mortgage_value,
   f3182_title_key=v_title.title_key
 WHERE room_id=v_room AND position=p_position;
 INSERT INTO public.room_events(room_id,actor_id,event_type,payload)
 VALUES(v_room,v_me,'f3182_title_assigned',
   jsonb_build_object('position',p_position,'titleKey',v_title.title_key,
     'priceConfirmed',p_purchase_price IS NOT NULL));
 PERFORM game_private.notify(v_room);
 RETURN jsonb_build_object('ok',true,'position',p_position,'titleKey',v_title.title_key);
END;
$body$;
REVOKE ALL ON FUNCTION public.game_assign_f3182_title(text,text,smallint,text,bigint,bigint)
 FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.game_assign_f3182_title(text,text,smallint,text,bigint,bigint)
 TO anon,authenticated;

-- Manual editing overrides the catalogue binding; it must never leave a stale title association.
DO $patch$
DECLARE src text;
BEGIN
 src:=pg_get_functiondef('public.game_set_space(text,text,smallint,text,text,text,bigint,bigint[],bigint,bigint)'::regprocedure);
 IF position('set name=btrim(p_name),space_type=p_type,' IN src)=0 THEN
    RAISE EXCEPTION 'Unexpected game_set_space implementation';END IF;
 EXECUTE replace(src,
   'set name=btrim(p_name),space_type=p_type,',
   'set name=btrim(p_name),f3182_title_key=null,space_type=p_type,');
END;
$patch$;

UPDATE public.monopoly_editions
 SET notes='28 tarjetas F3182 verificadas por fotografías: 22 propiedades, 4 refugios y 2 áreas protegidas. Alquileres y costos de construcción registrados. Precios de compra, valores de hipoteca y posiciones exactas pendientes de fotos del tablero.'
 WHERE sku='F3182';
COMMIT;
