-- Aaradhya's Homoeopathy
-- Fix: permission denied for table public.profiles
-- Run this once in Supabase SQL Editor.

-- The browser/authenticated role needs table privileges in addition to RLS.
grant usage on schema public to authenticated;
grant select, update on public.profiles to authenticated;

-- Keep the profiles table locked down by RLS.
alter table public.profiles enable row level security;

drop policy if exists "profiles own select" on public.profiles;
create policy "profiles own select"
on public.profiles
for select
to authenticated
using (
  id = auth.uid()
  or public.current_profile_role() = 'admin'
);

drop policy if exists "profiles own update" on public.profiles;
create policy "profiles own update"
on public.profiles
for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

-- The role helper is called from RLS policies.
create or replace function public.current_profile_role()
returns text
language sql
security definer
set search_path = public
stable
as $$
  select role
  from public.profiles
  where id = auth.uid();
$$;

revoke all on function public.current_profile_role() from public;
grant execute on function public.current_profile_role() to authenticated;

-- Ensure the function owner can read profiles even when RLS is enabled.
alter function public.current_profile_role() owner to postgres;
