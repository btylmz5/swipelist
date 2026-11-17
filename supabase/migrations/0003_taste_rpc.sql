-- Increment taste counters server-side.
--
-- A read-modify-write from the client would lose swipes whenever two land close
-- together, and would need a SELECT round trip per card. This does it atomically
-- in one call.

create or replace function public.bump_taste(
    p_artist_key  text,
    p_artist_name text,
    p_kept        boolean
)
returns void
language plpgsql
security invoker            -- runs as the caller, so RLS still applies
set search_path = public
as $$
begin
    insert into public.taste_artists (user_id, artist_key, artist_name, kept_count, skipped_count)
    values (
        auth.uid(),
        p_artist_key,
        p_artist_name,
        case when p_kept then 1 else 0 end,
        case when p_kept then 0 else 1 end
    )
    on conflict (user_id, artist_key) do update
        set kept_count    = taste_artists.kept_count    + case when p_kept then 1 else 0 end,
            skipped_count = taste_artists.skipped_count + case when p_kept then 0 else 1 end,
            artist_name   = excluded.artist_name,
            updated_at    = now();
end;
$$;

revoke all on function public.bump_taste(text, text, boolean) from public, anon;
grant execute on function public.bump_taste(text, text, boolean) to authenticated;
