-- Alumill TDS Generator - generic, FileMaker-style permission system
--
-- Replaces the fixed department enum with:
--   roles                    privilege sets (Super Admin, QC Manager, ...)
--   permission_objects       registry of protectable "tables" and "scripts"
--   role_object_permissions  view/create/edit/delete per role x data object
--   role_script_permissions  can_run per role x script (buttons/actions that
--                            aren't simple CRUD, e.g. Verify TDS)
--   role_field_permissions   section-level visibility within a data object
--                            (this app's master data lives in one JSON blob,
--                            not separate physical tables, so "fields" here
--                            map to the Products/Rules/Alloy Properties
--                            sections rather than literal input boxes)
-- profiles.role_id replaces profiles.department.
--
-- Going forward: adding a user, a role, or changing who can do what is a pure
-- data edit via the Admin > Roles & Permissions screen - no code changes.
-- Only inventing a genuinely new feature/table/script still needs a registry
-- row added (one INSERT) plus that feature's own generic permission check.

create table if not exists roles (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_system boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists permission_objects (
  key text primary key,
  label text not null,
  kind text not null check (kind in ('data','script')),
  description text
);

create table if not exists role_object_permissions (
  role_id uuid not null references roles(id) on delete cascade,
  object_key text not null references permission_objects(key) on delete cascade,
  can_view boolean not null default false,
  can_create boolean not null default false,
  can_edit boolean not null default false,
  can_delete boolean not null default false,
  primary key (role_id, object_key)
);

create table if not exists role_script_permissions (
  role_id uuid not null references roles(id) on delete cascade,
  script_key text not null references permission_objects(key) on delete cascade,
  can_run boolean not null default false,
  primary key (role_id, script_key)
);

create table if not exists role_field_permissions (
  role_id uuid not null references roles(id) on delete cascade,
  object_key text not null references permission_objects(key) on delete cascade,
  field_key text not null,
  visible boolean not null default true,
  primary key (role_id, object_key, field_key)
);

alter table profiles add column if not exists role_id uuid references roles(id);

-- ---- seed roles ----
insert into roles (name, is_system) values
  ('Super Admin', true),
  ('QC Manager', false),
  ('QC Inspector', false),
  ('Production Manager', false),
  ('Production Inspector', false),
  ('Sales', false)
on conflict (name) do nothing;

-- ---- seed the object/script registry ----
insert into permission_objects (key, label, kind, description) values
  ('master_data', 'Master Data (Products, Rules, Alloy Properties)', 'data', 'The shared alloy/product/rule library used to generate a TDS.'),
  ('tds_requests', 'TDS Requests', 'data', 'Submitted TDS requests and their status.'),
  ('verify_tds', 'Verify / Reject TDS Request', 'script', 'Sign off on or reject a pending TDS request.'),
  ('reset_master_data', 'Reset Master Data to Factory Defaults', 'script', 'Destructive - wipes edits back to the built-in defaults.'),
  ('manage_roles', 'Manage Roles & Permissions', 'script', 'Create/edit roles and the permission matrix itself.'),
  ('manage_users', 'Manage Users', 'script', 'Approve/reject signups and assign roles.')
on conflict (key) do nothing;

-- ---- seed the permission matrix, matching the agreed table ----
insert into role_object_permissions (role_id, object_key, can_view, can_create, can_edit, can_delete)
select r.id, o.object_key, o.can_view, o.can_create, o.can_edit, o.can_delete
from (values
  ('Super Admin','master_data', true, true, true, true),
  ('Super Admin','tds_requests', true, true, true, true),
  ('QC Manager','master_data', true, true, true, true),
  ('QC Manager','tds_requests', true, true, false, false),
  ('QC Inspector','master_data', true, false, false, false),
  ('QC Inspector','tds_requests', true, true, false, false),
  ('Production Manager','master_data', true, false, false, false),
  ('Production Manager','tds_requests', true, true, false, false),
  ('Production Inspector','master_data', true, false, false, false),
  ('Production Inspector','tds_requests', true, true, false, false),
  ('Sales','master_data', true, false, false, false),
  ('Sales','tds_requests', true, true, false, false)
) as o(role_name, object_key, can_view, can_create, can_edit, can_delete)
join roles r on r.name = o.role_name
on conflict (role_id, object_key) do update set
  can_view = excluded.can_view, can_create = excluded.can_create,
  can_edit = excluded.can_edit, can_delete = excluded.can_delete;

insert into role_script_permissions (role_id, script_key, can_run)
select r.id, s.script_key, s.can_run
from (values
  ('Super Admin','verify_tds', true),
  ('Super Admin','reset_master_data', true),
  ('Super Admin','manage_roles', true),
  ('Super Admin','manage_users', true),
  ('QC Manager','verify_tds', true),
  ('QC Manager','reset_master_data', true),
  ('Production Manager','verify_tds', true)
) as s(role_name, script_key, can_run)
join roles r on r.name = s.role_name
on conflict (role_id, script_key) do update set can_run = excluded.can_run;

-- ---- seed field-level visibility for master_data: everyone with view access
-- on master_data can see all three sections by default; the super admin can
-- narrow this per role from the Roles & Permissions screen. ----
insert into role_field_permissions (role_id, object_key, field_key, visible)
select rop.role_id, 'master_data', f.field_key, true
from role_object_permissions rop
cross join (values ('products'), ('rules'), ('alloy_properties')) as f(field_key)
where rop.object_key = 'master_data' and rop.can_view = true
on conflict (role_id, object_key, field_key) do nothing;

-- ---- migrate existing profiles.department -> role_id ----
update profiles set role_id = (select id from roles where name = 'Super Admin') where department = 'admin' and role_id is null;
update profiles set role_id = (select id from roles where name = 'QC Manager') where department = 'qc' and role_id is null;
update profiles set role_id = (select id from roles where name = 'Production Manager') where department = 'production' and role_id is null;
update profiles set role_id = (select id from roles where name = 'Sales') where department = 'sales' and role_id is null;
update profiles set role_id = (select id from roles where name = 'Sales') where role_id is null;

alter table profiles alter column role_id set not null;

-- Drop every policy that still reads profiles.department BEFORE dropping the
-- column itself, or Postgres refuses (dependent objects).
drop policy if exists "qc admin write app_state" on app_state;
drop policy if exists "qc admin update app_state" on app_state;
drop policy if exists "select own or reviewer" on tds_requests;
drop policy if exists "update by reviewer or own" on tds_requests;

alter table profiles drop column if exists department;

-- ---- update the signup trigger: bootstrap the super admin's role, default
-- everyone else to Sales (least-privileged, matches the old default). ----
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
  insert into public.profiles (id, email, status, approved_at, role_id, email_confirmed)
  values (
    new.id,
    new.email,
    case when lower(new.email) = 'nizar.a.mansour@gmail.com' then 'approved' else 'pending' end,
    case when lower(new.email) = 'nizar.a.mansour@gmail.com' then now() else null end,
    v_role_id,
    (new.email_confirmed_at is not null)
  );
  return new;
end;
$$;

-- ---- generic permission-check helpers, used by RLS policies. security
-- definer so they can read profiles/role_*_permissions regardless of the
-- calling user's own row-level access (avoids policy recursion). ----
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
     where p.id = auth.uid() and rop.object_key = p_object_key and p.status = 'approved'
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
     where p.id = auth.uid() and rsp.script_key = p_script_key and p.status = 'approved'
    ), false
  );
