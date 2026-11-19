-- Monopoly Perú host recovery credential security
-- Version: 004
-- REVIEW ONLY: execute manually in Supabase SQL Editor after approval.
-- Prerequisites: 001_initial_rooms.sql and 003_create_room.sql are applied.
-- This version intentionally aborts if rooms already exist; use a reviewed data
-- migration instead of applying credential defaults to live rooms.

begin;

do $$
begin
  if exists (select 1 from public.rooms) then
    raise exception '004_host_security.sql requires public.rooms to be empty';
  end if;
end;
$$;

alter table public.rooms
  add column host_credential_issued_at timestamptz not null default now(),
  add column host_credential_expires_at timestamptz not null default (now() + interval '24 hours'),
  add column host_credential_revoked_at timestamptz;

alter table public.rooms
  add constraint rooms_host_credential_expiry_check
    check (host_credential_expires_at > host_credential_issued_at),
  add constraint rooms_host_credential_revoked_check
    check (
      host_credential_revoked_at is null
      or host_credential_revoked_at >= host_credential_issued_at
    );

-- Supports server-side cleanup and checks for credentials that are still eligible
-- for recovery. The endpoint must also compare the HMAC digest and room status.
create index rooms_active_host_credential_expiry_idx
  on public.rooms (host_credential_expires_at)
  where host_credential_revoked_at is null;

-- Reassert the closed client-access posture established in versions 001 and 003.
alter table public.rooms enable row level security;
alter table public.room_host_sessions enable row level security;

revoke all on table public.rooms from anon, authenticated;
revoke all on table public.room_host_sessions from anon, authenticated;

commit;

-- Post-application verification queries. These are read-only.
-- Expected: issued_at and expires_at are non-nullable; revoked_at is nullable.
select column_name, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'rooms'
  and column_name in (
    'host_credential_issued_at',
    'host_credential_expires_at',
    'host_credential_revoked_at'
  )
order by column_name;

-- Expected: both credential lifecycle constraints and the active-expiry index.
select conname as constraint_name
from pg_constraint
where conrelid = 'public.rooms'::regclass
  and conname in (
    'rooms_host_credential_expiry_check',
    'rooms_host_credential_revoked_check'
  )
order by conname;

select indexname
from pg_indexes
where schemaname = 'public'
  and tablename = 'rooms'
  and indexname = 'rooms_active_host_credential_expiry_idx';

-- Expected: both tables retain RLS and client roles hold no table privileges.
select c.relname as table_name, c.relrowsecurity as row_security_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('rooms', 'room_host_sessions')
order by c.relname;

select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('rooms', 'room_host_sessions')
  and grantee in ('anon', 'authenticated')
order by grantee, table_name, privilege_type;
