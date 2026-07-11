-- Alumill TDS Generator — auth / admin-approval schema
-- Adds account-gating on top of the existing app_state / tds_records tables.

-- One row per signed-up user. Created automatically by the trigger below —
-- never insertable by the client, so a signup can't set its own status.
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  approved_by uuid references auth.users(id)
);
alter table profiles enable row level security;

drop policy if exists "select own profile" on profiles;
drop policy if exists "admin select all profiles" on profiles;
drop policy if exists "admin update profiles" on profiles;
create policy "select own profile" on profiles for select using (auth.uid() = id);
create policy "admin select all profiles" on profiles for select using (lower(auth.jwt() ->> 'email') = 'nizar.a.mansour@gmail.com');
create policy "admin update profiles" on profiles for update
  using (lower(auth.jwt() ->> 'email') = 'nizar.a.mansour@gmail.com')
  with check (lower(auth.jwt() ->> 'email') = 'nizar.a.mansour@gmail.com');

-- Auto-creates the profile row on signup. The super admin's own signup is
-- auto-approved (otherwise nobody could ever approve the first account);
-- everyone else starts 'pending' until the super admin approves them from
-- the Approvals panel in the app.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, status, approved_at)
  values (
    new.id,
    new.email,
    case when lower(new.email) = 'nizar.a.mansour@gmail.com' then 'approved' else 'pending' end,
    case when lower(new.email) = 'nizar.a.mansour@gmail.com' then now() else null end
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Tighten master-data / TDS-log access: previously anon read/write was wide
-- open (documented as a known gap). Now requires an authenticated user whose
-- profile is approved.
drop policy if exists "allow all on app_state" on app_state;
drop policy if exists "allow all on tds_records" on tds_records;

create policy "approved users all on app_state" on app_state for all
  using (exists (select 1 from profiles where id = auth.uid() and status = 'approved'))
  with check (exists (select 1 from profiles where id = auth.uid() and status = 'approved'));

create policy "approved users all on tds_records" on tds_records for all
  using (exists (select 1 from profiles where id = auth.uid() and status = 'approved'))
  with check (exists (select 1 from profiles where id = auth.uid() and status = 'approved'));
