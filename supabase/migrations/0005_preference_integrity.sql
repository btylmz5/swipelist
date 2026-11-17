begin;
alter table public.sw2_preferences drop constraint if exists sw2_preferences_profile_check;
alter table public.sw2_preferences add constraint sw2_preferences_profile_check check (profile ? 'source' and profile->>'source' = 'user_explicit');
create or replace function public.sw2_preferences_touch() returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end;
$$;
create trigger sw2_preferences_touch before update on public.sw2_preferences for each row execute function public.sw2_preferences_touch();
commit;
