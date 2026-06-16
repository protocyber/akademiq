## Why

The app shell predates the design system it now ships. Three gaps:

- **No dark mode.** The Tailwind config already sets `darkMode: ["class"]` and
  `globals.css` already defines a complete `.dark { --… }` token block, but
  nothing toggles the class — `next-themes` is not installed and there is no
  provider or switcher. The Stitch design kit ships dark-mode comps
  (`docs/internal/stitch_design/*_dark_mode/`) we are not honoring.
- **User identity lives in the wrong corner.** The signed-in user's name and the
  logout button sit at the bottom-left of the sidebar
  (`components/layout/sidebar-layout.tsx`), not the conventional top-right. There
  is a top-right avatar circle in the header but it is inert (no menu).
- **Confirmation UX is inconsistent.** A reusable `ConfirmDialog`
  (`components/ui/confirm-dialog.tsx`) already exists, but we have no guarantee
  every destructive/confirm flow uses it rather than a native `window.confirm`.

Doing this **first** matters: two large redesigns
(`redesign-academic-config-tables`, `redesign-academic-ops-tables`) are at 0% of
64 combined tasks. If dark mode lands after them, every new table is built
light-only and needs a second dark pass. Landing theming first makes that new UI
dark-ready by construction.

## What Changes

- **NEW dark-mode engine** — install `next-themes`, add a `ThemeProvider` at the
  root layout, and a **3-state switcher (light / dark / system)** placed in the
  top-right header next to the user control. Theme is class-based and respects
  the OS preference in `system` mode, persisted across reloads, with no
  flash-of-wrong-theme on first paint.
- **MODIFIED app shell** — move the user's name and logout out of the
  bottom-left sidebar into a **top-right avatar dropdown**: avatar icon → menu
  containing the user's name, a link to the user profile, and a logout action.
  The bottom-left user block is removed.
- **MODIFIED color usage** — replace hardcoded palette colors in the shell
  (e.g. `bg-slate-900`/`text-slate-100` on the sidebar, header `bg-*`) with
  theme tokens where they should follow the theme; intentionally-permanent
  surfaces (the dark sidebar as a brand choice) are documented, not accidental.
- **AUDIT confirmations** — verify every confirm/alert flow routes through the
  shared `ConfirmDialog`/`AlertDialog`; replace any remaining native
  `window.confirm`/`alert`. (Current grep shows ~none, so this is a verification
  task, not a rebuild.)

## Capabilities

### New Capabilities

- `web-theming`: class-based light/dark/system theming for the web app — the
  `next-themes` provider, the persisted 3-state switcher, and the token contract
  that app surfaces follow.

### Modified Capabilities

- `web-auth-onboarding`: the app shell relocates the user identity + logout to a
  top-right avatar dropdown and exposes the theme switcher in the header.

## Impact

- **Web (`apps/web`):** add `next-themes` dependency; `ThemeProvider` in
  `src/app/layout.tsx`; new theme-switcher component; rework
  `components/layout/sidebar-layout.tsx` header (avatar dropdown) and remove the
  sidebar footer user block; token-ize hardcoded shell colors; audit confirm
  flows against `ConfirmDialog`.
- **No backend impact.**
- **Sequencing:** SHOULD merge before `redesign-academic-config-tables` and
  `redesign-academic-ops-tables` resume so new tables are dark-ready.
- **Out of scope:** the global academic-year selector (deferred — see
  `redesign-academic-config-tables`), per-page visual redesigns, and the date
  picker rework (`shared-input-polish`).
