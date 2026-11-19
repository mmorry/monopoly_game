-- Monopoly Perú | Version 007 | CSPRNG qualification with empty search_path
-- Supabase installs pgcrypto's gen_random_bytes() in extensions schema.
-- Replaces only installed function bodies; keeps grants/signatures unchanged.
begin;
do $fix$
declare fn regprocedure; definition text;
begin
  foreach fn in array array[
    'public.game_create_room(text,text,smallint,text,bigint,bigint,bigint)'::regprocedure,
    'public.game_join_room(text,text)'::regprocedure,
    'public.game_recover_host(text,text)'::regprocedure
  ]
  loop
    definition := pg_get_functiondef(fn::oid);
    if position('extensions.gen_random_bytes' in definition)=0 then
      definition := replace(definition,'gen_random_bytes(', 'extensions.gen_random_bytes(');
      execute definition;
    end if;
  end loop;
end;
$fix$;
commit;