-- Alumill TDS Generator — department roles + submit/verify workflow schema

-- Departments drive feature-level permissions: only QC (and the super admin) can
-- edit master data; QC or Production can verify a submitted TDS request. New
-- signups default to 'sales' (the most common self-serve case) until the super
-- admin reassigns them.
alter table profiles add column if not exists department text not null default 'sales'
  check (department in ('sales','qc','production','admin'));

-- Auto-approve + auto-department the super admin on signup (extends the existing
-- approval trigger). Everyone else starts 'sales' + 'pending' as before.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, status, approved_at, department)
  values (
    new.id,
    new.email,
    case when lower(new.email) = 'nizar.a.mansour@gmail.com' then 'approved' else 'pending' end,
    case when lower(new.email) = 'nizar.a.mansour@gmail.com' then now() else null end,
    case when lower(new.email) = 'nizar.a.mansour@gmail.com' then 'admin' else 'sales' end
  );
  return new;
end;
$$;

-- Only the super admin can change a profile's department/status (already covered by
-- the existing "admin update profiles" policy — department just rides along as
-- another column on the same row).

-- TDS requests: Sales (or anyone) submits, QC/Production/Admin verify or reject,
-- and only a verified request can be printed. snapshot holds the FULL resolved
-- sheet — alloy label/standard/chemistry, temper, the matched thickness band
-- (tensile/yield/elongation/bend + verified flag), thickness/width tolerances, and
-- every matching remark row — exactly as computed at submission time, so a later
-- master-data edit never changes an already-submitted/verified/printed sheet.
create table if not exists tds_requests (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  created_by_email text not null,
  ref text,
  customer text,
  product text,
  alloy_label text,
  temper text,
  thickness_mm numeric,
  width_mm numeric,
  units text,
  status text not null default 'pending' check (status in ('pending','verified','rejected')),
  verified_by uuid references auth.users(id),
  verified_by_email text,
  verified_at timestamptz,
  rejection_reason text,
  snapshot jsonb not null,
  printed_at timestamptz,
  pdf_base64 text
);
alter table tds_requests enable row level security;

drop policy if exists "select own or reviewer" on tds_requests;
drop policy if exists "insert own" on tds_requests;
drop policy if exists "update by reviewer or own" on tds_requests;

-- Everyone approved can see their own requests; QC/Production/Admin can see every
-- request (needed for the verification queue and for audit).
create policy "select own or reviewer" on tds_requests for select
  using (
    created_by = auth.uid()
    or exists (select 1 from profiles where id = auth.uid() and status = 'approved' and department in ('qc','production','admin'))
  );
-- Any approved user can submit a request, only as themselves.
create policy "insert own" on tds_requests for insert
  with check (
    created_by = auth.uid()
    and exists (select 1 from profiles where id = auth.uid() and status = 'approved')
  );
-- The submitter can update their own row (to record printed_at/pdf_base64 once
-- verified); QC/Production/Admin can update any row (to verify/reject it).
create policy "update by reviewer or own" on tds_requests for update
  using (
    created_by = auth.uid()
    or exists (select 1 from profiles where id = auth.uid() and status = 'approved' and department in ('qc','production','admin'))
  )
  with check (
    created_by = auth.uid()
    or exists (select 1 from profiles where id = auth.uid() and status = 'approved' and department in ('qc','production','admin'))
  );

-- Tighten app_state: every approved user still needs to READ master data (to fill
-- out a TDS request), but only QC/Admin should be able to WRITE it.
drop policy if exists "approved users all on app_state" on app_state;
create policy "approved users read app_state" on app_state for select
  using (exists (select 1 from profiles where id = auth.uid() and status = 'approved'));
create policy "qc admin write app_state" on app_state for insert
  with check (exists (select 1 from profiles where id = auth.uid() and status = 'approved' and department in ('qc','admin')));
create policy "qc admin update app_state" on app_state for update
  using (exists (select 1 from profiles where id = auth.uid() and status = 'approved' and department in ('qc','admin')))
  with check (exists (select 1 from profiles where id = auth.uid() and status = 'approved' and department in ('qc','admin')));
