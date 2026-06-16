## 1. Theming engine

- [x] 1.1 Add `next-themes` to `apps/web` dependencies
- [x] 1.2 Mount ThemeProvider (attribute="class", defaultTheme="system", enableSystem) in `src/app/layout.tsx`; add the no-flash script/setup `next-themes` provides
- [x] 1.3 Verify `globals.css` `.dark` token block is complete for all tokens used by shell surfaces (extend if any are missing)

## 2. Theme switcher

- [x] 2.1 Build a 3-state switcher component (light/dark/system) using existing `DropdownMenu`/`Button` primitives
- [x] 2.2 Place it in the top-right header in `components/layout/sidebar-layout.tsx`, adjacent to the user control
- [x] 2.3 Reflect the active mode in the control and persist selection via `next-themes`

## 3. Top-right avatar dropdown (#6)

- [x] 3.1 Replace the inert header avatar with a `DropdownMenu` trigger
- [x] 3.2 Dropdown items: user name (header), link to user profile, logout action wired to the existing `onLogout`/`isLoggingOut`
- [x] 3.3 Remove the bottom-left sidebar footer user block (name/email/logout)
- [x] 3.4 Keep mobile (Sheet) parity — identity/logout reachable on small screens

## 4. Token-ize shell colors

- [x] 4.1 Audit `sidebar-layout.tsx` and header for hardcoded `slate-*`/palette colors; replace theme-following surfaces with semantic tokens
- [x] 4.2 Document any intentionally-fixed surface (e.g. permanently dark sidebar) as a deliberate exception
- [x] 4.3 Spot-check key screens (dashboard, settings/users, login) render correctly in both themes

## 5. Confirmation audit (#8)

- [x] 5.1 Grep for native `window.confirm`/`alert(`/`confirm(` across `apps/web/src`; list any remaining
- [x] 5.2 Replace any remaining native confirms with `ConfirmDialog`/`AlertDialog`
- [x] 5.3 Confirm destructive flows use the `destructive` variant and loading state

## 6. Verify

- [x] 6.1 `pnpm lint` and `pnpm build` (or typecheck) pass
- [x] 6.2 Manually verify: theme persists across reload, system mode follows OS, no flash-of-wrong-theme
- [x] 6.3 Manually verify: avatar dropdown opens, profile link + logout work, sidebar footer gone