$$;

-- ---- rewrite RLS policies to use the generic helpers instead of department ----
drop policy if exists "qc admin write app_state" on app_state;
drop policy if exists "qc admin update app_state" on app_state;
create policy "object perm write app_state" on app_state for insert
  with check (public.has_object_permission('master_data','edit'));
create policy "object perm update app_state" on app_state for update
  using (public.has_object_permission('master_data','edit'))
  with check (public.has_object_permission('master_data','edit'));

drop policy if exists "select own or reviewer" on tds_requests;
drop policy if exists "update by reviewer or own" on tds_requests;
create policy "select own or reviewer" on tds_requests for select
  using (created_by = auth.uid() or public.has_script_permission('verify_tds'));
create policy "update by reviewer or own" on tds_requests for update
  using (created_by = auth.uid() or public.has_script_permission('verify_tds'))
  with check (created_by = auth.uid() or public.has_script_permission('verify_tds'));

-- roles / permission_objects / role_*_permissions: readable by any approved
-- user (the app needs its own permission map to render), writable only by
-- someone with the manage_roles script permission (or the hardcoded super
-- admin email, kept as an unconditional bootstrap safety valve).
alter table roles enable row level security;
alter table permission_objects enable row level security;
alter table role_object_permissions enable row level security;
alter table role_script_permissions enable row level security;
alter table role_field_permissions enable row level security;

