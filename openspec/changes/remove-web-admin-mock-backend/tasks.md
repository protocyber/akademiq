## 1. Prerequisite

- [x] 1.1 Confirm `add-platform-overview-and-plan-read` has landed and `GET /overview`, `GET /plans`, and unfiltered `GET /users` each return `200` with an operator token
- [x] 1.2 Confirm the backend stack reachable from the dev machine (platform-service `:8087`, iam-service `:8081`)

## 2. Configuration

- [x] 2.1 Set `NUXT_PUBLIC_IAM_BASE_URL` and `NUXT_PUBLIC_PLATFORM_BASE_URL` in `apps/web-admin/.env.example` to the proxied admin origin
- [x] 2.2 Set the same values in the local gitignored `apps/web-admin/.env`
- [x] 2.3 Rewrite the misleading comment in `nuxt.config.ts:38-42` that tells the reader to leave base URLs empty to reach the bundled mocks
- [x] 2.4 Verify `app/lib/api/client.ts` needs no change — `baseFor()` already composes absolute base URLs correctly

## 3. Remove the mock backend

- [x] 3.1 Delete `apps/web-admin/server/api/` (17 route handlers across iam auth, tenants, users, plans, audit, overview, me)
- [x] 3.2 Delete `apps/web-admin/server/utils/mock.ts` and the now-empty `server/` tree
- [x] 3.3 Grep the app for references to removed server routes or `mockDb` and confirm none remain

## 4. Users screen becomes a directory

- [x] 4.1 In `app/lib/queries/users.ts`, drop the `enabled` gate that requires a non-empty email and add `page`/`page_size` params
- [x] 4.2 Make `email` an optional filter in the query key and request path so an empty value lists the directory
- [x] 4.3 Update `app/pages/users/index.vue` to render the listing on load, keeping the email input as a filter and the existing empty-state for no matches
- [x] 4.4 Confirm the loading indicator convention from `web-admin-foundation` is preserved for the initial listing query

## 5. E2E suite

- [x] 5.1 Rewrite `tests/e2e/operator-flow.spec.ts` as read-only: login → tenants list → tenant detail → audit view
- [x] 5.2 Read operator credentials from environment variables instead of the hard-coded mock pair
- [x] 5.3 Replace assertions on mock fixture names (e.g. `SMA Negeri 1 Surabaya`) with structural assertions that hold on any environment
- [x] 5.4 Remove the suspend/reactivate assertions so the suite never mutates real tenant state
- [x] 5.5 Fix `playwright.config.ts` `webServer.command` from `npm run dev` to the pnpm equivalent

## 6. Verification

- [x] 6.1 Run the app and confirm Overview, Plans, Tenants, Users, and Audit all render live data
- [ ] 6.2 Open the app on the local dev origin and on the proxied origin and confirm identical behaviour — skipped: the Traefik-proxied origin (akademiq-admin.dev.sby.test) does not resolve from this sandbox; verified equivalent by config only (same base URLs point both origins at the same backend). Needs manual confirmation from a machine with DNS/hosts access to the proxy.
- [x] 6.3 Confirm the login form now rejects a wrong password (previously any non-empty password succeeded against the mock)
- [x] 6.4 Run `pnpm test` (unit) in `apps/web-admin` and confirm no regression from the removed server routes
- [x] 6.5 Run `pnpm test:e2e` against the live stack and confirm the rewritten flow passes
- [x] 6.6 Confirm no tenant was suspended or otherwise mutated by the test run
