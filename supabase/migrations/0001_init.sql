-- Swipelist schema.
--
-- Every table is owned by a user and readable only by that user. RLS is the only
-- thing standing between a row and the anon key, which ships inside the app, so
-- each table denies by default and is opened up one policy at a time.
--
-- "Automatically expose new tables" is off on this project, so access is granted
-- explicitly rather than inherited.

-- ─────────────────────────────────────────────────────────────
-- profiles
-- ─────────────────────────────────────────────────────────────

create table if not exists public.profiles (
    id           uuid primary key references auth.users (id) on delete cascade,
    display_name text,
    created_at   timestamptz not null default now()
);

comment on table public.profiles is 'One row per account, created automatically on signup.';

-- ─────────────────────────────────────────────────────────────
-- platform_connections — linked music services
-- ─────────────────────────────────────────────────────────────

create table if not exists public.platform_connections (
    id               uuid primary key default gen_random_uuid(),
    user_id          uuid not null references auth.users (id) on delete cascade,
    provider         text not null check (provider in ('spotify', 'apple_music', 'deezer')),
    external_user_id text,
    display_name     text,
    access_token     text,
    refresh_token    text,
    expires_at       timestamptz,
    scopes           text,
    connected_at     timestamptz not null default now(),
    unique (user_id, provider)
);

comment on table public.platform_connections is
    'OAuth credentials per linked service. Readable only by the owning user. '
    'Hardening path: move reads behind an Edge Function using the service role so '
    'refresh tokens never reach the device at all.';

-- ─────────────────────────────────────────────────────────────
-- playlists + tracks
-- ─────────────────────────────────────────────────────────────

create table if not exists public.playlists (
    id                   uuid primary key default gen_random_uuid(),
    user_id              uuid not null references auth.users (id) on delete cascade,
    name                 text not null,
    brief_text           text,
    brief_energy         text,
    brief_occasion       text,
    exported_provider    text,
    external_playlist_id text,
    created_at           timestamptz not null default now()
);

create index if not exists playlists_user_created_idx
    on public.playlists (user_id, created_at desc);

create table if not exists public.playlist_tracks (
    id           uuid primary key default gen_random_uuid(),
    playlist_id  uuid not null references public.playlists (id) on delete cascade,
    position     integer not null,
    title        text not null,
    artist       text not null,
    album        text,
    release_year text,
    artwork_url  text,
    preview_url  text,
    provider     text,
    provider_uri text,
    unique (playlist_id, position)
);

create index if not exists playlist_tracks_playlist_idx
    on public.playlist_tracks (playlist_id, position);

-- ─────────────────────────────────────────────────────────────
-- taste_artists — the feedback loop, persisted across sessions
-- ─────────────────────────────────────────────────────────────

create table if not exists public.taste_artists (
    user_id       uuid not null references auth.users (id) on delete cascade,
    artist_key    text not null,
    artist_name   text not null,
    kept_count    integer not null default 0,
    skipped_count integer not null default 0,
    updated_at    timestamptz not null default now(),
    primary key (user_id, artist_key)
);

comment on table public.taste_artists is
    'Kept/skipped counts per lead artist. Lets a new session start from known taste '
    'instead of cold.';

-- ─────────────────────────────────────────────────────────────
-- shown_tracks — never show the same song twice
-- ─────────────────────────────────────────────────────────────

create table if not exists public.shown_tracks (
    user_id   uuid not null references auth.users (id) on delete cascade,
    track_key text not null,
    shown_at  timestamptz not null default now(),
    primary key (user_id, track_key)
);

comment on table public.shown_tracks is
    'Folded "artist|title" of every card shown, so decks never repeat across sessions.';

-- ─────────────────────────────────────────────────────────────
-- Row level security
-- ─────────────────────────────────────────────────────────────

alter table public.profiles             enable row level security;
alter table public.platform_connections enable row level security;
alter table public.playlists            enable row level security;
alter table public.playlist_tracks      enable row level security;
alter table public.taste_artists        enable row level security;
alter table public.shown_tracks         enable row level security;

-- Owner-only access, one policy per table.
create policy "own profile" on public.profiles
    for all using (auth.uid() = id) with check (auth.uid() = id);

create policy "own connections" on public.platform_connections
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own playlists" on public.playlists
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Tracks inherit ownership through their playlist.
create policy "own playlist tracks" on public.playlist_tracks
    for all
    using (exists (
        select 1 from public.playlists p
        where p.id = playlist_tracks.playlist_id and p.user_id = auth.uid()
    ))
    with check (exists (
        select 1 from public.playlists p
        where p.id = playlist_tracks.playlist_id and p.user_id = auth.uid()
    ));

create policy "own taste" on public.taste_artists
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own shown tracks" on public.shown_tracks
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────
-- Grants — signed-in users only. anon gets nothing.
-- ─────────────────────────────────────────────────────────────

grant select, insert, update, delete on
    public.profiles,
    public.platform_connections,
    public.playlists,
    public.playlist_tracks,
    public.taste_artists,
    public.shown_tracks
to authenticated;

-- ─────────────────────────────────────────────────────────────
-- Create a profile row automatically on signup
-- ─────────────────────────────────────────────────────────────

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.profiles (id, display_name)
    values (
        new.id,
        coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name')
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();