drop policy if exists "approved read roles" on roles;
create policy "approved read roles" on roles for select
  using (exists (select 1 from profiles where id = auth.uid() and status = 'approved'));
drop policy if exists "manage_roles write roles" on roles;
create policy "manage_roles write roles" on roles for all
  using (public.has_script_permission('manage_roles') or lower(auth.jwt() ->> 'email') = 'nizar.a.mansour@gmail.com')
  with check (public.has_script_permission('manage_roles') or lower(auth.jwt() ->> 'email') = 'nizar.a.mansour@gmail.com');

drop policy if exists "approved read permission_objects" on permission_objects;
create policy "approved read permission_objects" on permission_objects for select
  using (exists (select 1 from profiles where id = auth.uid() and status = 'approved'));
drop policy if exists "manage_roles write permission_objects" on permission_objects;
create policy "manage_roles write permission_objects" on permission_objects for all
  using (public.has_script_permission('manage_roles') or lower(auth.jwt() ->> 'email') = 'nizar.a.mansour@gmail.com')
  with check (public.has_script_permission('manage_roles') or lower(auth.jwt() ->> 'email') = 'nizar.a.mansour@gmail.com');

drop policy if exists "approved read role_object_permissions" on role_object_permissions;
create policy "approved read role_object_permissions" on role_object_permissions for select
  using (exists (select 1 from profiles where id = auth.uid() and status = 'approved'));
drop policy if exists "manage_roles write role_object_permissions" on role_object_permissions;
create policy "manage_roles write role_object_permissions" on role_object_permissions for all
  using (public.has_script_permission('manage_roles') or lower(auth.jwt() ->> 'email') = 'nizar.a.mansour@gmail.com')
  with check (public.has_script_permission('manage_roles') or lower(auth.jwt() ->> 'email') = 'nizar.a.mansour@gmail.com');

drop policy if exists "approved read role_script_permissions" on role_script_permissions;
create policy "approved read role_script_permissions" on role_script_permissions for select
  using (exists (select 1 from profiles where id = auth.uid() and status = 'approved'));
drop policy if exists "manage_roles write role_script_permissions" on role_script_permissions;
create policy "manage_roles write role_script_permissions" on role_script_permissions for all
  using (public.has_script_permission('manage_roles') or lower(auth.jwt() ->> 'email') = 'nizar.a.mansour@gmail.com')
  with check (public.has_script_permission('manage_roles') or lower(auth.jwt() ->> 'email') = 'nizar.a.mansour@gmail.com');

drop policy if exists "approved read role_field_permissions" on role_field_permissions;
create policy "approved read role_field_permissions" on role_field_permissions for select
  using (exists (select 1 from profiles where id = auth.uid() and status = 'approved'));
drop policy if exists "manage_roles write role_field_permissions" on role_field_permissions;
create policy "manage_roles write role_field_permissions" on role_field_permissions for all
  using (public.has_script_permission('manage_roles') or lower(auth.jwt() ->> 'email') = 'nizar.a.mansour@gmail.com')
  with check (public.has_script_permission('manage_roles') or lower(auth.jwt() ->> 'email') = 'nizar.a.mansour@gmail.com');

-- protect system roles (Super Admin) from deletion
create or replace function public.prevent_system_role_delete()
returns trigger
language plpgsql
as $$
begin
  if old.is_system then
    raise exception 'Cannot delete a system role.';
  end if;
  return old;
end;
$$;
drop trigger if exists protect_system_roles on roles;
create trigger protect_system_roles
  before delete on roles
  for each row execute procedure public.prevent_system_role_delete();

-- ---- extend user management beyond the hardcoded super admin email: anyone
-- with manage_users can also approve/reject signups and assign roles. ----
drop policy if exists "manage_users update profiles" on profiles;
create policy "manage_users update profiles" on profiles for update
  using (public.has_script_permission('manage_users'))
  with check (public.has_script_permission('manage_users'));

drop policy if exists "manage_users select all profiles" on profiles;
create policy "manage_users select all profiles" on profiles for select
  using (public.has_script_permission('manage_users'));
