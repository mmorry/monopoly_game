-- Monopoly Perú database schema verification
-- Version: 002
-- Execute manually in Supabase SQL Editor only after 001_initial_rooms.sql.
-- Read-only checks: this script does not create, update, or delete data.

-- Expected: two rows, both with rowsecurity = true.
select c.relname as table_name, c.relrowsecurity as row_security_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('rooms', 'room_players')
order by c.relname;

-- Expected: the named constraints for keys, lifecycle, aliases, roles, and statuses.
select conrelid::regclass as table_name, conname as constraint_name, contype as constraint_type
from pg_constraint
where conrelid in ('public.rooms'::regclass, 'public.room_players'::regclass)
order by table_name, constraint_name;

-- Expected: the indexes declared in 001, including the partial unique indexes.
select tablename, indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename in ('rooms', 'room_players')
order by tablename, indexname;

-- Expected: no table privileges for anon or authenticated.
select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('rooms', 'room_players')
  and grantee in ('anon', 'authenticated')
order by grantee, table_name, privilege_type;
