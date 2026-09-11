## Why

Two related onboarding/context issues degrade the first-run experience for a
new tenant and the settings UX for school profile.

**Issue 1 — global scope empty during onboarding (issue #9).** When a new
tenant is registered, no academic year/term/curriculum exists.
`AcademicScopeProvider` resolves `yearId` to `null` (correct behavior), and
the dashboard shows `EmptyStateNoYear` (a manual nudge to
`/settings/academic/years`). However, the user reports that the UI "loses
context" — the global curriculum scope is empty even in scenarios where an
academic year has just been created and activated. Investigation reveals a
**latent bug**: the provider **writes** its selection to `localStorage`
(`akademiq.academic_scope.<tenantId>`) but **never reads it back** on mount.
Every page load re-resolves from scratch, ignoring the user's last
selection. Combined with the empty-onboarding data, this makes the scope feel
broken.

**Issue 2 — school profile is always-editable inline (issue #10).** The
`/settings/school-profile` page renders a `Card` containing a permanently-
editable `react-hook-form`. There is no view mode and no edit modal. The
product request is to show the profile in **read-only view mode** by default,
with an "Edit" button that opens a modal/sheet containing the form.

## What Changes

- **Fix the localStorage read-back bug in `AcademicScopeProvider`.** On mount
  (after auth resolves), read the persisted scope from
  `localStorage[akademiq.academic_scope.<tenantId>]` and restore it, falling
  back to the resolver defaults if the persisted value is stale (e.g. the
  year/term/curriculum no longer exists).
- **Broaden query invalidation after year/term creation and activation.**
  When a user creates and activates a year (and subsequently a term) during
  onboarding, the academic scope provider's underlying queries must
  re-fetch so the scope selectors populate without requiring a page reload.
  This overlaps with Cluster B's invalidation fix but is broader: it covers
  create + transition + curriculum-version creation.
- **School profile: view mode + edit modal.** Refactor
  `/settings/school-profile` to render a read-only display of the profile by
  default. Add an "Edit" button in the Card header that opens a `Dialog` (or
  `Sheet`) containing the existing `SchoolProfileForm`. On successful submit,
  the modal closes and the view refreshes.

## Capabilities

### Modified Capabilities
- `web-onboarding-ui`: academic scope provider restores persisted selection
  on mount; school profile page shows view mode with edit modal.

## Impact

- **Web** (`apps/web`):
  - `components/providers/academic-scope-provider.tsx`: add localStorage
    read-back + stale-validation.
  - `app/settings/school-profile/page.tsx`: split into view-mode display +
    edit modal; extract or reuse `SchoolProfileForm` inside a `Dialog`.
  - Query invalidation may be touched in `use-academic-config.ts` (overlaps
    with Cluster B — coordinate to avoid duplicate work).
- **No backend changes.**
- **No migration.**
