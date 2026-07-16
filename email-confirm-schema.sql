-- Alumill TDS Generator - hide unconfirmed signups from the Admin approval queue
--
-- Problem: anyone can type your email into the signup form. Supabase's built-in
-- "confirm your email" link already stops them from ever logging in (they don't
-- control your inbox), but the pending profile row still showed up in the Admin
-- approvals list immediately on signup, before anyone proved they own that inbox.
-- That's queue clutter and a light social-engineering surface ("please approve
-- nizar.a.mansour@gmail.com"), even though it was never an actual access risk.
--
-- Fix: track email confirmation on the profile row (via a trigger off
-- auth.users.email_confirmed_at) and only surface a pending signup in the Admin
-- queue once it's true.

alter table profiles add column if not exists email_confirmed boolean not null default false;

-- Backfill from whatever's already confirmed in auth.users.
update profiles p
set email_confirmed = true
from auth.users u
where p.id = u.id and u.email_confirmed_at is not null and p.email_confirmed = false;

-- Extend the signup trigger to seed email_confirmed from auth.users at insert time
-- (covers the case where a Supabase project has "Confirm email" turned off, in
-- which case email_confirmed_at is already set the moment the row is inserted).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, status, approved_at, department, email_confirmed)
  values (
    new.id,
    new.email,
    case when lower(new.email) = 'nizar.a.mansour@gmail.com' then 'approved' else 'pending' end,
    case when lower(new.email) = 'nizar.a.mansour@gmail.com' then now() else null end,
    case when lower(new.email) = 'nizar.a.mansour@gmail.com' then 'admin' else 'sales' end,
    (new.email_confirmed_at is not null)
  );
  return new;
end;
$$;

-- New trigger: flip email_confirmed the moment Supabase marks the address confirmed
-- (fires when the user clicks the confirmation link in their inbox).
create or replace function public.handle_email_confirmed()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if (old.email_confirmed_at is null and new.email_confirmed_at is not null) then
    update public.profiles set email_confirmed = true where id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_email_confirmed on auth.users;
create trigger on_auth_user_email_confirmed
  after update on auth.users
  for each row execute procedure public.handle_email_confirmed();
