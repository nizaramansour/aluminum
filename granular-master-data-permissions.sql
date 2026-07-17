-- Alumill TDS Generator - split master_data into per-table permissions
--
-- Products, Alloy Properties, and Conditions & Remarks Rules were one
-- combined "master_data" permission object with a single Edit flag - a role
-- could edit ALL of them or NONE, even though a user may need rights to one
-- table but not another (e.g. edit Products but never touch Alloy
-- Properties). This splits them into three real permission objects, each
-- with its own View/Create/Edit/Delete, and adds a database trigger that
-- checks WHICH part of the underlying app_state JSON actually changed on
-- every save - so a role without rights to a section genuinely cannot get a
-- change to it through, even though all three still live in one JSON row
-- (DATA = { products, alloys, rules }, saved as one app_state row - this
-- app was never built on separate physical tables per section).

insert into permission_objects (key, label, kind, description) values
  ('products', 'Products', 'data', 'The Product Type options offered on the TDS Generator form.'),
  ('rules', 'Conditions & Remarks Rules', 'data', 'Product/Alloy/Temper/Thickness/Width-based remark rules.'),
  ('alloy_properties', 'Alloy Properties', 'data', 'Chemistry, tempers, and thickness bands per alloy.')
on conflict (key) do nothing;

-- Carry over each role's existing master_data rights to all three new
-- objects as a starting point - View also folds in the old per-section field
-- visibility toggle, so nothing regresses on migration. The super admin can
-- now split these apart per role from Admin > Roles & Permissions.
insert into role_object_permissions (role_id, object_key, can_view, can_create, can_edit, can_delete)
select rop.role_id, obj.key,
  coalesce(rfp.visible, rop.can_view),
  rop.can_create, rop.can_edit, rop.can_delete
from role_object_permissions rop
cross join (values ('products'),('rules'),('alloy_properties')) as obj(key)
left join role_field_permissions rfp
  on rfp.role_id = rop.role_id and rfp.object_key = 'master_data' and rfp.field_key = obj.key
where rop.object_key = 'master_data'
on conflict (role_id, object_key) do update set
  can_view = excluded.can_view, can_create = excluded.can_create,
  can_edit = excluded.can_edit, can_delete = excluded.can_delete;

-- Retire the old combined object and the now-superseded field-level table.
delete from role_object_permissions where object_key = 'master_data';
delete from permission_objects where key = 'master_data';
drop table if exists role_field_permissions;

-- Broaden the RLS gate to "some edit right on at least one of the three
-- tables" - the trigger below is what actually enforces per-section rights.
drop policy if exists "object perm write app_state" on app_state;
drop policy if exists "object perm update app_state" on app_state;
create policy "object perm write app_state" on app_state for insert
  with check (
    public.has_object_permission('products','edit')
    or public.has_object_permission('rules','edit')
    or public.has_object_permission('alloy_properties','edit')
  );
create policy "object perm update app_state" on app_state for update
  using (
    public.has_object_permission('products','edit')
    or public.has_object_permission('rules','edit')
    or public.has_object_permission('alloy_properties','edit')
  )
  with check (
    public.has_object_permission('products','edit')
    or public.has_object_permission('rules','edit')
    or public.has_object_permission('alloy_properties','edit')
  );

-- Per-section enforcement: on every update to the master-data row, only the
-- parts of the JSON that actually changed need edit rights on that table -
-- this is what makes "edit Products but not Alloy Properties" a real,
-- database-enforced boundary rather than just a UI toggle.
create or replace function public.check_master_data_section_permissions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.key <> 'alumill-master-data-v1' then
    return new;
  end if;
  if (old.value -> 'products') is distinct from (new.value -> 'products')
     and not public.has_object_permission('products','edit') then
    raise exception 'Not permitted to edit Products';
  end if;
  if (old.value -> 'rules') is distinct from (new.value -> 'rules')
     and not public.has_object_permission('rules','edit') then
    raise exception 'Not permitted to edit Conditions & Remarks Rules';
  end if;
  if (old.value -> 'alloys') is distinct from (new.value -> 'alloys')
     and not public.has_object_permission('alloy_properties','edit') then
    raise exception 'Not permitted to edit Alloy Properties';
  end if;
  return new;
end;
$$;
drop trigger if exists guard_master_data_sections on app_state;
create trigger guard_master_data_sections
  before update on app_state
  for each row execute procedure public.check_master_data_section_permissions();
