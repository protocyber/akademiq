## 1. Theming engine

- [ ] 1.1 Add `next-themes` to `apps/web` dependencies
- [ ] 1.2 Mount `ThemeProvider` (attribute="class", defaultTheme="system", enableSystem) in `src/app/layout.tsx`; add the no-flash script/setup `next-themes` provides
- [ ] 1.3 Verify `globals.css` `.dark` token block is complete for all tokens used by shell surfaces (extend if any are missing)

## 2. Theme switcher

- [ ] 2.1 Build a 3-state switcher component (light/dark/system) using existing `DropdownMenu`/`Button` primitives
- [ ] 2.2 Place it in the top-right header in `components/layout/sidebar-layout.tsx`, adjacent to the user control
- [ ] 2.3 Reflect the active mode in the control and persist selection via `next-themes`

## 3. Top-right avatar dropdown (#6)

- [ ] 3.1 Replace the inert header avatar with a `DropdownMenu` trigger
- [ ] 3.2 Dropdown items: user name (header), link to user profile, logout action wired to the existing `onLogout`/`isLoggingOut`
- [ ] 3.3 Remove the bottom-left sidebar footer user block (name/email/logout)
- [ ] 3.4 Keep mobile (Sheet) parity — identity/logout reachable on small screens

## 4. Token-ize shell colors

- [ ] 4.1 Audit `sidebar-layout.tsx` and header for hardcoded `slate-*`/palette colors; replace theme-following surfaces with semantic tokens
- [ ] 4.2 Document any intentionally-fixed surface (e.g. permanently dark sidebar) as a deliberate exception
- [ ] 4.3 Spot-check key screens (dashboard, settings/users, login) render correctly in both themes

## 5. Confirmation audit (#8)

- [ ] 5.1 Grep for native `window.confirm`/`alert(`/`confirm(` across `apps/web/src`; list any remaining
- [ ] 5.2 Replace any remaining native confirms with `ConfirmDialog`/`AlertDialog`
- [ ] 5.3 Confirm destructive flows use the `destructive` variant and loading state

## 6. Verify

- [ ] 6.1 `pnpm lint` and `pnpm build` (or typecheck) pass
- [ ] 6.2 Manually verify: theme persists across reload, system mode follows OS, no flash-of-wrong-theme
- [ ] 6.3 Manually verify: avatar dropdown opens, profile link + logout work, sidebar footer gone
