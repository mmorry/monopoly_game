-- Monopoly Perú secure room creation prerequisites
-- Version: 003
-- REVIEW ONLY: execute manually in Supabase SQL Editor after approval.
-- Prerequisite: 001_initial_rooms.sql has been applied.

begin;

-- The endpoint receives a high-entropy host recovery credential once and stores
-- only its HMAC-SHA-256 digest. It must never persist the plaintext credential.
alter table public.rooms
  add column host_credential_hash bytea not null;

alter table public.rooms
  add constraint rooms_host_credential_hash_length_check
  check (octet_length(host_credential_hash) = 32);

-- Browser sessions are opaque, revocable capabilities. The cookie value is never
-- stored: only its HMAC-SHA-256 digest is persisted.
create table public.room_host_sessions (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null,
  session_token_hash bytea not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  last_seen_at timestamptz,
  revoked_at timestamptz,

  constraint room_host_sessions_room_id_fkey
    foreign key (room_id)
    references public.rooms (id)
    on delete cascade,
  constraint room_host_sessions_token_hash_length_check
    check (octet_length(session_token_hash) = 32),
  constraint room_host_sessions_expiry_check
    check (expires_at > created_at),
  constraint room_host_sessions_last_seen_check
    check (last_seen_at is null or last_seen_at >= created_at),
  constraint room_host_sessions_revoked_check
    check (revoked_at is null or revoked_at >= created_at)
);

create unique index room_host_sessions_token_hash_key
  on public.room_host_sessions (session_token_hash);

create index room_host_sessions_active_room_idx
  on public.room_host_sessions (room_id, expires_at)
  where revoked_at is null;

-- Keep the new table closed to all browser roles until a future, reviewed access
-- model requires narrowly scoped policies. The Vercel endpoint uses a private
-- server-only database connection instead of client grants.
alter table public.room_host_sessions enable row level security;

revoke all on table public.room_host_sessions from anon, authenticated;

commit;
