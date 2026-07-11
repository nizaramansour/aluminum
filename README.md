# Alumill TDS Generator

Interactive Technical Data Sheet generator, alloy comparator, and admin-editable
master data system for Alumill Tech Gulf LLC's aluminium coil/sheet products.

Single-file web app (`index.html`) — no build step, no framework. Runs standalone
in any browser, and auto-upgrades its storage/integration layer depending on where
it's deployed (see **Integration modes** below).

## Features

- **TDS Generator** — pick product, alloy, temper, thickness (mm), width (mm), units
  (metric/imperial/both); generates a letterhead-branded, print/PDF-ready technical
  data sheet with tensile/yield/elongation/bend looked up from the shared thickness-
  range grid, ANSI H35.2 dimensional tolerances, and condition-based remarks (e.g.
  tension-leveling flatness rules, slit-coil edge-ripple notes by width).
- **Alloy Comparator** — pick any alloy + temper combination, add to a comparison
  list, generates a side-by-side mechanical/chemical properties sheet (no dimensional
  tolerances).
- **Admin tab** (passphrase-gated, see below) — edit Products, Conditions & Remarks
  Rules, and the full Alloys/Chemistry/Thickness-Bands library, all from the browser.
  Every alloy/temper block is independently collapsible.
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
index.html            the entire app
supabase-schema.sql    run this once in Supabase's SQL editor before deploying
README.md             this file
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
3. In your Supabase project: **Settings → API**, copy the **Project URL** and the
   **`anon` `public`** key (never the `service_role` key).
4. In `index.html`, find:
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
a UI overlay), separate from the Admin-tab passphrase below.

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

## Admin access (master-data editing)

Separately from the login gate above, the Admin tab's Products/Rules/Alloys editing
is gated by a passphrase constant near the top of the script:

```js
const ADMIN_PASSPHRASE = "alumill-qc";
```

**This is a soft gate only** — it prevents accidental edits by a signed-in user, not
unauthorized access, since anyone with view-source access to the deployed file can
read this constant. Real access control for *reaching the app at all* is handled by
the Supabase Auth login above; this passphrase is just a second speed-bump in front
of master-data edits specifically, for whoever is already signed in and approved.

## Data model notes for whoever continues this

- **Thickness ranges are shared across all alloys** (`DATA.thicknessRanges`), editable
  once in Admin → Thickness Bands. Each alloy/temper just fills in tensile/yield/
  elongation/bend against that shared grid (`alloy.tempers[temperKey].values[rangeId]`)
  rather than maintaining its own range boundaries — this reflects that ANSI/ASTM
  gauge steps are standardized across non-aerospace alloys.
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
