## 1. Login loading through navigation (#3)

- [ ] 1.1 Add a local "navigating" flag set true on successful login before `router.push`
- [ ] 1.2 Include the flag in the button's `disabled`/`loading` so it stays loading until the route changes
- [ ] 1.3 Ensure the flag is not set (or is reset) on the failure path so retry works
- [ ] 1.4 Verify both fast-path (single tenant → dashboard) and tenant-select navigations keep the button loading

## 2. Proactive background refresh (#4)

- [ ] 2.1 Add a helper to read `exp` from the access token (reuse `lib/auth/access-claims.ts`)
- [ ] 2.2 Add a background scheduler that arms a timer to fire shortly before `exp` and calls the existing `tryRefresh()`
- [ ] 2.3 (Re)arm the timer in `setTokens` and on successful refresh; clear it in `clearTokens`/`clearAllTokens`
- [ ] 2.4 Confirm proactive + reactive refresh share the single-flight `refreshInFlight` guard (no overlap)
- [ ] 2.5 Guard for SSR (`typeof window`) and avoid arming when no refresh token is present

## 3. Email verification indicator (#10)

- [ ] 3.1 Surface `email_verified` in the edit-user form with a check/alert icon and an accessible label
- [ ] 3.2 Factor a small reusable indicator if email is shown verified/unverified in more than one place
- [ ] 3.3 Ensure state is not conveyed by color alone (label/title present)

## 4. Verify

- [ ] 4.1 `pnpm lint` and `pnpm build` (or typecheck) pass
- [ ] 4.2 Manually verify: rapid double-click on login submit cannot fire a second request during navigation
- [ ] 4.3 Manually verify (shortened TTL or mock): session refreshes in the background before expiry without a visible error
- [ ] 4.4 Manually verify: verified vs unverified email render the correct indicator
