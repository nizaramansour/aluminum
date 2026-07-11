-- Alumill TDS Generator — Supabase schema
-- Run this once in Supabase: SQL Editor > New Query > paste > Run

-- Master data (alloys, chemistry, thickness ranges, products, rules) as one JSON blob,
-- mirroring how the app already stores it in memory — low risk, no complex relational
-- schema to get wrong. Keyed by a single string (see STORAGE_KEY in index.html).
create table if not exists app_state (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

-- One row per generated TDS — the dedicated log table, independent of any order/coil record.
create table if not exists tds_records (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  ref text,
  customer text,
  alloy text,
  temper text,
  thickness_mm numeric,
  width_mm numeric,
  product text,
  units text,
  pdf_base64 text
);

-- Supabase requires Row Level Security to be explicitly enabled and policies defined,
-- or the anon key can't read/write at all.
alter table app_state enable row level security;
alter table tds_records enable row level security;

-- NOTE: these policies allow full read/write to anyone holding the anon key (which is
-- visible in the deployed site's source, by design of Supabase's anon-key model). That's
-- fine for an internal tool behind an unlisted URL, but if you want it locked down to
-- your team only, replace these with policies that check auth.uid() against a Supabase
-- Auth session instead — ask Claude to tighten this before going further if so.
create policy "allow all on app_state" on app_state for all using (true) with check (true);
create policy "allow all on tds_records" on tds_records for all using (true) with check (true);
