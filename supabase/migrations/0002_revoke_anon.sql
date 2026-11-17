-- Strip every privilege from `anon` on the app tables.
--
-- The migration in 0001 granted CRUD only to `authenticated`, but Postgres' default
-- schema privileges had already handed `anon` REFERENCES, TRIGGER and TRUNCATE.
-- TRUNCATE is the dangerous one: it is not subject to row level security, so an
-- anon caller could empty a table regardless of the policies on it — and the anon
-- key ships inside the app binary where anyone can read it.

revoke all on public.profiles             from anon;
revoke all on public.platform_connections from anon;
revoke all on public.playlists            from anon;
revoke all on public.playlist_tracks      from anon;
revoke all on public.taste_artists        from anon;
revoke all on public.shown_tracks         from anon;

-- Stop future tables in this schema inheriting the same defaults.
alter default privileges in schema public revoke all on tables from anon;
