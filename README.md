# Alumill TDS Generator

Interactive Technical Data Sheet generator, alloy comparator, and admin-editable
master data system for Alumill Tech Gulf LLC's aluminium coil/sheet products.

Single-file web app (`index.html`) — no build step, no framework. Runs standalone
in any browser, and auto-upgrades its storage/integration layer depending on where
it's deployed (see **Integration modes** below).

## Features

- **TDS Generator** — Sales picks product, alloy, temper, thickness (mm), width (mm),
  units (metric/imperial/both) and submits for verification; tensile/yield/elongation/
  bend are looked up from that alloy+temper's own thickness bands, plus ANSI H35.2
  dimensional tolerances and condition-based remarks (e.g. tension-leveling flatness
  rules, slit-coil edge-ripple notes by width). See **The submit → verify → print
  workflow** below — it no longer prints directly.
- **Alloy Comparator** — pick any alloy + temper combination, add to a comparison
  list, generates a side-by-side mechanical/chemical properties sheet (no dimensional
  tolerances); prints directly, unaffected by the workflow above.
- **Admin tab** (role-permission-gated, see **Roles & permissions** below) — edit
  Products, Conditions & Remarks Rules, and the full Alloys/Chemistry/Thickness-Bands
  library, all from the browser. Every alloy/temper block is independently collapsible.
- **Client-side PDF export** — via html2canvas + jsPDF, downloads directly; no print
  dialog dependency (important since print() is unreliable inside sandboxed iframes).

## Tech stack

