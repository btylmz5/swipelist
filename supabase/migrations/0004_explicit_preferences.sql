-- Separate from all Spotify-derived data and Swipelist3 tables.
begin;
create table if not exists public.sw2_preferences (
 user_id uuid primary key references auth.users(id) on delete cascade,
 profile jsonb not null check (profile ? 'source' and profile->>'source' = 'user_explicit'),
 updated_at timestamptz not null default now()
);
create table if not exists public.sw2_feedback (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 candidate_id text not null check (length(candidate_id) between 1 and 100),
 brief text not null check (length(brief) between 1 and 3000),
 verdict text not null check (verdict in ('keep','skip','off_brief','dislike','known')),
 created_at timestamptz not null default now()
);
alter table public.sw2_preferences enable row level security;
alter table public.sw2_feedback enable row level security;
revoke all on public.sw2_preferences, public.sw2_feedback from anon;
grant select,insert,update,delete on public.sw2_preferences, public.sw2_feedback to authenticated;
create policy sw2_preferences_owner on public.sw2_preferences for all to authenticated using (auth.uid()=user_id) with check (auth.uid()=user_id);
create policy sw2_feedback_owner on public.sw2_feedback for all to authenticated using (auth.uid()=user_id) with check (auth.uid()=user_id);
create index sw2_feedback_user_time on public.sw2_feedback(user_id,created_at desc);
commit;
