-- Alumill TDS Generator - a proper Users table/screen
--
-- Adds the descriptive/HR fields the department column never had (full name,
-- department label, job position/title) plus an Active flag distinct from the
-- pending/approved/rejected signup status - an approved user can be suspended
-- without losing their role assignment or history. Department/Position here
-- are purely informational; the role (privilege set) is what actually
-- controls permissions.

alter table profiles add column if not exists full_name text;
alter table profiles add column if not exists department text;
alter table profiles add column if not exists position text;
alter table profiles add column if not exists active boolean not null default true;

-- Capture the full name the user typed at signup (passed via
-- supabase.auth.signUp({ options: { data: { full_name } } })).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_role_id uuid;
begin
  select id into v_role_id from roles where name = (
    case when lower(new.email) = 'nizar.a.mansour@gmail.com' then 'Super Admin' else 'Sales' end
  );
  insert into public.profiles (id, email, status, approved_at, role_id, email_confirmed, full_name)
  values (
    new.id,
    new.email,
    case when lower(new.email) = 'nizar.a.mansour@gmail.com' then 'approved' else 'pending' end,
    case when lower(new.email) = 'nizar.a.mansour@gmail.com' then now() else null end,
    v_role_id,
    (new.email_confirmed_at is not null),
    new.raw_user_meta_data ->> 'full_name'
  );
  return new;
end;
$$;

-- An inactive user must be blocked exactly like an unapproved one, everywhere
-- has_object_permission()/has_script_permission() already gate.
create or replace function public.has_object_permission(p_object_key text, p_action text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    (select case p_action
       when 'view' then can_view
       when 'create' then can_create
       when 'edit' then can_edit
       when 'delete' then can_delete
       else false
     end
     from role_object_permissions rop
     join profiles p on p.role_id = rop.role_id
     where p.id = auth.uid() and rop.object_key = p_object_key and p.status = 'approved' and p.active = true
    ), false
  );
$$;

create or replace function public.has_script_permission(p_script_key text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    (select rsp.can_run
     from role_script_permissions rsp
     join profiles p on p.role_id = rsp.role_id
     where p.id = auth.uid() and rsp.script_key = p_script_key and p.status = 'approved' and p.active = true
    ), false
  );
$$;

-- The two remaining RLS policies that check profiles.status directly (rather
-- than through the has_*_permission() helpers above) also need the active
-- check added.
drop policy if exists "approved users read app_state" on app_state;
create policy "approved users read app_state" on app_state for select
  using (exists (select 1 from profiles where id = auth.uid() and status = 'approved' and active = true));

drop policy if exists "insert own" on tds_requests;
create policy "insert own" on tds_requests for insert
  with check (
    created_by = auth.uid()
    and exists (select 1 from profiles where id = auth.uid() and status = 'approved' and active = true)
  );