- Plain HTML/CSS/JS, single file, no build tooling
- [html2canvas](https://html2canvas.hertzen.com/) + [jsPDF](https://github.com/parallax/jsPDF) (CDN, cdnjs) for PDF export
- [Supabase](https://supabase.com) (optional) for persisted, shared master data + a
  generated-TDS log table, when deployed as a public web app
- FileMaker WebViewer JS bridge (optional) for embedding inside an existing FileMaker
  solution instead of / in addition to Supabase

## File structure

```
index.html                       the entire app
supabase-schema.sql               1) run first — app_state (master data), tds_records
auth-schema.sql                    2) login gate, profiles table, admin-approval trigger
workflow-schema.sql                 3) tds_requests (submit/verify/print request table)
email-confirm-schema.sql             4) hide unconfirmed signups from the approval queue
permissions-schema.sql                5) roles/permissions
users-table-schema.sql                 6) name/department/position/active
granular-master-data-permissions.sql    7) split Products/Rules/Alloy Properties - run last
README.md                        this file
```

## Integration modes (auto-detected, in priority order)

The app checks its environment at load time and picks the first available option:

1. **FileMaker** — if `window.FileMaker` exists (i.e. it's embedded in a FileMaker
   WebViewer with "Allow JavaScript to perform FileMaker scripts" on), master data
   load/save and generated-TDS logging all route through FileMaker scripts. See the
   contract documented in the `FILEMAKER INTEGRATION BRIDGE` comment block in
   `index.html` — a FileMaker developer needs to build three scripts:
   `TDS - Get Master Data`, `TDS - Save Master Data`, `TDS - Save Generated Record`.
2. **Supabase** — if `SUPABASE_URL` / `SUPABASE_ANON_KEY` are filled in (see below)
   and the Supabase JS client loaded successfully, master data and the TDS log persist
   there instead. This is the mode for the public Vercel deployment.
3. **Claude artifact storage** (`window.storage`) — only present when this file is
   opened inside Claude.ai's artifact viewer. Useful for testing/iterating with Claude
   directly, not for the live deployment.
4. **In-memory only** — final fallback. Works fully for a single session; nothing
   persists after a reload. This is what you'll see if you open `index.html` locally
   as a plain file with no Supabase credentials configured.

## Setup — Supabase (for the live web deployment)

1. In your Supabase project: **SQL Editor → New Query**, paste the contents of
   `supabase-schema.sql`, run it. This creates `app_state` (master data) and
   `tds_records` (generated TDS log).
2. Run `auth-schema.sql` next, in the same SQL editor. This adds the `profiles`
   table and the login-gate RLS policies described in **Account access** below —
   without it, `supabase-schema.sql`'s tables are still wide open to anyone with
   the anon key, not just approved signed-in users.
3. Run `workflow-schema.sql` next. This creates `tds_requests` (the submit/verify/
   print request table) — see **The submit → verify → print workflow** below.
4. Run `email-confirm-schema.sql` next. Adds `profiles.email_confirmed` so the
   Admin approval queue only ever shows a signup once the requestor has proven they
   own that email address (clicked Supabase's confirmation link) — otherwise anyone
   could type someone else's email into the signup form and show up as "pending."
5. Run `permissions-schema.sql` next. This replaces the department column with the
   full role/permission system — see **Roles & permissions** above.
6. Run `users-table-schema.sql` next. Adds `full_name`/`department`/`position`/
   `active` to `profiles` — see **Users** above.
7. Run `granular-master-data-permissions.sql` last. Splits `products`/`rules`/
   `alloy_properties` into separate, database-enforced permission objects — see
   **Roles & permissions** above.
8. In your Supabase project: **Settings → API**, copy the **Project URL** and the
   **`anon` `public`** key (never the `service_role` key).
9. In `index.html`, find:
   ```js
   const SUPABASE_URL = "";
   const SUPABASE_ANON_KEY = "";
   ```
   and paste both values in. It's expected/normal for the anon key to be visible in
   this file once deployed — Supabase's RLS policies are what actually gate access,
   not secrecy of this key.

## Deployment — GitHub + Vercel

1. Push this repo to GitHub (`index.html` at the root).
2. In Vercel: **Add New → Project → Import** the repo. No build configuration needed —
   Vercel serves static HTML automatically.
3. Vercel gives you a live URL on deploy. Every push to the connected branch redeploys.

## Account access (Supabase Auth)

When Supabase is configured, the entire app sits behind a login screen — nothing
renders until the visitor is signed in with an **approved** account. This is a real
access control (enforced by Row Level Security on `app_state`/`tds_records`, not just
a UI overlay), separate from the role-based permissions described below.

- **Sign up**: email + password, via the Sign Up tab on the login screen. Supabase
  sends a confirmation email the user must click before they can sign in.
- **Approval**: every new signup lands with `status = 'pending'` in the `profiles`
  table (see `auth-schema.sql`) and cannot sign in to see the app until approved.
  The **super admin** (`nizar.a.mansour@gmail.com`, hardcoded in `index.html` as
  `SUPER_ADMIN_EMAIL`) sees a "User Approvals" panel at the top of the Admin tab
  listing every pending signup, with Approve/Reject buttons. The super admin's own
  signup is auto-approved by a database trigger — otherwise there'd be no one able
  to approve the first account.
- There's currently no in-app notification (email/push) to the super admin when a
  new signup arrives — they need to check the Approvals panel. Adding a real
  notification would need a transactional email provider (e.g. Resend) wired up via
  a Supabase Edge Function, which isn't set up.
- No "forgot password" flow is built yet; a locked-out user currently needs the
  super admin to reset their password from the Supabase dashboard (Auth > Users).
- Run `auth-schema.sql` once in the SQL editor (after `supabase-schema.sql`) to set
  up the `profiles` table, the approval trigger, and the RLS policies that require
  an approved session.

## Roles & permissions (FileMaker-style privilege sets)

Access control is **fully data-driven**, modeled after FileMaker's privilege sets —
see `permissions-schema.sql`. There is no hardcoded department enum in the code;
everything below is rows in the database, editable from **Admin → Roles &
Permissions** by anyone with the `manage_roles` script permission (the super admin
always has it).

- **`roles`** — privilege sets. Ships with Super Admin (system role, can't be
  deleted), QC Manager, QC Inspector, Production Manager, Production Inspector, and
  Sales, but the super admin can rename, add, or delete roles freely from the UI.
- **`permission_objects`** — a registry of protectable "data objects" (`products`,
  `rules`, `alloy_properties`, `tds_requests`) and "scripts" (`verify_tds`,
  `reset_master_data`, `manage_roles`, `manage_users` — named actions that aren't
  simple CRUD, like FileMaker script permissions gating a button).
- **`role_object_permissions`** — View / Create / Edit / Delete per role × data
  object. Products, Conditions & Remarks Rules, and Alloy Properties are three
  separate objects (see `granular-master-data-permissions.sql`) — a role can edit
  Products without touching Alloy Properties, and vice versa, with **real
  database-level enforcement**: `app_state` (where all three actually live, as one
  JSON blob in one row — this app has no separate physical table per section) has a
  trigger, `check_master_data_section_permissions()`, that inspects which top-level
  key of the JSON a given save actually changed and requires edit rights on that
  specific object. A role with `products.edit` but not `rules.edit` genuinely cannot
  get a rules change through, even though both live in the same row.
- **`role_script_permissions`** — Can-run per role × script.
- `profiles.role_id` replaces the old fixed department column.

**Adding a user, adding a role, or changing who can do what is a pure data edit —
zero code.** The one time code is still needed is inventing a genuinely new
feature/table/script in the first place; wiring its permission is then one generic
`canEdit('key')` / `canRunScript('key')` call plus one `permission_objects` row, not
bespoke per-role logic.

The client loads its own role's permissions once at login (`loadPermissions()`) into
an in-memory map for fast UI gating; the real security boundary is the matching
Postgres RLS policies, which call `has_object_permission()` / `has_script_permission()`
SQL functions server-side — the same pattern the old passphrase/department system
used, just generalized.

## Users

**Admin → Users** (`usersPanel`, gated by the `manage_users` script permission — see
`users-table-schema.sql`) is the full roster: every account that has ever registered
via Sign Up, editable in one table.

- **Name, Department, Position** — free-text, informational only. They describe the
  person (e.g. "Hari" / "Quality Control" / "QC Manager"); they don't grant anything.
  Name is also collected at signup now (`profiles.full_name`, via
  `signUp({ options: { data: { full_name } } })`) but stays editable here for
  existing accounts or typo fixes.
- **Role** — the actual privilege set (see **Roles & permissions** above). This is
  what controls what the user can do; it's normal for it to say something different
  from Position (e.g. Position "Senior QC Inspector", Role "QC Inspector").
- **Status** — Pending approval / Approved / Rejected, with Approve/Reject actions
  inline for pending rows (same action as the sidebar's Pending Signups list; both
  stay in sync).
- **Active** — `profiles.active`, independent of Status. Lets you suspend an
  *already-approved* user's access (they're blocked at both the RLS layer and the
  login gate, with a distinct "Account deactivated" message) without demoting them
  or losing their role/history — useful for someone on leave or who left, versus
  Rejected which is for a signup that should never have been approved at all.
- **User since** — `created_at`.

## The submit → verify → print workflow

- **TDS Generator doesn't print directly.** Filling the form and clicking "Submit
  for Verification" freezes the current form state — resolved alloy/temper
  properties, thickness band values, tolerances, and matching remarks — into a
  `tds_requests` row with `status = 'pending'`. That frozen `snapshot` is what ever
  gets printed later, so a subsequent master-data edit can't retroactively change an
  already-submitted sheet. Requires `tds_requests.create`.
- **Verify Requests tab** (visible to whichever role(s) have the `verify_tds` script
  permission) lists pending requests from everyone and lets a reviewer Verify or
  Reject (with a reason) — this only touches the request's status, never master data.
- **My Requests tab** lists the signed-in user's own submissions with status. A
  verified request shows a "Print / Save PDF" button that paints and exports the
  frozen `snapshot`, not live data, and records `printed_at`/`pdf_base64` back onto
  the request row.
- The **Comparator tab is unaffected** — it still prints directly, since it's a
  side-by-side reference sheet rather than a certified TDS tied to an order.

## Data model notes for whoever continues this

- **Thickness bands are independent per alloy+temper** (`alloy.tempers[temperKey].
  thicknessBands`, each `{min,max,tensileMin,tensileMax,yieldMin,elong,bend,verified}`)
  — no shared grid across alloys. Each alloy+temper's QC data is entered straight from
  its own ASTM copy in Admin → Alloy Properties, sorted and overlap-checked within
  that alloy+temper only.
- **Tempers ending in H2x** are ASTM B209 Note C "optional supplier" designations.
  Which base temper (H1x or H3x) they're equivalent to **varies by alloy** — e.g. for
  AA5005 specifically, H22 pairs with H32 (not H12), because that alloy uniquely has
  both series. See each temper's `equivNote` field.
- **Values marked `verified:false`** are best-available placeholders pending
  confirmation against a licensed ASTM B209 / EN 485-2 / ANSI H35.2 copy — they render
  in amber italics in the library rather than being presented as fact. Don't silently
  flip these to `true` without actually checking a source.
- **Rules** (Admin → Conditions & Remarks) key off Product/Alloy/Temper/Thickness/
  Width and each set a `label` + `remark`. Multiple rules sharing the same `label`
  combine their remarks into one row if they all match simultaneously (not
  first-match-wins) — this was a deliberate design choice, see conversation history
  if it needs revisiting.
- **Width/thickness tolerance lookups** (ANSI H35.2 Tables 7.7a / 7.11) are only
  confirmed for specific metric brackets (documented inline near
  `ANSI_WIDTH_BRACKETS_7_7A` / `ANSI_WIDTH_BRACKETS_7_11`). Widths outside those
  brackets correctly report "not verified" rather than guessing — extending coverage
  requires sourcing the other brackets from a licensed ANSI H35.2 copy.

## Known open items

- Supabase RLS policies are currently wide open (anon read/write) — fine for internal
  use behind an unlisted URL, worth tightening with Supabase Auth if this becomes more
  broadly accessible.
- FileMaker-side scripts (`TDS - Get/Save Master Data`, `TDS - Save Generated Record`)
  are not yet built — the JS-side contract is ready and documented in `index.html`.
- Several alloy/temper/thickness-range combinations are still `verified:false`
  placeholders — see the amber-flagged rows in Admin → Thickness Bands.
